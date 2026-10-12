import Foundation

struct WorktreeLeftover: Equatable, Sendable, Identifiable {
    let repository: URL
    let checkout: URL
    let isRegistered: Bool
    let keptReason: String?

    var id: String { checkout.path }
    var name: String { checkout.lastPathComponent }
    var isEligible: Bool { isRegistered && keptReason == nil }
}

struct WorktreeSweepOutcome: Equatable, Sendable {
    let leftover: WorktreeLeftover
    let result: WorktreeCleanupResult?
}

enum WorktreeLeftovers {
    static let minimumAge: TimeInterval = 24 * 60 * 60
    static let unregisteredReason = "It is not a git worktree."

    static func managedFolders(of repository: URL) -> [URL] {
        [
            repository.appending(path: Tab.worktreesRootRelativePath, directoryHint: .isDirectory),
            repository.appending(path: ".tree", directoryHint: .isDirectory),
        ]
    }

    static func scan(
        repositories: [URL], openCheckouts: Set<String>, now: Date = Date()
    ) async -> [WorktreeLeftover] {
        var leftovers: [WorktreeLeftover] = []
        for repository in repositories {
            leftovers += await scan(repository: repository, openCheckouts: openCheckouts, now: now)
        }
        return leftovers
    }

    static func sweep(
        repositories: [URL], openCheckouts: Set<String>, deleteBranch: Bool, now: Date = Date()
    ) async -> [WorktreeSweepOutcome] {
        var outcomes: [WorktreeSweepOutcome] = []
        for repository in repositories {
            _ = try? await GitRunner.output(["worktree", "prune"], in: repository)
            let leftovers = await scan(repository: repository, openCheckouts: openCheckouts, now: now)
            for leftover in leftovers {
                guard leftover.isEligible else {
                    TracingService.shared.record(
                        "worktree.leftover.skipped",
                        attributes: attributes(for: leftover, extra: ["reason": leftover.keptReason ?? ""]))
                    outcomes.append(WorktreeSweepOutcome(leftover: leftover, result: nil))
                    continue
                }
                let result = await WorktreeCleanup.remove(
                    repository: repository, checkout: leftover.checkout, deleteBranch: deleteBranch)
                switch result.outcome {
                case .deleted:
                    TracingService.shared.record(
                        "worktree.leftover.removed", attributes: attributes(for: leftover, extra: [:]))
                case .kept(let reason):
                    TracingService.shared.record(
                        "worktree.leftover.skipped",
                        attributes: attributes(for: leftover, extra: ["reason": reason]))
                case .failed(let reason):
                    TracingService.shared.record(
                        "worktree.leftover.failed",
                        attributes: attributes(for: leftover, extra: ["reason": reason]))
                }
                outcomes.append(WorktreeSweepOutcome(leftover: leftover, result: result))
            }
        }
        return outcomes
    }

    private static func scan(repository: URL, openCheckouts: Set<String>, now: Date) async -> [WorktreeLeftover] {
        guard FileManager.default.fileExists(atPath: repository.path),
            let listing = try? await GitRunner.output(["worktree", "list", "--porcelain"], in: repository)
        else { return [] }
        let registered = Set(
            Tab.parseWorktreeListPorcelain(listing).map { URL(filePath: $0.path).resolvingSymlinksInPath().path })
        var leftovers: [WorktreeLeftover] = []
        for folder in managedFolders(of: repository) {
            for entry in children(of: folder) {
                let child = entry.resolvingSymlinksInPath()
                let resolved = child.path
                if openCheckouts.contains(resolved) { continue }
                guard registered.contains(resolved) else {
                    leftovers.append(
                        WorktreeLeftover(
                            repository: repository, checkout: child, isRegistered: false,
                            keptReason: unregisteredReason))
                    continue
                }
                let reason = await keptReason(repository: repository, checkout: child, now: now)
                leftovers.append(
                    WorktreeLeftover(repository: repository, checkout: child, isRegistered: true, keptReason: reason))
            }
        }
        return leftovers
    }

    private static func keptReason(repository: URL, checkout: URL, now: Date) async -> String? {
        let changed = lastChange(of: checkout)
        let assessment: WorktreeAssessment
        do {
            assessment = try await WorktreeCleanup.assess(repository: repository, checkout: checkout)
        } catch {
            return "It could not be checked: \(error.localizedDescription)"
        }
        if assessment.isLocked { return "It is locked in git." }
        if assessment.hasUnsavedWork {
            return "It has unsaved work: \(assessment.unsavedWorkLines.joined(separator: ", "))."
        }
        guard let changed else { return "Its age could not be determined." }
        if now.timeIntervalSince(changed) < minimumAge { return "It changed within the last 24 hours." }
        return nil
    }

    private static func lastChange(of checkout: URL) -> Date? {
        guard
            let pointer = try? String(contentsOf: checkout.appending(path: ".git"), encoding: .utf8),
            pointer.hasPrefix("gitdir:")
        else { return nil }
        let admin = URL(
            filePath: pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines),
            directoryHint: .isDirectory)
        let dates = ["HEAD", "index"].compactMap { name -> Date? in
            let attributes = try? FileManager.default.attributesOfItem(atPath: admin.appending(path: name).path)
            return attributes?[.modificationDate] as? Date
        }
        return dates.max()
    }

    private static func children(of folder: URL) -> [URL] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        return entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func attributes(for leftover: WorktreeLeftover, extra: [String: String]) -> [String: String] {
        var result = ["repository": leftover.repository.path, "checkout": leftover.checkout.path]
        for (key, value) in extra { result[key] = value }
        return result
    }
}

@MainActor
enum LaunchCleanup {
    static func openCheckoutPaths(in appState: AppState) -> Set<String> {
        Set(
            appState.tabs.flatMap { tab in
                tab.panes.compactMap { $0.worktreePath?.resolvingSymlinksInPath().path }
            })
    }

    @discardableResult
    static func start(appState: AppState, appSettings: AppSettings) -> Task<[WorktreeSweepOutcome], Never>? {
        KnownRepositories.refresh(with: appState.tabs.map(\.directory))
        guard appSettings.cleanUpLeftoversAtLaunch else { return nil }
        let repositories = KnownRepositories.load()
        let openCheckouts = openCheckoutPaths(in: appState)
        let deleteBranch = appSettings.deleteBranchWithWorktree
        return Task.detached(priority: .utility) {
            await WorktreeLeftovers.sweep(
                repositories: repositories, openCheckouts: openCheckouts, deleteBranch: deleteBranch)
        }
    }
}
