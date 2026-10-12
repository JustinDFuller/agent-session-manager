import Foundation
import Observation

enum WorktreeCleanupDecision: Equatable {
    case followSetting
    case keep
    case delete
}

enum WorktreeCloseTarget {
    case pane(Pane)
    case tab(Tab)
}

enum WorktreeAskChoice {
    case delete
    case keep
    case cancel
}

enum WorktreeUnsavedChoice {
    case keep
    case deleteAnyway
    case cancel
}

struct WorktreeAskPrompt: Equatable {
    let title: String
    let message: String
    let deleteLabel: String
    let keepLabel: String
}

struct WorktreeUnsavedPrompt: Equatable {
    let title: String
    let message: String
    let keepLabel: String
}

struct WorktreeCleanupNotice: Equatable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class WorktreeCloseFlow {
    private(set) var askPrompt: WorktreeAskPrompt?
    private(set) var unsavedPrompt: WorktreeUnsavedPrompt?
    private(set) var notice: WorktreeCleanupNotice?

    private struct Candidate {
        let pane: Pane
        let checkout: URL
    }

    private struct Skipped {
        let name: String
        let reason: String
    }

    private struct Request {
        let target: WorktreeCloseTarget
        let tab: Tab
        let appState: AppState
        let appSettings: AppSettings
        let candidates: [Candidate]
    }

    private var request: Request?
    private var assessments: [WorktreeAssessment] = []
    private var skipped: [Skipped] = []
    private var lastExecution: Task<Void, Never>?

    static let processExitTimeout: Duration = .seconds(2)

    func begin(
        _ target: WorktreeCloseTarget,
        decision: WorktreeCleanupDecision = .followSetting,
        appState: AppState,
        appSettings: AppSettings
    ) {
        guard request == nil, askPrompt == nil, unsavedPrompt == nil else { return }
        guard let tab = Self.tab(of: target) else { return }
        let panes = Self.panes(of: target)
        let candidates = Self.candidates(in: panes)
        let pending = Request(
            target: target, tab: tab, appState: appState, appSettings: appSettings, candidates: candidates)
        guard !candidates.isEmpty else {
            close(pending)
            return
        }
        switch Self.effective(decision, setting: appSettings.worktreeCleanupBehavior) {
        case .keep:
            close(pending)
        case .delete:
            request = pending
            assess(pending)
        case .ask:
            request = pending
            askPrompt = Self.askPrompt(for: target, candidates: candidates)
        }
    }

    func answer(_ choice: WorktreeAskChoice) {
        askPrompt = nil
        guard let pending = request else { return }
        switch choice {
        case .cancel:
            request = nil
        case .keep:
            request = nil
            close(pending)
        case .delete:
            assess(pending)
        }
    }

    func answer(_ choice: WorktreeUnsavedChoice) {
        unsavedPrompt = nil
        guard let pending = request else { return }
        let atRisk = assessments.filter(\.hasUnsavedWork)
        switch choice {
        case .cancel:
            reset()
        case .keep:
            execute(pending, deleting: assessments.filter { !$0.hasUnsavedWork }, force: [])
        case .deleteAnyway:
            execute(pending, deleting: assessments, force: Set(atRisk.map { Self.key($0.checkout) }))
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func waitForCompletion() async {
        await lastExecution?.value
    }

    private func assess(_ pending: Request) {
        Task {
            var assessed: [WorktreeAssessment] = []
            var skippedNow: [Skipped] = []
            let closingIDs = Set(Self.panes(of: pending.target).map(\.id))
            for candidate in pending.candidates {
                let inUse = pending.appState.isCheckoutInUse(
                    directory: pending.tab.directory, checkout: candidate.checkout, excludingPaneIDs: closingIDs)
                if inUse {
                    skippedNow.append(Skipped(name: candidate.checkout.lastPathComponent, reason: Self.inUseReason))
                    continue
                }
                guard FileManager.default.fileExists(atPath: candidate.checkout.path) else {
                    assessed.append(Self.missing(candidate.checkout))
                    continue
                }
                do {
                    assessed.append(
                        try await WorktreeCleanup.assess(
                            repository: pending.tab.directory, checkout: candidate.checkout))
                } catch {
                    skippedNow.append(
                        Skipped(
                            name: candidate.checkout.lastPathComponent,
                            reason: "It could not be checked for unsaved work: \(error.localizedDescription)"))
                }
            }
            assessments = assessed
            skipped = skippedNow
            let atRisk = assessed.filter(\.hasUnsavedWork)
            if atRisk.isEmpty {
                execute(pending, deleting: assessed, force: [])
            } else {
                unsavedPrompt = Self.unsavedPrompt(
                    for: atRisk, deleteBranch: pending.appSettings.deleteBranchWithWorktree)
            }
        }
    }

    private func execute(_ pending: Request, deleting: [WorktreeAssessment], force: Set<String>) {
        let skippedNow = skipped
        let processIDs = Self.processIDs(in: Self.panes(of: pending.target))
        let deleteBranch = pending.appSettings.deleteBranchWithWorktree
        let repository = pending.tab.directory
        reset()
        close(pending)
        lastExecution = Task {
            await Self.waitForExit(of: processIDs)
            var lines: [String] = []
            var failed = false
            for assessment in deleting {
                let result = await WorktreeCleanup.remove(
                    repository: repository, checkout: assessment.checkout,
                    force: force.contains(Self.key(assessment.checkout)), deleteBranch: deleteBranch)
                switch result.outcome {
                case .deleted:
                    break
                case .kept(let reason):
                    lines.append("Kept \(result.name): \(reason)")
                case .failed(let reason):
                    failed = true
                    lines.append("Could not delete \(result.name): \(reason)")
                }
            }
            for item in skippedNow {
                lines.append("Kept \(item.name): \(item.reason)")
            }
            guard !lines.isEmpty else { return }
            notice = WorktreeCleanupNotice(
                title: failed ? "Worktree Cleanup Failed" : "Worktree Kept",
                message: lines.joined(separator: "\n"))
        }
    }

    private func close(_ pending: Request) {
        switch pending.target {
        case .pane(let pane):
            pending.tab.closePane(pane)
            SessionPersistence.save(appState: pending.appState)
        case .tab(let tab):
            pending.appState.closeTab(tab)
        }
    }

    private func reset() {
        request = nil
        assessments = []
        skipped = []
    }

    nonisolated static let inUseReason = "Another pane is still using it."

    nonisolated private static func key(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func tab(of target: WorktreeCloseTarget) -> Tab? {
        switch target {
        case .pane(let pane): return pane.tab
        case .tab(let tab): return tab
        }
    }

    private static func panes(of target: WorktreeCloseTarget) -> [Pane] {
        switch target {
        case .pane(let pane): return [pane]
        case .tab(let tab): return tab.panes
        }
    }

    private static func candidates(in panes: [Pane]) -> [Candidate] {
        var seen: Set<String> = []
        var result: [Candidate] = []
        for pane in panes where pane.worktreeIsManaged {
            guard let checkout = pane.worktreeDirectory, seen.insert(key(checkout)).inserted else { continue }
            result.append(Candidate(pane: pane, checkout: checkout))
        }
        return result
    }

    private static func effective(
        _ decision: WorktreeCleanupDecision, setting: WorktreeCleanupBehavior
    ) -> WorktreeCleanupBehavior {
        switch decision {
        case .keep: return .keep
        case .delete: return .delete
        case .followSetting: return setting
        }
    }

    private static func missing(_ checkout: URL) -> WorktreeAssessment {
        WorktreeAssessment(
            checkout: checkout, branch: nil, modifiedCount: 0, untrackedCount: 0, unpushedCommitCount: 0,
            isLocked: false, isUsedByOtherPane: false)
    }

    private static func askPrompt(for target: WorktreeCloseTarget, candidates: [Candidate]) -> WorktreeAskPrompt {
        let names = candidates.map { "\"\($0.checkout.lastPathComponent)\"" }
        switch target {
        case .pane:
            return WorktreeAskPrompt(
                title: "Close Worktree Pane",
                message:
                    "The worktree \(names.joined()) was created by Agent Session Manager. Would you like to delete it?",
                deleteLabel: "Delete Worktree", keepLabel: "Keep Worktree")
        case .tab(let tab):
            let noun = candidates.count == 1 ? "worktree" : "worktrees"
            return WorktreeAskPrompt(
                title: "Close Tab With Worktrees",
                message:
                    "The tab \"\(tab.name)\" uses \(candidates.count) \(noun) created by Agent Session Manager: "
                    + "\(names.joined(separator: ", ")). Would you like to delete \(candidates.count == 1 ? "it" : "them")?",
                deleteLabel: candidates.count == 1 ? "Delete Worktree" : "Delete Worktrees",
                keepLabel: candidates.count == 1 ? "Keep Worktree" : "Keep Worktrees")
        }
    }

    private static func unsavedPrompt(for atRisk: [WorktreeAssessment], deleteBranch: Bool) -> WorktreeUnsavedPrompt {
        let sections = atRisk.map { assessment -> String in
            var lines = ["\(assessment.name) has unsaved work:"] + assessment.unsavedWorkLines.map { "• \($0)" }
            if deleteBranch, let branch = assessment.branch, assessment.unpushedCommitCount > 0 {
                lines.append("Its branch \"\(branch)\" is deleted too.")
            }
            return lines.joined(separator: "\n")
        }
        let plural = atRisk.count > 1
        return WorktreeUnsavedPrompt(
            title: plural ? "Worktrees Have Unsaved Work" : "Worktree Has Unsaved Work",
            message: sections.joined(separator: "\n\n"),
            keepLabel: plural ? "Keep Worktrees" : "Keep Worktree")
    }

    private static func processIDs(in panes: [Pane]) -> [Int32] {
        panes.compactMap { pane in
            guard case .running(let pid) = pane.terminalController?.processState else { return nil }
            return pid
        }
    }

    private static func waitForExit(of processIDs: [Int32]) async {
        guard !processIDs.isEmpty else { return }
        let deadline = ContinuousClock.now + processExitTimeout
        while ContinuousClock.now < deadline, processIDs.contains(where: { kill($0, 0) == 0 }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
