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
        var deliveredStatuses: [PRTrackingStatus] = []
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

        coordinator.handleBatchResponse(makeQueryResult(failure: .authentication), token: 0)

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 42)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .failed(.authentication))
        XCTAssertTrue(deliveredPRs.isEmpty)
        XCTAssertEqual(deliveredStatuses.last, .failed(.authentication))
    }

    func testConfirmedNoPRClearsCachedPRAndSuccessfulRetryRecovers() throws {
        let coordinator = PRTrackingCoordinator()
        let paneID = UUID()
        var deliveredPRs: [PullRequest?] = []
        var deliveredStatuses: [PRTrackingStatus] = []
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
            makeQueryResult(outData: try batchResponse(paneID: paneID, nodes: [])), token: 0)

        XCTAssertNil(coordinator.subscribers[paneID]?.lastData)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .noPullRequest)
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
            makeQueryResult(outData: try batchResponse(paneID: paneID, nodes: found)), token: 0)

        XCTAssertEqual(coordinator.subscribers[paneID]?.lastData?.number, 43)
        XCTAssertEqual(coordinator.subscribers[paneID]?.status, .current)
        XCTAssertEqual(deliveredStatuses, [.noPullRequest, .current])
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

        coordinator.handleBatchResponse(makeQueryResult(outData: outData), token: 0)

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
        outData: Data = Data(),
        failure: GitHubCLIFailure? = nil
    ) -> PRTrackingCoordinator.QueryResult {
        PRTrackingCoordinator.QueryResult(
            outData: outData,
            exitStatus: failure == nil ? 0 : 4,
            result: failure?.rawValue ?? "ok",
            failure: failure,
            inputFailure: nil,
            count: 1,
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
