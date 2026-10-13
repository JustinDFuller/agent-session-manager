import XCTest

@testable import AgentSessionManager

@MainActor
final class PRTrackingCoordinatorTests: XCTestCase {
    func testParseOwnerRepoHTTPS() {
        let result = PRTrackingCoordinator.parseOwnerRepo(
            from: "https://github.com/JustinDFuller/agent-session-manager.git")
        XCTAssertEqual(result?.owner, "JustinDFuller")
        XCTAssertEqual(result?.repo, "agent-session-manager")
    }

    func testParseOwnerRepoHTTPSNoGitSuffix() {
        let result = PRTrackingCoordinator.parseOwnerRepo(from: "https://github.com/owner/repo")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
    }

    func testParseOwnerRepoSSH() {
        let result = PRTrackingCoordinator.parseOwnerRepo(from: "git@github.com:owner/repo.git")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
    }

    func testParseOwnerRepoSSHNoGitSuffix() {
        let result = PRTrackingCoordinator.parseOwnerRepo(from: "git@github.com:owner/repo")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
    }

    func testParseOwnerRepoUnrecognizedFormat() {
        XCTAssertNil(PRTrackingCoordinator.parseOwnerRepo(from: "not-a-url"))
    }

    func testParsePRBasicFields() {
        let node: [String: Any] = [
            "number": 42,
            "title": "My PR",
            "state": "OPEN",
            "url": "https://github.com/owner/repo/pull/42",
            "isDraft": false,
            "mergeable": "MERGEABLE",
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertNotNil(pr)
        XCTAssertEqual(pr?.number, 42)
        XCTAssertEqual(pr?.title, "My PR")
        XCTAssertEqual(pr?.state, "open")
        XCTAssertEqual(pr?.url, "https://github.com/owner/repo/pull/42")
        XCTAssertEqual(pr?.isDraft, false)
        XCTAssertEqual(pr?.mergeable, "MERGEABLE")
    }

    func testParsePRStateIsLowercased() {
        let node: [String: Any] = ["number": 1, "title": "T", "state": "MERGED", "url": "u"]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.state, "merged")
    }

    func testParsePRStatusCheckRollupState() {
        let node: [String: Any] = [
            "number": 1,
            "title": "T",
            "state": "OPEN",
            "url": "u",
            "commits": [
                "nodes": [
                    [
                        "commit": [
                            "statusCheckRollup": ["state": "SUCCESS"]
                        ]
                    ]
                ]
            ],
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.commitStatusState, "SUCCESS")
        XCTAssertEqual(pr?.buildStatus, .success)
    }

    func testParsePRReviewThreadCount() {
        let node: [String: Any] = [
            "number": 1,
            "title": "T",
            "state": "OPEN",
            "url": "u",
            "reviewThreads": ["totalCount": 3],
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.unresolvedCommentCount, 3)
    }

    func testParsePRMissingRequiredFields() {
        let node: [String: Any] = ["number": 1, "title": "T"]
        XCTAssertNil(PRTrackingCoordinator.parsePRFromGraphQLNode(node))
    }

    func testParsePRConflictingMergeable() {
        let node: [String: Any] = [
            "number": 1, "title": "T", "state": "OPEN", "url": "u",
            "mergeable": "CONFLICTING",
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertTrue(pr?.hasMergeConflicts ?? false)
    }

    func testBatchQueryBuildingSingleSubscriber() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
        coordinator.subscribers[paneID] = makeRecord(owner: "owner1", repo: "repo1", branch: "feature-1")
        let query = coordinator.buildBatchQuery()
        XCTAssertTrue(query.contains(alias), "Query should contain alias for pane")
        XCTAssertTrue(query.contains("owner1"), "Query should contain owner")
        XCTAssertTrue(query.contains("repo1"), "Query should contain repo")
        XCTAssertTrue(query.contains("feature-1"), "Query should contain branch")
        XCTAssertTrue(query.contains("statusCheckRollup"), "Query should request CI status")
        XCTAssertTrue(query.contains("reviewThreads"), "Query should request review threads")
        XCTAssertTrue(query.contains("orderBy"), "Query should order results")
        XCTAssertTrue(query.contains("CREATED_AT"), "Query should order by creation date")
        XCTAssertTrue(query.contains("DESC"), "Query should order newest first")
    }

    func testBatchQueryBuildingMultipleSubscribers() {
        let coordinator = PRTrackingCoordinator()
        let pane1 = UUID()
        let pane2 = UUID()
        coordinator.subscribers[pane1] = makeRecord(owner: "owner1", repo: "repo1", branch: "branch-a")
        coordinator.subscribers[pane2] = makeRecord(owner: "owner2", repo: "repo2", branch: "branch-b")
        let query = coordinator.buildBatchQuery()
        let alias1 = "pane_" + pane1.uuidString.replacingOccurrences(of: "-", with: "")
        let alias2 = "pane_" + pane2.uuidString.replacingOccurrences(of: "-", with: "")
        XCTAssertTrue(query.contains(alias1))
        XCTAssertTrue(query.contains(alias2))
        XCTAssertTrue(query.contains("owner1"))
        XCTAssertTrue(query.contains("owner2"))
    }

    func testBatchQuerySkipsUnresolvedSubscribers() {
        let coordinator = PRTrackingCoordinator()
        let resolved = UUID()
        let unresolved = UUID()
        coordinator.subscribers[resolved] = makeRecord(owner: "owner", repo: "repo", branch: "main")
        coordinator.subscribers[unresolved] = makeRecord(owner: nil, repo: nil, branch: nil)
        let query = coordinator.buildBatchQuery()
        let resolvedAlias = "pane_" + resolved.uuidString.replacingOccurrences(of: "-", with: "")
        let unresolvedAlias = "pane_" + unresolved.uuidString.replacingOccurrences(of: "-", with: "")
        XCTAssertTrue(query.contains(resolvedAlias))
        XCTAssertFalse(query.contains(unresolvedAlias))
    }

    func testBatchQuerySkipsHEADBranch() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "owner", repo: "repo", branch: "HEAD")
        let query = coordinator.buildBatchQuery()
        XCTAssertTrue(query.isEmpty, "Detached HEAD should be excluded from batch query")
    }

    func testBatchQueryEmptyWhenNoResolvedSubscribers() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: nil, repo: nil, branch: nil)
        let query = coordinator.buildBatchQuery()
        XCTAssertTrue(query.isEmpty)
    }

    func testAdjustIntervalBackoffOnLowRemaining() {
        let coordinator = PRTrackingCoordinator()
        coordinator.effectiveInterval = 30
        coordinator.adjustInterval(remainingPoints: 400)
        XCTAssertEqual(coordinator.effectiveInterval, 60, accuracy: 1)
    }

    func testAdjustIntervalDoublingCapsAt600() {
        let coordinator = PRTrackingCoordinator()
        coordinator.effectiveInterval = 400
        coordinator.adjustInterval(remainingPoints: 400)
        XCTAssertEqual(coordinator.effectiveInterval, 600, accuracy: 1)
    }

    func testAdjustIntervalRestoresOnHighRemaining() {
        let coordinator = PRTrackingCoordinator()
        coordinator.effectiveInterval = 120
        coordinator.adjustInterval(remainingPoints: 3000)
        XCTAssertLessThan(coordinator.effectiveInterval, 120)
    }

    func testAdjustIntervalNoChangeWhenHealthy() {
        let coordinator = PRTrackingCoordinator()
        coordinator.effectiveInterval = 30
        coordinator.adjustInterval(remainingPoints: 3000)
        XCTAssertEqual(coordinator.effectiveInterval, 30, accuracy: 1)
    }

    func testSubscribeDeliversCachedDataImmediately() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let cachedPR = PullRequest(number: 5, title: "Cached", state: "open", url: "u")
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "o",
            repo: "r",
            branchName: "main",
            lastData: cachedPR,
            callback: { _ in },
            isActive: true
        )

        var receivedPR: PullRequest?
        coordinator.subscribe(paneID: paneID, workingDirectory: "/tmp", isActive: true) { pr in
            receivedPR = pr
        }

        XCTAssertEqual(receivedPR?.number, 5)
    }

    func testAuthenticationFailureRetainsPRAsStaleWithoutDeliveringResolution() throws {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let existing = PullRequest(number: 42, title: "Open", state: "open", url: "url")
        var deliveredPRs: [PullRequest?] = []
        var deliveredStatuses: [StatusLineData.PRTrackingState?] = []
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            lastData: existing,
            status: .current,
            callback: { deliveredPRs.append($0) },
            statusCallback: { deliveredStatuses.append($0) },
            isActive: true
        )

        coordinator.handleBatchResponse(makeQueryResult(paneIDs: [paneID], failure: .authentication), token: 0)

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 42)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .failed(.authentication))
        XCTAssertTrue(deliveredPRs.isEmpty)
        XCTAssertEqual(deliveredStatuses.last, .failed(.authentication))
    }

    func testConfirmedNoPRClearsCachedPRAndSuccessfulRetryRecovers() throws {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        var deliveredPRs: [PullRequest?] = []
        var deliveredStatuses: [StatusLineData.PRTrackingState?] = []
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            lastData: PullRequest(number: 42, title: "Old", state: "open", url: "url"),
            status: .failed(.authentication),
            callback: { deliveredPRs.append($0) },
            statusCallback: { deliveredStatuses.append($0) },
            isActive: true
        )

        coordinator.handleBatchResponse(
            makeQueryResult(paneIDs: [paneID], outData: try batchResponse(paneID: paneID, nodes: [])), token: 0)

        XCTAssertNil(coordinator.subscribers[paneID]?.lastData)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .absent)
        XCTAssertEqual(deliveredPRs.count, 1)
        XCTAssertNil(deliveredPRs[0])

        let found = [
            [
                "number": 43,
                "title": "Recovered",
                "state": "OPEN",
                "url": "https://github.com/owner/repo/pull/43",
            ]
        ]
        coordinator.handleBatchResponse(
            makeQueryResult(paneIDs: [paneID], outData: try batchResponse(paneID: paneID, nodes: found)), token: 0)

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 43)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .current)
        XCTAssertEqual(deliveredStatuses, [.absent, .current])
    }

    func testMissingPRResponseAliasIsFailureAndRetainsCachedPR() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let existing = PullRequest(number: 42, title: "Open", state: "open", url: "url")
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            lastData: existing,
            status: .current,
            callback: { _ in },
            isActive: true
        )
        let outData = Data(#"{"data":{}}"#.utf8)

        coordinator.handleBatchResponse(makeQueryResult(paneIDs: [paneID], outData: outData), token: 0)

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 42)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .failed(.parse))
    }

    func testUnsubscribeRemovesRecord() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "o", repo: "r", branch: "main")
        coordinator.unsubscribe(paneID: paneID)
        XCTAssertNil(coordinator.subscribers[paneID])
    }

    func testSetActiveUpdatesRecord() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "o", repo: "r", branch: "main")
        coordinator.setActive(paneID: paneID, isActive: false)
        XCTAssertEqual(coordinator.subscribers[paneID]?.isActive, false)
    }

    func testPausePreservesSubscribers() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "o", repo: "r", branch: "main")
        coordinator.pause()
        XCTAssertNotNil(coordinator.subscribers[paneID])
    }

    func testResumeWhileNotPausedReschedulesTimer() {
        let coordinator = PRTrackingCoordinator()
        XCTAssertFalse(coordinator.isPaused)
        coordinator.resume()
        XCTAssertFalse(coordinator.isPaused)
    }

    func testPauseWithBackgroundRefreshEnabledKeepsTimerRunning() {
        let tmpDir = makeTempSettingsDir(backgroundRefreshEnabled: true, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(tmpDir) }

        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "o", repo: "r", branch: "main")
        coordinator.pause()
        XCTAssertFalse(coordinator.isPaused)
        XCTAssertNotNil(coordinator.cycleTimer)
    }

    func testPauseWithBackgroundRefreshDisabledStopsTimer() {
        let tmpDir = makeTempSettingsDir(backgroundRefreshEnabled: false, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(tmpDir) }

        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "o", repo: "r", branch: "main")
        coordinator.pause()
        XCTAssertTrue(coordinator.isPaused)
        XCTAssertNil(coordinator.cycleTimer)
    }

    func testResumeFromBackgroundRefreshDisabledWithNoSubscribersLeavesTimerNil() {
        let tmpDir = makeTempSettingsDir(backgroundRefreshEnabled: false, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(tmpDir) }

        let coordinator = PRTrackingCoordinator()
        coordinator.pause()
        XCTAssertTrue(coordinator.isPaused)
        coordinator.resume()
        XCTAssertFalse(coordinator.isPaused)
        XCTAssertNil(coordinator.cycleTimer)
    }

    func testBackgroundedFlagSetOnPause() {
        let coordinator = PRTrackingCoordinator()
        XCTAssertFalse(coordinator.isBackgrounded)
        coordinator.pause()
        XCTAssertTrue(coordinator.isBackgrounded)
    }

    func testBackgroundedFlagClearedOnResume() {
        let coordinator = PRTrackingCoordinator()
        coordinator.pause()
        XCTAssertTrue(coordinator.isBackgrounded)
        coordinator.resume()
        XCTAssertFalse(coordinator.isBackgrounded)
    }

    func testResumeFromBackgroundRefreshRestoresForegroundInterval() {
        let tmpDir = makeTempSettingsDir(backgroundRefreshEnabled: true, backgroundIntervalSeconds: 90)
        defer { cleanupTempSettingsDir(tmpDir) }

        let coordinator = PRTrackingCoordinator()
        coordinator.pause()
        XCTAssertTrue(coordinator.isBackgrounded)
        coordinator.resume()
        XCTAssertFalse(coordinator.isBackgrounded)
    }

    func testParseRepoIdentityHTTPS() {
        let result = PRTrackingCoordinator.parseRepoIdentity(from: "https://github.com/owner/repo.git")
        XCTAssertEqual(result?.host, "github.com")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.name, "repo")
    }

    func testParseRepoIdentityHTTPSNoGitSuffix() {
        let result = PRTrackingCoordinator.parseRepoIdentity(from: "https://github.com/owner/repo")
        XCTAssertEqual(result?.host, "github.com")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.name, "repo")
    }

    func testParseRepoIdentitySSH() {
        let result = PRTrackingCoordinator.parseRepoIdentity(from: "git@github.com:owner/repo.git")
        XCTAssertEqual(result?.host, "github.com")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.name, "repo")
    }

    func testParseRepoIdentitySSHNoGitSuffix() {
        let result = PRTrackingCoordinator.parseRepoIdentity(from: "git@github.com:owner/repo")
        XCTAssertEqual(result?.host, "github.com")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.name, "repo")
    }

    func testParseRepoIdentityGitHubEnterprise() {
        let result = PRTrackingCoordinator.parseRepoIdentity(
            from: "https://github.example.com/org/myrepo.git")
        XCTAssertEqual(result?.host, "github.example.com")
        XCTAssertEqual(result?.owner, "org")
        XCTAssertEqual(result?.name, "myrepo")
    }

    func testParseRepoIdentityInvalidReturnsNil() {
        XCTAssertNil(PRTrackingCoordinator.parseRepoIdentity(from: "not-a-url"))
    }

    func testParseOwnerRepoStillWorksThroughIdentity() {
        let result = PRTrackingCoordinator.parseOwnerRepo(from: "git@github.com:owner/repo.git")
        XCTAssertEqual(result?.owner, "owner")
        XCTAssertEqual(result?.repo, "repo")
    }

    func testFailedQueryRetainsPRAndDoesNotDeliverResolutionTransition() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let existing = PullRequest(number: 17, title: "Current", state: "open", url: "u")
        var dataUpdates = 0
        var deliveredStatus: StatusLineData.PRTrackingState?
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            lastData: existing,
            status: .current,
            callback: { _ in dataUpdates += 1 },
            statusCallback: { deliveredStatus = $0 },
            isActive: true)

        coordinator.applyQueryFailure(.authentication, paneIDs: [paneID])

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 17)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .failed(.authentication))
        XCTAssertEqual(deliveredStatus, .failed(.authentication))
        XCTAssertEqual(dataUpdates, 0)
    }

    func testPartialGraphQLResultRetainsPRAndReportsParseFailure() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let existing = PullRequest(number: 17, title: "Current", state: "open", url: "u")
        var dataUpdates = 0
        var latestStatus: StatusLineData.PRTrackingState?
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            lastData: existing,
            status: .current,
            callback: { _ in dataUpdates += 1 },
            statusCallback: { latestStatus = $0 },
            isActive: true)

        XCTAssertEqual(coordinator.deliverPRResults(from: [:], paneIDs: [paneID]), 0)
        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 17)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .failed(.parse))
        XCTAssertEqual(latestStatus, .failed(.parse))
        XCTAssertEqual(dataUpdates, 0)
    }

    func testQueryFailureOnlyUpdatesPaneIDs() {
        let coordinator = PRTrackingCoordinator()
        let queriedPaneID = UUID()
        let excludedPaneID = UUID()
        var excludedStatus: StatusLineData.PRTrackingState?
        coordinator.subscribers[queriedPaneID] = makeRecord(owner: "owner", repo: "repo", branch: "main")
        coordinator.subscribers[excludedPaneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: nil,
            callback: { _ in XCTFail("An excluded pane must not receive PR data") },
            statusCallback: { excludedStatus = $0 },
            isActive: true)

        coordinator.applyQueryFailure(.authentication, paneIDs: [queriedPaneID])

        XCTAssertEqual(coordinator.subscribers[queriedPaneID]?.status, .failed(.authentication))
        XCTAssertNil(coordinator.subscribers[excludedPaneID]?.status)
        XCTAssertNil(excludedStatus)
    }

    func testPRResultsOnlyUpdatePaneIDs() {
        let coordinator = PRTrackingCoordinator()
        let queriedPaneID = UUID()
        let excludedPaneID = UUID()
        var excludedStatus: StatusLineData.PRTrackingState?
        coordinator.subscribers[queriedPaneID] = makeRecord(owner: "owner", repo: "repo", branch: "main")
        coordinator.subscribers[excludedPaneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: nil,
            callback: { _ in XCTFail("An excluded pane must not receive PR data") },
            statusCallback: { excludedStatus = $0 },
            isActive: true)
        let alias = "pane_" + queriedPaneID.uuidString.replacingOccurrences(of: "-", with: "")

        XCTAssertEqual(
            coordinator.deliverPRResults(
                from: [alias: ["pullRequests": ["nodes": []]]], paneIDs: [queriedPaneID]),
            0)

        XCTAssertEqual(coordinator.subscribers[queriedPaneID]?.status, .absent)
        XCTAssertNil(coordinator.subscribers[excludedPaneID]?.status)
        XCTAssertNil(excludedStatus)
    }

    func testRepositoryIdentityStartsImmediateCycle() async throws {
        let settingsDirectory = makeTempSettingsDir(
            backgroundRefreshEnabled: true, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(settingsDirectory) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: settingsDirectory)
        try Data("true".utf8).write(to: support.appending(path: "pr-tracking-settings.json"))
        let repository = try createGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let paneID = UUID()
        let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
        let response = Data("{\"data\":{\"\(alias)\":{\"pullRequests\":{\"nodes\":[]}}}}".utf8)
        let requestExpectation = expectation(description: "GitHub query starts")
        let absentExpectation = expectation(description: "Initial PR result is delivered")
        var latestStatus: StatusLineData.PRTrackingState?
        let runner = PRTrackingTestRunner(response: response, onRun: { requestExpectation.fulfill() })
        let coordinator = PRTrackingCoordinator(cliRunner: runner)
        let record = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: repository.path,
            callback: { _ in },
            statusCallback: { status in
                latestStatus = status
                if status == .absent { absentExpectation.fulfill() }
            },
            isActive: true)
        coordinator.subscribers[paneID] = record

        coordinator.setRepositoryIdentity(
            paneID: paneID,
            identityToken: record.identityToken,
            workingDirectory: repository.path,
            owner: "owner",
            repo: "repo")
        await fulfillment(of: [requestExpectation, absentExpectation], timeout: 5)

        XCTAssertEqual(latestStatus, .absent)
        let query = try XCTUnwrap(runner.lastInput)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: query) as? [String: String])
        XCTAssertTrue(try XCTUnwrap(body["query"]).contains(alias))
        coordinator.unsubscribe(paneID: paneID)
    }

    func testPollingCycleClosesTelemetrySpanWhenEnabled() async throws {
        let settingsDirectory = makeTempSettingsDir(
            backgroundRefreshEnabled: true, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(settingsDirectory) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: settingsDirectory)
        try Data("true".utf8).write(to: support.appending(path: "pr-tracking-settings.json"))
        let appSettings = AppSettings()
        appSettings.debugModeEnabled = true
        TracingService.shared.configure(from: appSettings)
        defer {
            appSettings.debugModeEnabled = false
            TracingService.shared.configure(from: appSettings)
            TracingService.shared.resetForTesting()
        }
        let repository = try createGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let paneID = UUID()
        let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
        let response = Data("{\"data\":{\"\(alias)\":{\"pullRequests\":{\"nodes\":[]}}}}".utf8)
        let absentExpectation = expectation(description: "Initial PR result is delivered")
        let runner = PRTrackingTestRunner(response: response, onRun: {})
        let coordinator = PRTrackingCoordinator(cliRunner: runner)
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: repository.path,
            owner: "owner",
            repo: "repo",
            paneName: "telemetry-test",
            callback: { _ in },
            statusCallback: { status in
                if status == .absent { absentExpectation.fulfill() }
            },
            isActive: true)

        coordinator.runCycle()
        await fulfillment(of: [absentExpectation], timeout: 5)

        let globalTrace = appSettings.resolvedTracingDirectoryURL
            .appending(path: "_global/global.jsonl")
        var traceLines: [String] = []
        for _ in 0..<20 {
            if let contents = try? String(contentsOf: globalTrace, encoding: .utf8) {
                traceLines = contents.split(whereSeparator: \.isNewline).map(String.init)
                if traceLines.contains(where: { $0.contains("pr.poll.cycle") && $0.contains("\"ok\"") }) {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let cycleSpan = try XCTUnwrap(
            traceLines.compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }.first { $0["name"] as? String == "pr.poll.cycle" })
        let attributes = try XCTUnwrap(cycleSpan["attributes"] as? [String: String])
        XCTAssertEqual(attributes["result"], "ok")
        coordinator.unsubscribe(paneID: paneID)
    }

    func testTrackingDisabledDuringBranchLookupEndsCycleWithoutQuery() async throws {
        let settingsDirectory = makeTempSettingsDir(
            backgroundRefreshEnabled: true, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(settingsDirectory) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: settingsDirectory)
        let trackingSettings = support.appending(path: "pr-tracking-settings.json")
        try Data("true".utf8).write(to: trackingSettings)
        let appSettings = AppSettings()
        appSettings.debugModeEnabled = true
        TracingService.shared.configure(from: appSettings)
        defer {
            appSettings.debugModeEnabled = false
            TracingService.shared.configure(from: appSettings)
            TracingService.shared.resetForTesting()
        }
        let branchLookupStarted = expectation(description: "Branch lookup is suspended")
        let branchGate = AsyncStream<String?>.makeStream()
        let runner = PRTrackingTestRunner(response: Data(), onRun: {})
        let coordinator = PRTrackingCoordinator(
            cliRunner: runner,
            branchFetcher: { _ in
                branchLookupStarted.fulfill()
                var iterator = branchGate.stream.makeAsyncIterator()
                guard let branch = await iterator.next() else { return nil }
                return branch
            })
        let paneID = UUID()
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp/repository",
            owner: "owner",
            repo: "repo",
            callback: { _ in },
            isActive: true)

        coordinator.runCycle()
        await fulfillment(of: [branchLookupStarted], timeout: 5)
        try Data("false".utf8).write(to: trackingSettings)
        branchGate.continuation.yield("feature")
        branchGate.continuation.finish()

        let globalTrace = appSettings.resolvedTracingDirectoryURL
            .appending(path: "_global/global.jsonl")
        var traceLines: [String] = []
        for _ in 0..<20 {
            if let contents = try? String(contentsOf: globalTrace, encoding: .utf8) {
                traceLines = contents.split(whereSeparator: \.isNewline).map(String.init)
                if traceLines.contains(where: {
                    $0.contains("pr.poll.cycle") && $0.contains("tracking_disabled")
                }) {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let cycleSpan = try XCTUnwrap(
            traceLines.compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }.first { $0["name"] as? String == "pr.poll.cycle" })
        let attributes = try XCTUnwrap(cycleSpan["attributes"] as? [String: String])
        XCTAssertEqual(attributes["result"], "tracking_disabled")
        XCTAssertNil(runner.lastInput)
        XCTAssertNil(coordinator.subscribers[paneID]?.status)
        coordinator.unsubscribe(paneID: paneID)
    }

    func testMixedQueryableAndUnqueryableBranchesOnlyUpdateQueryParticipants() async throws {
        let settingsDirectory = makeTempSettingsDir(
            backgroundRefreshEnabled: true, backgroundIntervalSeconds: 60)
        defer { cleanupTempSettingsDir(settingsDirectory) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: settingsDirectory)
        try Data("true".utf8).write(to: support.appending(path: "pr-tracking-settings.json"))
        let repository = try createGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let queriedPaneID = UUID()
        let excludedPaneID = UUID()
        let queryAlias = "pane_" + queriedPaneID.uuidString.replacingOccurrences(of: "-", with: "")
        let excludedAlias = "pane_" + excludedPaneID.uuidString.replacingOccurrences(of: "-", with: "")
        let response = Data("{\"data\":{\"\(queryAlias)\":{\"pullRequests\":{\"nodes\":[]}}}}".utf8)
        let requestExpectation = expectation(description: "Queryable branch is requested")
        let absentExpectation = expectation(description: "Queryable branch result is delivered")
        var excludedStatus: StatusLineData.PRTrackingState?
        let stalePR = PullRequest(number: 3, title: "Other branch", state: "open", url: "u")
        var excludedPR: PullRequest? = stalePR
        let runner = PRTrackingTestRunner(response: response, onRun: { requestExpectation.fulfill() })
        let coordinator = PRTrackingCoordinator(cliRunner: runner)
        coordinator.subscribers[queriedPaneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: repository.path,
            owner: "owner",
            repo: "repo",
            callback: { _ in },
            statusCallback: { status in
                if status == .absent { absentExpectation.fulfill() }
            },
            isActive: true)
        coordinator.subscribers[excludedPaneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: repository.deletingLastPathComponent().appending(path: UUID().uuidString).path,
            owner: "owner",
            repo: "repo",
            lastData: stalePR,
            status: .current,
            callback: { excludedPR = $0 },
            statusCallback: { excludedStatus = $0 },
            isActive: true)

        coordinator.runCycle()
        await fulfillment(of: [requestExpectation, absentExpectation], timeout: 5)

        XCTAssertEqual(coordinator.subscribers[queriedPaneID]?.status, .absent)
        XCTAssertNil(coordinator.subscribers[excludedPaneID]?.status)
        XCTAssertNil(excludedStatus)
        XCTAssertNil(coordinator.subscribers[excludedPaneID]?.lastData)
        XCTAssertNil(excludedPR)
        let query = try XCTUnwrap(runner.lastInput)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: query) as? [String: String])
        let queryText = try XCTUnwrap(body["query"])
        XCTAssertTrue(queryText.contains(queryAlias))
        XCTAssertFalse(queryText.contains(excludedAlias))
        coordinator.unsubscribe(paneID: queriedPaneID)
        coordinator.unsubscribe(paneID: excludedPaneID)
    }

    func testStaleRepositoryIdentityCannotUpdateReplacedSubscription() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        var status: StatusLineData.PRTrackingState?
        let original = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp/old",
            callback: { _ in },
            statusCallback: { status = $0 },
            isActive: true)
        let replacement = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp/new",
            callback: { _ in },
            statusCallback: { status = $0 },
            isActive: true)
        coordinator.subscribers[paneID] = replacement

        coordinator.setRepositoryIdentity(
            paneID: paneID,
            identityToken: original.identityToken,
            workingDirectory: original.workingDirectory,
            owner: "old-owner",
            repo: "old-repo")

        XCTAssertNil(coordinator.subscribers[paneID]?.owner)
        XCTAssertNil(coordinator.subscribers[paneID]?.repo)
        XCTAssertNil(status)
    }

    func testMissingRepositoryIdentityClearsOldPRWithoutReportingAbsence() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        let existing = PullRequest(number: 9, title: "Old branch", state: "open", url: "u")
        var deliveredPR: PullRequest? = existing
        var latestStatus: StatusLineData.PRTrackingState? = .current
        let record = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "old-branch",
            lastData: existing,
            status: .current,
            callback: { deliveredPR = $0 },
            statusCallback: { latestStatus = $0 },
            isActive: true)
        coordinator.subscribers[paneID] = record

        coordinator.setRepositoryIdentity(
            paneID: paneID,
            identityToken: record.identityToken,
            workingDirectory: record.workingDirectory,
            owner: nil,
            repo: nil)

        XCTAssertNil(coordinator.subscribers[paneID]?.lastData)
        XCTAssertNil(deliveredPR)
        XCTAssertNil(coordinator.subscribers[paneID]?.status)
        XCTAssertNil(latestStatus)
    }

    func testSuccessfulPRAndConfirmedAbsenceUpdateVisibleState() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        var latestStatus: StatusLineData.PRTrackingState?
        coordinator.subscribers[paneID] = PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: "owner",
            repo: "repo",
            branchName: "feature",
            callback: { _ in },
            statusCallback: { latestStatus = $0 },
            isActive: true)
        let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
        let found: [String: Any] = [
            alias: [
                "pullRequests": [
                    "nodes": [
                        [
                            "number": 17, "title": "Current", "state": "OPEN", "url": "u",
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(coordinator.deliverPRResults(from: found, paneIDs: [paneID]), 1)
        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 17)
        XCTAssertEqual(latestStatus, .current)

        XCTAssertEqual(
            coordinator.deliverPRResults(from: [alias: ["pullRequests": ["nodes": []]]], paneIDs: [paneID]), 0)
        XCTAssertNil(coordinator.subscribers[paneID]?.lastData)
        XCTAssertEqual(latestStatus, .absent)
    }

    func testParsePRReviewDecisionApproved() {
        let node: [String: Any] = [
            "number": 1, "title": "T", "state": "OPEN", "url": "u",
            "reviewDecision": "APPROVED",
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.reviewDecision, "APPROVED")
        XCTAssertEqual(pr?.reviewStateLabel, "approved")
    }

    func testParsePRReviewDecisionChangesRequested() {
        let node: [String: Any] = [
            "number": 1, "title": "T", "state": "OPEN", "url": "u",
            "reviewDecision": "CHANGES_REQUESTED",
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.reviewDecision, "CHANGES_REQUESTED")
        XCTAssertEqual(pr?.reviewStateLabel, "changes requested")
    }

    func testParsePRReviewDecisionReviewRequired() {
        let node: [String: Any] = [
            "number": 1, "title": "T", "state": "OPEN", "url": "u",
            "reviewDecision": "REVIEW_REQUIRED",
        ]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertEqual(pr?.reviewDecision, "REVIEW_REQUIRED")
        XCTAssertEqual(pr?.reviewStateLabel, "pending")
    }

    func testParsePRReviewDecisionNullIsNil() {
        let node: [String: Any] = ["number": 1, "title": "T", "state": "OPEN", "url": "u"]
        let pr = PRTrackingCoordinator.parsePRFromGraphQLNode(node)
        XCTAssertNil(pr?.reviewDecision)
        XCTAssertNil(pr?.reviewStateLabel)
    }

    func testPRDraftOverridesReviewStateLabel() {
        var pr = PullRequest(number: 1, title: "T", state: "open", url: "u")
        pr.isDraft = true
        pr.reviewDecision = "APPROVED"
        XCTAssertEqual(pr.reviewStateLabel, "draft")
    }

    func testBatchQueryIncludesReviewDecision() {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        coordinator.subscribers[paneID] = makeRecord(owner: "owner", repo: "repo", branch: "main")
        let query = coordinator.buildBatchQuery()
        XCTAssertTrue(query.contains("reviewDecision"), "Batch query must include reviewDecision field")
    }

    private func createGitRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory.appending(path: "pr-cycle-\(UUID().uuidString)")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["init", "-b", "feature", repository.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let commit = Process()
        commit.executableURL = URL(filePath: "/usr/bin/git")
        commit.arguments = [
            "-C", repository.path, "-c", "user.name=Agent Session Manager",
            "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "test",
        ]
        try commit.run()
        commit.waitUntilExit()
        XCTAssertEqual(commit.terminationStatus, 0)
        return repository
    }

    private func makeRecord(owner: String?, repo: String?, branch: String?) -> PRTrackingCoordinator.SubscriberRecord {
        PRTrackingCoordinator.SubscriberRecord(
            workingDirectory: "/tmp",
            owner: owner,
            repo: repo,
            branchName: branch,
            lastData: nil,
            callback: { _ in },
            isActive: true
        )
    }

    private func makeQueryResult(
        paneIDs: Set<UUID>,
        outData: Data = Data(),
        failure: GitHubCLIFailure? = nil
    ) -> PRTrackingCoordinator.QueryResult {
        PRTrackingCoordinator.QueryResult(
            outData: outData,
            exitStatus: failure == nil ? 0 : 4,
            result: failure?.rawValue ?? "ok",
            failure: failure,
            inputFailure: nil,
            count: paneIDs.count,
            paneIDs: paneIDs,
            startTime: Date(),
            endTime: Date()
        )
    }

    private func batchResponse(paneID: UUID, nodes: [[String: Any]]) throws -> Data {
        let alias = "pane_" + paneID.uuidString.replacingOccurrences(of: "-", with: "")
        let json: [String: Any] = [
            "data": [alias: ["pullRequests": ["nodes": nodes]]]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    @discardableResult
    private func makeTempSettingsDir(
        backgroundRefreshEnabled: Bool,
        backgroundIntervalSeconds: Int
    ) -> String {
        let subdirName = "pr-tests-\(UUID().uuidString)"
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appending(path: subdirName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "intervalSeconds": 30,
            "timeoutSeconds": 15,
            "backgroundRefreshEnabled": backgroundRefreshEnabled,
            "backgroundIntervalSeconds": backgroundIntervalSeconds,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: dir.appending(path: "pr-polling-settings.json"))
        }
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirName
        return subdirName
    }

    private func cleanupTempSettingsDir(_ subdirName: String) {
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: appSupport.appending(path: subdirName))
    }
}

private final class PRTrackingTestRunner: GitHubCLIRunning, @unchecked Sendable {
    private let response: Data
    private let onRun: @Sendable () -> Void
    private let lock = NSLock()
    private var inputs: [Data] = []

    var lastInput: Data? {
        lock.withLock { inputs.last }
    }

    init(response: Data, onRun: @escaping @Sendable () -> Void) {
        self.response = response
        self.onRun = onRun
    }

    func run(arguments: [String], stdin: Data?, timeout: TimeInterval) async -> GitHubCLIResult {
        if let stdin {
            lock.withLock { inputs.append(stdin) }
        }
        onRun()
        return GitHubCLIResult(
            stdout: response, stderrPrefix: "", exitCode: 0, failure: nil, inputFailure: nil)
    }
}
