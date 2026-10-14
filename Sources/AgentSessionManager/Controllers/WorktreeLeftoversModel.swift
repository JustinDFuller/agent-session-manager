import Foundation
import Observation

struct WorktreeLeftoverUnsavedPrompt: Equatable {
    let title: String
    let message: String
    let keepLabel: String
}

struct WorktreeLeftoverFolderPrompt: Equatable {
    let title: String
    let message: String
    let deleteLabel: String
}

@MainActor
@Observable
final class WorktreeLeftoversModel {
    private(set) var leftovers: [WorktreeLeftover] = []
    private(set) var sizes: [String: Int64] = [:]
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var unsavedPrompt: WorktreeLeftoverUnsavedPrompt?
    private(set) var folderPrompt: WorktreeLeftoverFolderPrompt?
    private(set) var notice: WorktreeCleanupNotice?
    var selection: Set<String> = []

    private var pending: Pending?
    private var isAssessingDeletion = false
    private var rescanRequested = false
    private var lastDeletion: Task<Void, Never>?

    private struct Pending {
        let appState: AppState
        let appSettings: AppSettings
        let registered: [WorktreeLeftover]
        let unregistered: [WorktreeLeftover]
        let atRisk: Set<String>
        let kept: [String]
    }

    func scan(appState: AppState, appSettings: AppSettings) async {
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        defer {
            isScanning = false
            hasScanned = true
        }
        repeat {
            rescanRequested = false
            let repositories = Self.repositories(appState: appState)
            let openCheckouts = LaunchCleanup.openCheckoutPaths(in: appState)
            let found = await Task.detached(priority: .utility) {
                await WorktreeLeftovers.scan(repositories: repositories, openCheckouts: openCheckouts)
            }.value
            leftovers = found
            selection.formIntersection(Set(found.map(\.id)))
            sizes = sizes.filter { entry in found.contains { $0.id == entry.key } }
        } while rescanRequested
    }

    func loadSize(of leftover: WorktreeLeftover) async {
        guard sizes[leftover.id] == nil else { return }
        let folder = leftover.checkout
        let size = await Task.detached(priority: .utility) { WorktreeLeftovers.size(of: folder) }.value
        sizes[leftover.id] = size
    }

    func reason(for leftover: WorktreeLeftover, launchCleanupEnabled: Bool) -> String {
        if let kept = leftover.keptReason { return kept }
        return launchCleanupEnabled
            ? "It is safe to delete and will be removed at the next launch."
            : "Clean Up Leftovers at Launch is off."
    }

    func requestDelete(appState: AppState, appSettings: AppSettings) {
        guard !isAssessingDeletion, pending == nil, unsavedPrompt == nil, folderPrompt == nil else { return }
        let chosen = leftovers.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isAssessingDeletion = true
        let openCheckouts = LaunchCleanup.openCheckoutPaths(in: appState)
        lastDeletion = Task {
            defer { isAssessingDeletion = false }
            var registered: [WorktreeLeftover] = []
            var unregistered: [WorktreeLeftover] = []
            var kept: [String] = []
            var atRisk: [(WorktreeLeftover, WorktreeAssessment)] = []
            for leftover in chosen {
                if openCheckouts.contains(leftover.checkout.resolvingSymlinksInPath().path) {
                    kept.append("Kept \(leftover.name): \(WorktreeCloseFlow.inUseReason)")
                    continue
                }
                guard leftover.isRegistered else {
                    unregistered.append(leftover)
                    continue
                }
                do {
                    let assessment = try await WorktreeCleanup.assess(
                        repository: leftover.repository, checkout: leftover.checkout)
                    if assessment.hasUnsavedWork { atRisk.append((leftover, assessment)) }
                    registered.append(leftover)
                } catch {
                    kept.append(
                        "Kept \(leftover.name): It could not be checked for unsaved work: "
                            + error.localizedDescription)
                }
            }
            pending = Pending(
                appState: appState, appSettings: appSettings, registered: registered,
                unregistered: unregistered, atRisk: Set(atRisk.map(\.0.id)), kept: kept)
            if atRisk.isEmpty {
                continueAfterUnsavedChoice()
            } else {
                unsavedPrompt = Self.unsavedPrompt(
                    for: atRisk.map(\.1), deleteBranch: appSettings.deleteBranchWithWorktree)
            }
        }
    }

    func answer(_ choice: WorktreeUnsavedChoice) {
        unsavedPrompt = nil
        guard let current = pending else { return }
        switch choice {
        case .cancel:
            pending = nil
        case .keep:
            pending = Pending(
                appState: current.appState, appSettings: current.appSettings,
                registered: current.registered.filter { !current.atRisk.contains($0.id) },
                unregistered: current.unregistered, atRisk: [], kept: current.kept)
            continueAfterUnsavedChoice()
        case .deleteAnyway:
            continueAfterUnsavedChoice()
        }
    }

    func confirmFolders(_ confirmed: Bool) {
        folderPrompt = nil
        guard let current = pending else { return }
        if confirmed {
            execute(current)
        } else {
            pending = nil
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func waitForDeletion() async {
        var awaited: Task<Void, Never>?
        while let current = lastDeletion, current != awaited {
            awaited = current
            await current.value
        }
    }

    private func continueAfterUnsavedChoice() {
        guard let current = pending else { return }
        if current.unregistered.isEmpty {
            execute(current)
        } else {
            folderPrompt = Self.folderPrompt(for: current.unregistered)
        }
    }

    private func execute(_ current: Pending) {
        pending = nil
        let deleteBranch = current.appSettings.deleteBranchWithWorktree
        lastDeletion = Task {
            var lines = current.kept
            var failed = false
            for leftover in current.registered {
                if current.appState.isCheckoutInUse(checkout: leftover.checkout) {
                    lines.append("Kept \(leftover.name): \(WorktreeCloseFlow.inUseReason)")
                    continue
                }
                let result = await WorktreeCleanup.remove(
                    repository: leftover.repository, checkout: leftover.checkout,
                    force: current.atRisk.contains(leftover.id), deleteBranch: deleteBranch)
                Self.collect(result, into: &lines, failed: &failed)
            }
            for leftover in current.unregistered {
                if current.appState.isCheckoutInUse(checkout: leftover.checkout) {
                    lines.append("Kept \(leftover.name): \(WorktreeCloseFlow.inUseReason)")
                    continue
                }
                let result = await WorktreeLeftovers.removeUnregistered(leftover)
                Self.collect(result, into: &lines, failed: &failed)
            }
            notice = WorktreeCleanupNotice.posting(lines: lines, failed: failed, over: notice)
            await scan(appState: current.appState, appSettings: current.appSettings)
        }
    }

    private static func collect(_ result: WorktreeCleanupResult, into lines: inout [String], failed: inout Bool) {
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

    private static func repositories(appState: AppState) -> [URL] {
        var seen: Set<String> = []
        return (KnownRepositories.load() + appState.tabs.map(\.directory)).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
    }

    private static func unsavedPrompt(
        for atRisk: [WorktreeAssessment], deleteBranch: Bool
    ) -> WorktreeLeftoverUnsavedPrompt {
        let sections = atRisk.map { assessment -> String in
            var lines = ["\(assessment.name) has unsaved work:"] + assessment.unsavedWorkLines.map { "• \($0)" }
            if deleteBranch, let branch = assessment.branch, assessment.unpushedCommitCount > 0 {
                lines.append("Its branch \"\(branch)\" is deleted too.")
            }
            return lines.joined(separator: "\n")
        }
        let plural = atRisk.count > 1
        return WorktreeLeftoverUnsavedPrompt(
            title: plural ? "Worktrees Have Unsaved Work" : "Worktree Has Unsaved Work",
            message: sections.joined(separator: "\n\n"),
            keepLabel: plural ? "Keep Worktrees" : "Keep Worktree")
    }

    private static func folderPrompt(for folders: [WorktreeLeftover]) -> WorktreeLeftoverFolderPrompt {
        let plural = folders.count > 1
        let names = folders.map { "\"\($0.name)\"" }.joined(separator: ", ")
        return WorktreeLeftoverFolderPrompt(
            title: plural ? "Delete Folders?" : "Delete Folder?",
            message:
                "\(names) \(plural ? "are" : "is") not a git worktree. Deleting removes \(plural ? "them" : "it") "
                + "from disk and cannot be undone.",
            deleteLabel: plural ? "Delete Folders" : "Delete Folder")
    }
}
