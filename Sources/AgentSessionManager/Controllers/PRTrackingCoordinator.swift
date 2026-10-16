import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PRTrackingCoordinator {
    static let shared = PRTrackingCoordinator()

    struct QueryResult {
        var outData: Data
        var exitStatus: Int32
        var result: String
        var failure: GitHubCLIFailure?
        var inputFailure: ChildProcessInputWriteFailure?
        var count: Int
        var startTime: Date
        var endTime: Date
    }

    struct SubscriberRecord {
        var workingDirectory: String
        var owner: String?
        var repo: String?
        var branchName: String?
        var paneName: String
        var tabID: UUID
        var tabName: String
        var lastData: PullRequest?
        var status: PRTrackingStatus
        var callback: (PullRequest?) -> Void
        var statusCallback: (PRTrackingStatus) -> Void
        var isActive: Bool

        init(
            workingDirectory: String,
            owner: String? = nil,
            repo: String? = nil,
            branchName: String? = nil,
            paneName: String = "",
            tabID: UUID = UUID(),
            tabName: String = "",
            lastData: PullRequest? = nil,
            status: PRTrackingStatus = .loading,
            callback: @escaping (PullRequest?) -> Void,
            statusCallback: @escaping (PRTrackingStatus) -> Void = { _ in },
            isActive: Bool
        ) {
            self.workingDirectory = workingDirectory
            self.owner = owner
            self.repo = repo
            self.branchName = branchName
            self.paneName = paneName
            self.tabID = tabID
            self.tabName = tabName
            self.lastData = lastData
            self.status = status
            self.callback = callback
            self.statusCallback = statusCallback
            self.isActive = isActive
        }
    }

    var subscribers: [UUID: SubscriberRecord] = [:]
    private(set) var cycleTimer: Timer?
    var effectiveInterval: TimeInterval = 30
    private var activeBatchTask: Task<Void, Never>?
    private var cycleToken: UInt64 = 0
    private var currentCycleHandle: SpanHandle?
    private(set) var isPaused = false
    private(set) var isBackgrounded = false
    @ObservationIgnored nonisolated(unsafe) private var appStateObservers: [Any] = []

    init() {
        let center = NotificationCenter.default
        appStateObservers.append(
            center.addObserver(
                forName: NSApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
            }
        )
        appStateObservers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.resume() }
            }
        )
    }

    deinit {
        for observer in appStateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func subscribe(
        paneID: UUID,
        workingDirectory: String,
        isActive: Bool,
        paneName: String = "",
        tabID: UUID = UUID(),
        tabName: String = "",
        onPRStatus: @escaping (PRTrackingStatus) -> Void = { _ in },
        onPRData: @escaping (PullRequest?) -> Void
    ) {
        let previous = subscribers[paneID].flatMap { $0.workingDirectory == workingDirectory ? $0 : nil }
        let record = SubscriberRecord(
            workingDirectory: workingDirectory,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            lastData: previous?.lastData,
            status: previous?.status ?? .loading,
            callback: onPRData,
            statusCallback: onPRStatus,
            isActive: isActive
        )
        if previous?.lastData != nil { onPRData(previous?.lastData) }
        onPRStatus(record.status)
        subscribers[paneID] = record
        let task = Process()
        let outPipe = Pipe()
        task.executableURL = URL(filePath: "/usr/bin/git")
        task.arguments = ["-C", workingDirectory, "remote", "get-url", "origin"]
        task.standardOutput = outPipe
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let raw = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                let (owner, repo) = Self.parseOwnerRepo(from: raw)
            else {
                Task { @MainActor [weak self] in self?.setStatus(.unavailable, for: paneID) }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.subscribers[paneID]?.owner = owner
                self.subscribers[paneID]?.repo = repo
                self.runCycle()
            }
        }
        do {
            try task.run()
        } catch {
            setStatus(.unavailable, for: paneID)
        }
        guard !isPaused, cycleTimer == nil else { return }
        runCycle()
        scheduleCycleTimer()
    }

    func unsubscribe(paneID: UUID) {
        subscribers.removeValue(forKey: paneID)
        if subscribers.isEmpty {
            cycleTimer?.invalidate()
            cycleTimer = nil
            activeBatchTask?.cancel()
            activeBatchTask = nil
        }
    }

    func setActive(paneID: UUID, isActive: Bool) {
        subscribers[paneID]?.isActive = isActive
    }

    func retry(paneID: UUID) {
        guard subscribers[paneID] != nil else { return }
        setStatus(.loading, for: paneID)
        runCycle()
    }

    func pause() {
        isBackgrounded = true
        let settings = SettingsPersistence.prPollingSettings()
        if !settings.backgroundRefreshEnabled {
            isPaused = true
            cycleTimer?.invalidate()
            cycleTimer = nil
            activeBatchTask?.cancel()
            activeBatchTask = nil
        } else {
            scheduleCycleTimer()
        }
    }

    func resume() {
        isBackgrounded = false
        if isPaused {
            isPaused = false
            guard !subscribers.isEmpty else { return }
            runCycle()
            scheduleCycleTimer()
        } else {
            scheduleCycleTimer()
        }
    }

    private func scheduleCycleTimer() {
        cycleTimer?.invalidate()
        let settings = SettingsPersistence.prPollingSettings()
        if isBackgrounded {
            effectiveInterval = max(15, TimeInterval(settings.backgroundIntervalSeconds))
        } else {
            effectiveInterval = max(15, TimeInterval(settings.intervalSeconds))
        }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.subscribers.isEmpty else { return }
                self.runCycle()
                self.scheduleCycleTimer()
            }
        }
    }

    private func runCycle() {
        guard SettingsPersistence.isPRTrackingEnabled() else {
            for paneID in subscribers.keys { setStatus(.disabled, for: paneID) }
            return
        }

        TracingService.shared.end(handle: currentCycleHandle, attributes: ["result": "superseded"])
        currentCycleHandle = nil

        activeBatchTask?.cancel()
        activeBatchTask = nil
        cycleToken += 1
        let token = cycleToken

        let paneIDs = subscribers.keys.filter {
            subscribers[$0]?.owner != nil && subscribers[$0]?.repo != nil
        }
        guard !paneIDs.isEmpty else { return }

        let cycleHandle = TracingService.shared.startSpan(
            "pr.poll.cycle",
            attributes: ["pane_count": String(paneIDs.count)])
        currentCycleHandle = cycleHandle
        guard let cycleHandle else { return }

        Task { @MainActor [weak self] in
            guard let self, self.cycleToken == token else {
                TracingService.shared.end(handle: cycleHandle, attributes: ["result": "cancelled"])
                return
            }

            await withTaskGroup(of: (UUID, String?).self) { group in
                for paneID in paneIDs {
                    guard let cwd = self.subscribers[paneID]?.workingDirectory else { continue }
                    group.addTask {
                        let branch = await Self.fetchBranch(workingDirectory: cwd)
                        return (paneID, branch)
                    }
                }
                for await (paneID, branch) in group {
                    self.subscribers[paneID]?.branchName = branch
                    if branch == nil || branch?.isEmpty == true || branch == "HEAD" {
                        self.setStatus(.unavailable, for: paneID)
                    } else {
                        self.setStatus(.loading, for: paneID)
                    }
                }
            }

            guard self.cycleToken == token else {
                TracingService.shared.end(handle: cycleHandle, attributes: ["result": "cancelled"])
                return
            }
            self.dispatchBatchQuery(token: token, cycleHandle: cycleHandle)
        }
    }

    private func dispatchBatchQuery(token: UInt64, cycleHandle: SpanHandle) {
        guard SettingsPersistence.isPRTrackingEnabled() else { return }
        let query = buildBatchQuery()
        guard !query.isEmpty else { return }
        let settings = SettingsPersistence.prPollingSettings()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: ["query": query]) else { return }
        let count = subscribers.values.filter(Self.isQueryEligible).count
        let queryStartTime = Date()
        activeBatchTask = Task { [weak self] in
            let result = await GitHubCLIRunner.shared.run(
                arguments: ["api", "graphql", "--include", "--input", "-"],
                stdin: jsonData,
                timeout: Double(settings.timeoutSeconds))
            guard let self else { return }
            self.handleBatchResponse(
                QueryResult(
                    outData: result.stdout, exitStatus: result.exitCode ?? -1,
                    result: result.failure?.rawValue ?? "ok", failure: result.failure,
                    inputFailure: result.inputFailure,
                    count: count, startTime: queryStartTime, endTime: Date()), token: token, cycleHandle: cycleHandle)
        }
    }

    func handleBatchResponse(_ queryResult: QueryResult, token: UInt64, cycleHandle: SpanHandle? = nil) {
        guard cycleToken == token else {
            TracingService.shared.end(handle: cycleHandle, attributes: ["result": "cancelled"])
            return
        }
        var queryAttributes = [
            "pane_count": String(queryResult.count),
            "result": queryResult.result,
            "exit_code": String(queryResult.exitStatus),
        ]
        if let inputFailure = queryResult.inputFailure {
            queryAttributes["input_failure_stage"] = inputFailure.stage.rawValue
            queryAttributes["input_error_code"] = String(inputFailure.errorCode)
        }
        TracingService.shared.record(
            "pr.graphql.query",
            parent: cycleHandle,
            startTime: queryResult.startTime,
            endTime: queryResult.endTime,
            attributes: queryAttributes)
        activeBatchTask = nil
        if queryResult.failure == .missingExecutable, SettingsPersistence.isPRTrackingEnabled(),
            !Self.hasReportedMissingExecutable
        {
            Self.hasReportedMissingExecutable = true
            InvariantReporter.shared.violated(.githubCLIAvailable)
        }
        if let failure = queryResult.failure {
            for (paneID, record) in subscribers where Self.isQueryEligible(record) {
                setStatus(.failed(failure), for: paneID)
                TracingService.shared.record(
                    "pr.result.delivered",
                    attributes: [
                        "pane.id": paneID.uuidString, "pane.name": record.paneName,
                        "tab.id": record.tabID.uuidString, "tab.name": record.tabName,
                        "outcome": "failure", "failure": failure.rawValue,
                    ])
            }
            TracingService.shared.end(handle: cycleHandle, attributes: ["result": failure.rawValue])
            currentCycleHandle = nil
            return
        }
        guard !queryResult.outData.isEmpty, let text = String(data: queryResult.outData, encoding: .utf8) else {
            failSubscribers(with: .parse)
            TracingService.shared.end(handle: cycleHandle, attributes: ["result": "empty_response"])
            currentCycleHandle = nil
            return
        }
        let (headerSection, jsonText) = splitHeaderAndBody(from: text)
        let remainingPoints = parseRateLimitHeader(headerSection)
        if let points = remainingPoints {
            adjustInterval(remainingPoints: points)
        }
        guard let responseData = jsonText.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let dataDict = json["data"] as? [String: Any],
            (json["errors"] as? [Any])?.isEmpty != false
        else {
            failSubscribers(with: .parse)
            TracingService.shared.end(handle: cycleHandle, attributes: ["result": "parse_failed"])
            currentCycleHandle = nil
            return
        }
        let parsedCount = deliverPRResults(from: dataDict)
        var parsedAttrs: [String: String] = ["pr_count": String(parsedCount)]
        if let points = remainingPoints { parsedAttrs["rate_limit_remaining"] = String(points) }
        TracingService.shared.record("pr.response.parsed", parent: cycleHandle, attributes: parsedAttrs)
        TracingService.shared.end(handle: cycleHandle, attributes: ["result": "ok"])
        currentCycleHandle = nil
    }

    private func splitHeaderAndBody(from text: String) -> (header: String, body: String) {
        let separators = ["\r\n\r\n", "\n\n"]
        for separator in separators {
            let parts = text.components(separatedBy: separator)
            if parts.count >= 2 {
                return (parts[0], parts.dropFirst().joined(separator: separator))
            }
        }
        return ("", text)
    }

    private func parseRateLimitHeader(_ header: String) -> Int? {
        for line in header.components(separatedBy: .newlines)
        where line.lowercased().hasPrefix("x-ratelimit-remaining:") {
            return Int(
                line.dropFirst("x-ratelimit-remaining:".count)
                    .trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func setStatus(_ status: PRTrackingStatus, for paneID: UUID) {
        guard let record = subscribers[paneID] else { return }
        subscribers[paneID]?.status = status
        record.statusCallback(status)
    }

    private func failSubscribers(with failure: GitHubCLIFailure) {
        for paneID in subscribers.keys.filter({
            subscribers[$0].map(Self.isQueryEligible) ?? false
        }) {
            setStatus(.failed(failure), for: paneID)
        }
    }

    nonisolated private static func isQueryEligible(_ record: SubscriberRecord) -> Bool {
        guard let branch = record.branchName else { return false }
        return record.owner != nil && record.repo != nil && !branch.isEmpty && branch != "HEAD"
    }

    private func deliverPRResults(from dataDict: [String: Any]) -> Int {
        var parsedCount = 0
        for (paneID, record) in subscribers where Self.isQueryEligible(record) {
            let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
            guard let repoData = dataDict[alias] as? [String: Any],
                let pullRequests = repoData["pullRequests"] as? [String: Any],
                let nodes = pullRequests["nodes"] as? [[String: Any]]
            else {
                setStatus(.failed(.parse), for: paneID)
                continue
            }

            if let node = nodes.first {
                guard let pr = Self.parsePRFromGraphQLNode(node) else {
                    setStatus(.failed(.parse), for: paneID)
                    continue
                }
                parsedCount += 1
                subscribers[paneID]?.lastData = pr
                subscribers[paneID]?.callback(pr)
                setStatus(.current, for: paneID)
                if let record = subscribers[paneID] {
                    TracingService.shared.record(
                        "pr.result.delivered",
                        attributes: [
                            "pane.id": paneID.uuidString, "pane.name": record.paneName,
                            "tab.id": record.tabID.uuidString, "tab.name": record.tabName,
                            "outcome": "found",
                        ])
                }
            } else {
                subscribers[paneID]?.lastData = nil
                subscribers[paneID]?.callback(nil)
                setStatus(.noPullRequest, for: paneID)
                if let record = subscribers[paneID] {
                    TracingService.shared.record(
                        "pr.result.delivered",
                        attributes: [
                            "pane.id": paneID.uuidString, "pane.name": record.paneName,
                            "tab.id": record.tabID.uuidString, "tab.name": record.tabName,
                            "outcome": "not_found",
                        ])
                }
            }
        }
        return parsedCount
    }

    private static var hasReportedMissingExecutable = false

    func buildBatchQuery() -> String {
        var fragments: [String] = []
        for (paneID, record) in subscribers {
            guard let owner = record.owner,
                let repo = record.repo,
                let branch = record.branchName,
                !branch.isEmpty, branch != "HEAD"
            else { continue }
            let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
            fragments.append(
                """
                \(alias): repository(owner: "\(owner)", name: "\(repo)") {
                  pullRequests(headRefName: "\(branch)", first: 1, states: [OPEN, MERGED, CLOSED], orderBy: {field: CREATED_AT, direction: DESC}) {
                    nodes {
                      number title state url isDraft mergeable reviewDecision
                      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                      reviewThreads(first: 1) { totalCount }
                    }
                  }
                }
                """
            )
        }
        guard !fragments.isEmpty else { return "" }
        return "query BatchedPRStatus { \(fragments.joined(separator: " ")) }"
    }

    func adjustInterval(remainingPoints: Int) {
        let settings = SettingsPersistence.prPollingSettings()
        let base = max(15, TimeInterval(settings.intervalSeconds))
        if remainingPoints < 500 {
            effectiveInterval = min(600, effectiveInterval * 2)
        } else if remainingPoints > 2000, effectiveInterval > base {
            effectiveInterval = max(base, effectiveInterval / 1.5)
        }
    }

    struct BranchInfo {
        var paneID: UUID
        var owner: String
        var repo: String
        var branch: String
        var paneName: String = ""
        var tabID = UUID()
        var tabName: String = ""
    }

    static func checkBranchesForResolvedPRs(
        branches: [BranchInfo],
        parent: SpanHandle? = nil
    ) async -> [(paneID: UUID, pr: PullRequest)] {
        guard !branches.isEmpty else { return [] }

        let query = buildStaticBatchQuery(branches: branches)
        guard !query.isEmpty else { return [] }

        let jsonBody = ["query": query]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonBody) else { return [] }

        let jsonText: String? = await TracingService.shared.withSpan(
            "pr.graphql.query",
            parent: parent,
            attributes: ["context": "startup_check"]
        ) {
            let result = await GitHubCLIRunner.shared.run(
                arguments: ["api", "graphql", "--include", "--input", "-"],
                stdin: jsonData,
                timeout: Double(SettingsPersistence.prPollingSettings().timeoutSeconds))
            guard result.succeeded, let text = String(data: result.stdout, encoding: .utf8), !text.isEmpty else {
                return nil
            }
            return Self.splitStaticHeaderAndBody(text)
        }
        guard let jsonText else { return [] }
        return parseStaticBatchResponse(jsonText, branches: branches)
    }

    nonisolated private static func splitStaticHeaderAndBody(_ text: String) -> String {
        for separator in ["\r\n\r\n", "\n\n"] {
            let parts = text.components(separatedBy: separator)
            if parts.count >= 2 { return parts.dropFirst().joined(separator: separator) }
        }
        return text
    }

    static func buildStaticBatchQuery(branches: [BranchInfo]) -> String {
        var fragments: [String] = []
        for info in branches {
            guard !info.branch.isEmpty, info.branch != "HEAD" else { continue }
            let alias = "pane_" + info.paneID.uuidString.replacingOccurrences(of: "-", with: "")
            fragments.append(
                """
                \(alias): repository(owner: "\(info.owner)", name: "\(info.repo)") {
                  pullRequests(headRefName: "\(info.branch)", first: 1, states: [OPEN, MERGED, CLOSED], orderBy: {field: CREATED_AT, direction: DESC}) {
                    nodes {
                      number title state url isDraft mergeable reviewDecision
                      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                      reviewThreads(first: 1) { totalCount }
                    }
                  }
                }
                """
            )
        }
        guard !fragments.isEmpty else { return "" }
        return "query BatchedPRStatus { \(fragments.joined(separator: " ")) }"
    }

    nonisolated static func parseStaticBatchResponse(
        _ jsonText: String,
        branches: [BranchInfo]
    ) -> [(paneID: UUID, pr: PullRequest)] {
        guard let jsonData = jsonText.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let dataDict = json["data"] as? [String: Any]
        else { return [] }

        var results: [(paneID: UUID, pr: PullRequest)] = []
        for info in branches {
            let alias = "pane_" + info.paneID.uuidString.replacingOccurrences(of: "-", with: "")
            guard let repoData = dataDict[alias] as? [String: Any],
                let pullRequests = repoData["pullRequests"] as? [String: Any],
                let nodes = pullRequests["nodes"] as? [[String: Any]],
                let node = nodes.first,
                let pr = parsePRFromGraphQLNode(node)
            else { continue }
            results.append((paneID: info.paneID, pr: pr))
        }
        return results
    }

    static func fetchBranch(workingDirectory: String) async -> String? {
        await withCheckedContinuation { continuation in
            let task = Process()
            let outPipe = Pipe()
            task.executableURL = URL(filePath: "/usr/bin/git")
            task.arguments = ["-C", workingDirectory, "rev-parse", "--abbrev-ref", "HEAD"]
            task.standardOutput = outPipe
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { _ in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (branch?.isEmpty == false && branch != "HEAD") ? branch : nil)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    nonisolated static func parseRepoIdentity(from remoteURL: String) -> StatusLineData.Repo? {
        var cleaned = remoteURL
        if cleaned.hasSuffix(".git") { cleaned = String(cleaned.dropLast(4)) }

        if cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") {
            guard let url = URL(string: cleaned), let host = url.host else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2 else { return nil }
            return StatusLineData.Repo(host: host, owner: parts[parts.count - 2], name: parts[parts.count - 1])
        }

        if cleaned.contains("@"), cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let userHost = parts[0].split(separator: "@")
            let host = String(userHost.last ?? Substring(parts[0]))
            let pathParts = parts[1].split(separator: "/")
            guard pathParts.count >= 2 else { return nil }
            return StatusLineData.Repo(
                host: host,
                owner: String(pathParts[pathParts.count - 2]),
                name: String(pathParts[pathParts.count - 1])
            )
        }

        return nil
    }

    nonisolated static func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        guard let identity = parseRepoIdentity(from: remoteURL) else { return nil }
        return (identity.owner, identity.name)
    }

    nonisolated static func parsePRFromGraphQLNode(_ node: [String: Any]) -> PullRequest? {
        guard let number = node["number"] as? Int,
            let title = node["title"] as? String,
            let state = node["state"] as? String,
            let url = node["url"] as? String
        else { return nil }

        var pr = PullRequest(number: number, title: title, state: state.lowercased(), url: url)
        pr.isDraft = node["isDraft"] as? Bool
        pr.mergeable = node["mergeable"] as? String
        pr.reviewDecision = node["reviewDecision"] as? String

        if let commits = node["commits"] as? [String: Any],
            let commitNodes = commits["nodes"] as? [[String: Any]],
            let firstCommit = commitNodes.first,
            let commit = firstCommit["commit"] as? [String: Any],
            let rollup = commit["statusCheckRollup"] as? [String: Any],
            let rollupState = rollup["state"] as? String
        {
            pr.commitStatusState = rollupState
        }

        if let reviewThreads = node["reviewThreads"] as? [String: Any],
            let totalCount = reviewThreads["totalCount"] as? Int
        {
            pr.unresolvedCommentCount = totalCount
        }

        return pr
    }
}
