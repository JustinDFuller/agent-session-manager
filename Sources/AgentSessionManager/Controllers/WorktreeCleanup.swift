import Foundation

struct WorktreeAssessment: Equatable, Sendable {
    let checkout: URL
    let branch: String?
    let modifiedCount: Int
    let untrackedCount: Int
    let unpushedCommitCount: Int
    let isLocked: Bool
    let isUsedByOtherPane: Bool

    var name: String { checkout.lastPathComponent }
    var isDetached: Bool { branch == nil }
    var hasUnsavedWork: Bool { modifiedCount + untrackedCount + unpushedCommitCount > 0 }

    var unsavedWorkLines: [String] {
        var lines: [String] = []
        if modifiedCount > 0 {
            lines.append("\(modifiedCount) modified \(modifiedCount == 1 ? "file" : "files")")
        }
        if untrackedCount > 0 {
            lines.append("\(untrackedCount) untracked \(untrackedCount == 1 ? "file" : "files")")
        }
        if unpushedCommitCount > 0 {
            let target = branch.map { " on \($0)" } ?? " on a detached HEAD"
            lines.append(
                "\(unpushedCommitCount) \(unpushedCommitCount == 1 ? "commit" : "commits") not on any remote\(target)")
        }
        return lines
    }
}

enum WorktreeBranchOutcome: Equatable, Sendable {
    case notRequested
    case deleted(String)
    case kept(String, reason: String)
}

enum WorktreeCleanupOutcome: Equatable, Sendable {
    case deleted(branch: WorktreeBranchOutcome)
    case kept(reason: String)
    case failed(reason: String)
}

struct WorktreeCleanupResult: Equatable, Sendable {
    let checkout: URL
    let outcome: WorktreeCleanupOutcome

    var name: String { checkout.lastPathComponent }

    var isDeleted: Bool {
        if case .deleted = outcome { return true }
        return false
    }
}

enum WorktreeCleanup {
    static func assess(
        repository: URL, checkout: URL, isUsedByOtherPane: Bool = false
    ) async throws -> WorktreeAssessment {
        let status = try await GitRunner.output(
            ["--no-optional-locks", "status", "--porcelain=v1", "-z", "--untracked-files=all"], in: checkout)
        let (modified, untracked) = countChanges(porcelainZ: status)
        let head = try await GitRunner.output(["rev-parse", "--abbrev-ref", "HEAD"], in: checkout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let unpushed = try await GitRunner.output(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: checkout)
        let entries = try await listEntries(repository: repository)
        let resolved = checkout.resolvingSymlinksInPath().path
        let isLocked = entries.first { URL(filePath: $0.path).resolvingSymlinksInPath().path == resolved }?.isLocked
        return WorktreeAssessment(
            checkout: checkout,
            branch: head == "HEAD" ? nil : head,
            modifiedCount: modified,
            untrackedCount: untracked,
            unpushedCommitCount: Int(unpushed.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            isLocked: isLocked ?? false,
            isUsedByOtherPane: isUsedByOtherPane)
    }

    static func remove(
        repository: URL, checkout: URL, force: Bool = false, deleteBranch: Bool
    ) async -> WorktreeCleanupResult {
        let resolvedCheckout = checkout.resolvingSymlinksInPath()
        guard resolvedCheckout.path != repository.resolvingSymlinksInPath().path else {
            return WorktreeCleanupResult(
                checkout: checkout, outcome: .kept(reason: "It is the repository's main checkout."))
        }
        do {
            let entries = try await listEntries(repository: repository)
            let target = entries.first {
                URL(filePath: $0.path).resolvingSymlinksInPath().path == resolvedCheckout.path
            }
            guard FileManager.default.fileExists(atPath: checkout.path) else {
                try await prune(repository: repository)
                return WorktreeCleanupResult(checkout: checkout, outcome: .deleted(branch: .notRequested))
            }
            guard let target else {
                return WorktreeCleanupResult(
                    checkout: checkout, outcome: .kept(reason: "Git does not list it as a worktree of this repository.")
                )
            }
            let branch = target.branch.map(branchName(fromRef:))
            let checkedOutElsewhere = Set(
                entries.filter { $0.path != target.path }.compactMap { $0.branch.map(branchName(fromRef:)) })
            try await GitRunner.output(
                ["worktree", "remove"] + (force ? ["--force"] : []) + [checkout.path], in: repository)
            try await prune(repository: repository)
            guard deleteBranch, let branch else {
                return WorktreeCleanupResult(checkout: checkout, outcome: .deleted(branch: .notRequested))
            }
            let outcome = await removeBranch(
                branch, repository: repository, force: force, checkedOutElsewhere: checkedOutElsewhere)
            return WorktreeCleanupResult(checkout: checkout, outcome: .deleted(branch: outcome))
        } catch {
            return WorktreeCleanupResult(checkout: checkout, outcome: .failed(reason: error.localizedDescription))
        }
    }

    static func countChanges(porcelainZ output: String) -> (modified: Int, untracked: Int) {
        var modified = 0
        var untracked = 0
        var skipNext = false
        for token in output.split(separator: "\0", omittingEmptySubsequences: true) {
            if skipNext {
                skipNext = false
                continue
            }
            guard token.count >= 3 else { continue }
            let code = token.prefix(2)
            if code == "??" {
                untracked += 1
            } else if code != "!!" {
                modified += 1
                if code.contains("R") || code.contains("C") { skipNext = true }
            }
        }
        return (modified, untracked)
    }

    private static func listEntries(repository: URL) async throws -> [GitWorktreeListEntry] {
        Tab.parseWorktreeListPorcelain(
            try await GitRunner.output(["worktree", "list", "--porcelain"], in: repository))
    }

    private static func prune(repository: URL) async throws {
        try await GitRunner.output(["worktree", "prune"], in: repository)
    }

    private static func branchName(fromRef ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    private static func removeBranch(
        _ branch: String, repository: URL, force: Bool, checkedOutElsewhere: Set<String>
    ) async -> WorktreeBranchOutcome {
        if checkedOutElsewhere.contains(branch) {
            return .kept(branch, reason: "It is checked out in another worktree.")
        }
        if await defaultBranches(repository: repository).contains(branch) {
            return .kept(branch, reason: "It is the repository's default branch.")
        }
        do {
            let unpushed = try await GitRunner.output(
                ["rev-list", "--count", "refs/heads/\(branch)", "--not", "--remotes"], in: repository)
            let hasUnpushed = (Int(unpushed.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
            let flag = (force || !hasUnpushed) ? "-D" : "-d"
            try await GitRunner.output(["branch", flag, branch], in: repository)
            return .deleted(branch)
        } catch {
            return .kept(branch, reason: error.localizedDescription)
        }
    }

    private static func defaultBranches(repository: URL) async -> Set<String> {
        var names: Set<String> = ["main", "master"]
        if let head = try? await GitRunner.output(
            ["for-each-ref", "--format=%(symref:short)", "refs/remotes/origin/HEAD"], in: repository)
        {
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("origin/") { names.insert(String(trimmed.dropFirst("origin/".count))) }
        }
        return names
    }
}
