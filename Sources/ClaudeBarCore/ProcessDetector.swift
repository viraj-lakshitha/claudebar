import Foundation

/// Finds running Claude Code CLI processes. They keep using the account they
/// started with, and may write its refreshed tokens back after a switch.
public enum ProcessDetector {
    public static func runningClaudePIDs() -> [Int32] {
        guard let result = try? Shell.run("/bin/ps", ["-Axo", "pid=,args="]), result.status == 0 else {
            return []
        }
        let own = ProcessInfo.processInfo.processIdentifier
        return parse(result.stdoutString).filter { $0 != own }
    }

    /// Parses `ps -Axo pid=,args=` output and returns PIDs that look like the
    /// Claude Code CLI (native binary or the npm `cli.js`).
    public static func parse(_ output: String) -> [Int32] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]) else { return nil }
            let args = trimmed[space...].trimmingCharacters(in: .whitespaces)
            return isClaudeCLI(args) ? pid : nil
        }
    }

    static func isClaudeCLI(_ args: String) -> Bool {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let executable = parts.first else { return false }
        let name = (executable as NSString).lastPathComponent
        // Native installer binary or an npm shim resolved to `claude`.
        if name == "claude" { return true }
        // npm install: `node /…/@anthropic-ai/claude-code/cli.js`
        if name == "node" || name.hasPrefix("node") {
            return parts.dropFirst().contains { $0.contains("@anthropic-ai/claude-code/") || ($0 as NSString).lastPathComponent == "claude" }
        }
        return false
    }
}
