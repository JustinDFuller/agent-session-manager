import AgentSessionManagerMCPBridgeCore
import Foundation
import MCP
import XCTest

@testable import AgentSessionManager

final class AgentControlLifecycleTests: XCTestCase {
    func testTokenStoreEnforcesConcurrencyAndRevocation() throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(),
            paneName: "Pane",
            tabID: UUID(),
            tabName: "Tab",
            scope: .pane
        )
        let limits = AgentControlLimits(
            maxRequestBodyBytes: 1_024,
            maxResponseBodyBytes: 1_024,
            maxConcurrentRequestsPerCredential: 1,
            requestTimeout: .seconds(1),
            maxRegisteredCredentials: 1,
            maxSessionsPerCredential: 1
        )
        let credential = try store.register(source: source, limits: limits)

        XCTAssertEqual(
            store.source(for: credential.bearerToken, sessionID: nil, limits: limits),
            .success(source)
        )
        XCTAssertEqual(
            store.source(for: credential.bearerToken, sessionID: nil, limits: limits),
            .failure(.tooManyRequests)
        )

        store.finishRequest(token: credential.bearerToken)
        XCTAssertEqual(
            store.source(for: credential.bearerToken, sessionID: nil, limits: limits),
            .success(source)
        )

        store.revoke(paneID: source.paneID)
        XCTAssertEqual(
            store.source(for: credential.bearerToken, sessionID: nil, limits: limits),
            .failure(.invalidToken)
        )
    }

    func testTokenStoreLimitsSessionsPerCredentialAndUpdatesScope() throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(), paneName: "Pane", tabID: UUID(), tabName: "Tab", scope: .global)
        var limits = AgentControlLimits.default
        limits = AgentControlLimits(
            maxRequestBodyBytes: limits.maxRequestBodyBytes,
            maxResponseBodyBytes: limits.maxResponseBodyBytes,
            maxConcurrentRequestsPerCredential: limits.maxConcurrentRequestsPerCredential,
            requestTimeout: limits.requestTimeout,
            maxRegisteredCredentials: limits.maxRegisteredCredentials,
            maxSessionsPerCredential: 1)
        let credential = try store.register(source: source, limits: limits)

        XCTAssertTrue(store.bind(sessionID: "first", token: credential.bearerToken, limits: limits))
        XCTAssertFalse(store.bind(sessionID: "second", token: credential.bearerToken, limits: limits))

        store.updateScope(.pane)
        XCTAssertEqual(
            store.source(for: credential.bearerToken, sessionID: "first", limits: limits),
            .success(
                AgentControlSource(
                    paneID: source.paneID,
                    paneName: source.paneName,
                    tabID: source.tabID,
                    tabName: source.tabName,
                    scope: .pane)))
    }

    func testValidatorRejectsUntrustedHostAndOrigin() throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(), paneName: "Pane", tabID: UUID(), tabName: "Tab", scope: .pane)
        let limits = AgentControlLimits.default
        let credential = try store.register(source: source, limits: limits)
        let validator = AgentControlRequestValidator(
            tokenStore: store,
            expectedHost: "127.0.0.1:1234",
            expectedOrigin: "http://127.0.0.1:1234",
            limits: limits
        )

        let hostRequest = HTTPRequest(
            method: "POST",
            headers: [
                HTTPHeaderName.host: "localhost:1234",
                HTTPHeaderName.authorization: "Bearer \(credential.bearerToken)",
            ],
            body: Data("{}".utf8),
            path: "/mcp"
        )
        XCTAssertEqual(
            validator.validate(
                hostRequest, context: .init(httpMethod: "POST", sessionID: nil, isInitializationRequest: true))?
                .statusCode,
            403
        )
        store.finishRequest(token: credential.bearerToken)

        let originRequest = HTTPRequest(
            method: "POST",
            headers: [
                HTTPHeaderName.host: "127.0.0.1:1234",
                HTTPHeaderName.origin: "http://localhost:1234",
                HTTPHeaderName.authorization: "Bearer \(credential.bearerToken)",
            ],
            body: Data("{}".utf8),
            path: "/mcp"
        )
        XCTAssertEqual(
            validator.validate(
                originRequest, context: .init(httpMethod: "POST", sessionID: nil, isInitializationRequest: true))?
                .statusCode,
            403
        )
    }

    func testValidatorUsesConfiguredRequestBodyLimit() throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(), paneName: "Pane", tabID: UUID(), tabName: "Tab", scope: .pane)
        let limits = AgentControlLimits(
            maxRequestBodyBytes: 1,
            maxResponseBodyBytes: 1_024,
            maxConcurrentRequestsPerCredential: 1,
            requestTimeout: .seconds(1),
            maxRegisteredCredentials: 1,
            maxSessionsPerCredential: 1)
        let credential = try store.register(source: source, limits: limits)
        let validator = AgentControlRequestValidator(
            tokenStore: store,
            expectedHost: "127.0.0.1:1234",
            expectedOrigin: "http://127.0.0.1:1234",
            limits: limits)

        let response = validator.validate(
            HTTPRequest(
                method: "POST",
                headers: [
                    HTTPHeaderName.host: "127.0.0.1:1234",
                    HTTPHeaderName.authorization: "Bearer \(credential.bearerToken)",
                ],
                body: Data("{}".utf8),
                path: "/mcp"),
            context: .init(httpMethod: "POST", sessionID: nil, isInitializationRequest: true))
        XCTAssertEqual(response?.statusCode, 413)
    }

    func testHTTPApplicationBindsLoopbackEndpointAndRejectsUnauthorizedRequest() async throws {
        let store = AgentControlTokenStore()
        let application = AgentControlHTTPApplication(tokenStore: store, limits: .default)
        let port = try await application.start()
        defer { Task { await application.stop() } }

        let response = await application.handle(
            request: HTTPRequest(
                method: "POST",
                headers: [
                    HTTPHeaderName.host: "127.0.0.1:\(port)",
                    HTTPHeaderName.contentType: "application/json",
                ],
                body: Data("{\"method\":\"initialize\"}".utf8),
                path: "/mcp"
            ))

        XCTAssertEqual(response.statusCode, 401)
    }

    func testAuthenticatedMCPClientCompletesSequentialResponses() async throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(),
            paneName: "Pane",
            tabID: UUID(),
            tabName: "Tab",
            scope: .global
        )
        let application = AgentControlHTTPApplication(tokenStore: store, limits: .default)
        let port = try await application.start()
        let credential = try store.register(source: source, limits: .default)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(credential.bearerToken)"
        ]
        let transport = HTTPClientTransport(
            endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!,
            configuration: configuration
        )
        let client = Client(name: "AgentControlLifecycleTests", version: "1.0")
        defer {
            Task {
                await client.disconnect()
                await application.stop()
            }
        }

        try await client.connect(transport: transport)
        let resources = try await client.listResources()
        let tools = try await client.listTools()

        XCTAssertEqual(resources.resources.count, 0)
        XCTAssertEqual(tools.tools.count, 0)
    }

    func testAuthenticatedMCPSessionIsDisconnectedWhenCredentialIsRevoked() async throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(),
            paneName: "Pane",
            tabID: UUID(),
            tabName: "Tab",
            scope: .pane
        )
        let application = AgentControlHTTPApplication(tokenStore: store, limits: .default)
        let port = try await application.start()
        let credential = try store.register(source: source, limits: .default)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(credential.bearerToken)"
        ]
        let transport = HTTPClientTransport(
            endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!,
            configuration: configuration
        )
        let client = Client(name: "AgentControlLifecycleTests", version: "1.0")
        defer {
            Task {
                await client.disconnect()
                await application.stop()
            }
        }

        try await client.connect(transport: transport)
        _ = try await client.listResources()

        store.revoke(paneID: source.paneID)
        await application.disconnectSessions(forPaneID: source.paneID)

        do {
            _ = try await client.listResources()
            XCTFail("A revoked credential must not retain an active MCP session")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testStdioBridgeBindsAndReleasesAuthenticatedAgentControlSessions() async throws {
        let store = AgentControlTokenStore()
        let source = AgentControlSource(
            paneID: UUID(),
            paneName: "Cursor Pane",
            tabID: UUID(),
            tabName: "Cursor Tab",
            scope: .pane
        )
        let application = AgentControlHTTPApplication(tokenStore: store, limits: .default)
        let port = try await application.start()
        let credential = try store.register(source: source, limits: .default)
        defer { Task { await application.stop() } }

        for iteration in 0..<10 {
            let remoteTransport = AuthenticatedHTTPClientTransport(
                endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!,
                bearerToken: credential.bearerToken
            )
            let pair = await InMemoryTransport.createConnectedPair()
            try await pair.server.connect()
            let bridgeTask = Task {
                try await MCPTransportBridge(
                    localTransport: pair.server,
                    remoteTransport: remoteTransport
                ).run()
            }
            let client = Client(name: "CursorBridgeTests-\(iteration)", version: "1.0")

            try await client.connect(transport: pair.client)
            _ = try await client.listResources()
            await client.disconnect()

            do {
                try await bridgeTask.value
                XCTFail(
                    "iteration \(iteration): the bridge should observe the client's disconnect as a closed connection"
                )
            } catch let error as MCPError {
                guard case .connectionClosed = error else {
                    XCTFail("iteration \(iteration): expected MCPError.connectionClosed, got \(error)")
                    continue
                }
            }

            XCTAssertEqual(
                store.boundSessionCount(forPaneID: source.paneID), 0,
                "iteration \(iteration): the MCP session must be released when the bridge tears down")
        }
    }

    func testAuthorizationFailureTelemetryIsBoundedAndRedacted() async throws {
        let store = AgentControlTokenStore()
        let application = AgentControlHTTPApplication(tokenStore: store, limits: .default)
        let port = try await application.start()
        defer {
            Task { await application.stop() }
        }
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let response = await application.handle(
            request: HTTPRequest(
                method: "POST",
                headers: [
                    HTTPHeaderName.host: "127.0.0.1:\(port)",
                    HTTPHeaderName.authorization: "Bearer secret-token",
                ],
                body: Data("{\"method\":\"initialize\",\"secret\":\"payload\"}".utf8),
                path: "/mcp"
            )
        )

        XCTAssertEqual(response.statusCode, 401)
        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.last {
                $0.name == "agent_control.request.authorization_failed"
            }
        )
        XCTAssertEqual(event.attributes["status"], "401")
        XCTAssertEqual(event.attributes["result"], "rejected")
        XCTAssertNil(event.attributes["token"])
        XCTAssertNil(event.attributes["body"])
        XCTAssertFalse(event.attributes.values.contains("secret-token"))
        XCTAssertFalse(event.attributes.values.contains("payload"))
    }
}
