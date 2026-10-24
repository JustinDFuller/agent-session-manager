import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import ResourceExtension
import SignPostIntegration

final class SpanHandle: @unchecked Sendable {
    fileprivate let span: any Span

    fileprivate init(_ span: any Span) {
        self.span = span
    }
}

final class TracingService: @unchecked Sendable {
    static let shared = TracingService()

    private let lock = NSLock()
    private var _isEnabled = false
    private var _tracer: (any Tracer)?
    private var _testCaptureEnabled = false
    private var _recordedEventsForTesting: [(name: String, attributes: [String: String])] = []

    private init() {}

    var recordedEventsForTesting: [(name: String, attributes: [String: String])] {
        lock.withLock { _recordedEventsForTesting }
    }

    func enableTestCapture() {
        lock.withLock { _testCaptureEnabled = true }
    }

    func resetForTesting() {
        lock.withLock {
            _testCaptureEnabled = false
            _recordedEventsForTesting = []
        }
    }

    var isEnabled: Bool {
        lock.withLock { _isEnabled }
    }

    private static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    @MainActor
    func configure(from settings: AppSettings) {
        guard settings.debugModeEnabled else {
            lock.withLock {
                _isEnabled = false
                _tracer = nil
            }
            return
        }

        let resource = DefaultResources().get().merging(
            other: Resource(attributes: [
                ResourceAttributes.serviceName.rawValue: .string("AgentSessionManager"),
                ResourceAttributes.serviceVersion.rawValue: .string(Self.appVersion),
            ])
        )

        let exporter: any SpanExporter = PerPaneSpanExporter(
            tracesDirectory: settings.resolvedTracingDirectoryURL,
            maxBytesPerFile: AppSettings.debugFileMaxBytes,
            resourceAttributes: resource.attributes.mapValues(\.description)
        )

        var builder = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter))

        builder = builder.add(spanProcessor: OSSignposterIntegration())

        let provider = builder.build()

        let tracer = provider.get(
            instrumentationName: "AgentSessionManager",
            instrumentationVersion: "1.0.0"
        )

        lock.withLock {
            _isEnabled = true
            _tracer = tracer
        }
    }

    func startSpan(_ name: String, attributes: [String: String] = [:]) -> SpanHandle? {
        AppLog.log(name, level: .debug, attributes: attributes)
        guard let tracer = lock.withLock({ _isEnabled ? _tracer : nil }) else { return nil }
        let span = tracer.spanBuilder(spanName: name).startSpan()
        for (key, value) in attributes { span.setAttribute(key: key, value: value) }
        return SpanHandle(span)
    }

    func end(handle: SpanHandle?, attributes: [String: String] = [:]) {
        guard let handle else { return }
        AppLog.log(handle.span.name, level: .debug, attributes: attributes)
        for (key, value) in attributes { handle.span.setAttribute(key: key, value: value) }
        handle.span.end()
    }

    func record(
        _ name: String,
        parent: SpanHandle? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        attributes: [String: String] = [:]
    ) {
        AppLog.log(name, level: .debug, attributes: attributes)
        let (tracer, captureEnabled) = lock.withLock { (_isEnabled ? _tracer : nil, _testCaptureEnabled) }
        if captureEnabled {
            lock.withLock { _recordedEventsForTesting.append((name: name, attributes: attributes)) }
        }
        guard let tracer else { return }
        let builder = tracer.spanBuilder(spanName: name)
        if let startTime { _ = builder.setStartTime(time: startTime) }
        if let parent { _ = builder.setParent(parent.span.context) }
        let span = builder.startSpan()
        for (key, value) in attributes { span.setAttribute(key: key, value: value) }
        if let endTime {
            span.end(time: endTime)
        } else {
            span.end()
        }
    }

    @discardableResult
    func withSpan<T: Sendable>(
        _ name: String,
        parent: SpanHandle? = nil,
        attributes: [String: String] = [:],
        _ body: () throws -> T
    ) rethrows -> T {
        AppLog.log(name, level: .debug, attributes: attributes)
        guard let tracer = lock.withLock({ _isEnabled ? _tracer : nil }) else {
            return try body()
        }
        let builder = tracer.spanBuilder(spanName: name)
        if let parent { _ = builder.setParent(parent.span.context) }
        return try builder.withActiveSpan { span in
            for (key, value) in attributes { span.setAttribute(key: key, value: value) }
            return try body()
        }
    }

    @discardableResult
    @MainActor
    func withSpan<T: Sendable>(
        _ name: String,
        parent: SpanHandle? = nil,
        attributes: [String: String] = [:],
        _ body: @MainActor @Sendable () async throws -> T
    ) async rethrows -> T {
        AppLog.log(name, level: .debug, attributes: attributes)
        guard let tracer = lock.withLock({ _isEnabled ? _tracer : nil }) else {
            return try await body()
        }
        let builder = tracer.spanBuilder(spanName: name)
        if let parent { _ = builder.setParent(parent.span.context) }
        let span = builder.startSpan()
        for (key, value) in attributes { span.setAttribute(key: key, value: value) }
        do {
            let result = try await body()
            span.end()
            return result
        } catch {
            span.status = .error(description: error.localizedDescription)
            span.end()
            throw error
        }
    }
}
