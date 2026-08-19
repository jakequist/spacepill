import Foundation

// MARK: - Output

func output(_ text: String) {
    print(text)
}

func warn(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Pretty-prints a `data` object exactly as the app sent it, for `--json`.
func emitJSON(_ object: Any) throws {
    let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: options),
          let text = String(data: data, encoding: .utf8) else {
        throw CLIFailure("Could not render that response as JSON.")
    }
    output(text)
}

// MARK: - Where this binary lives

enum Install {
    /// This binary's real path. `install-cli` puts a symlink on PATH, so resolve it.
    static var executableURL: URL? {
        guard let path = Bundle.main.executablePath else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    /**
     * The SpacePill.app that contains this binary, when there is one.
     *
     * The CLI ships inside `SpacePill.app/Contents/MacOS/`, so walking two
     * levels up finds the bundle -- which is also where the version number
     * lives, avoiding a second copy of it in the source tree.
     */
    static var containingAppBundle: URL? {
        guard let executable = executableURL else { return nil }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        let bundle = contents.deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents", bundle.pathExtension == "app" else { return nil }
        return bundle
    }

    /// Version stamped into the containing bundle, if this copy is bundled.
    static var bundledVersion: String? {
        guard let bundle = containingAppBundle,
              let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let version = plist["CFBundleShortVersionString"] as? String,
              version != "0.0.0" else { return nil }
        return version
    }

    /**
     * Best available version string: the bundle this binary ships in, else
     * whatever the running app reports, else unknown.
     */
    static func resolveVersion() -> String {
        if let version = bundledVersion { return version }
        if let status = try? Client.send("status"), let version = status["version"] as? String {
            return version
        }
        return "unknown"
    }
}

// MARK: - Subprocesses

struct CommandResult {
    let status: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { status == 0 }
}

/**
 * Runs a tool and captures its output. Returns a non-zero status rather than
 * throwing when the tool is missing, so callers can treat "tool absent" and
 * "tool said no" the same way.
 */
@discardableResult
func runTool(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    do {
        try process.run()
    } catch {
        return CommandResult(status: 127, standardOutput: "", standardError: error.localizedDescription)
    }

    // Read before waiting: a tool that fills the 64 KB pipe buffer would
    // otherwise block forever waiting for us to drain it.
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return CommandResult(
        status: process.terminationStatus,
        standardOutput: String(data: outData, encoding: .utf8) ?? "",
        standardError: String(data: errData, encoding: .utf8) ?? ""
    )
}

// MARK: - Semantic versions

/**
 * Compares dotted numeric versions, ignoring a leading `v` and any pre-release
 * suffix. Returns nil when either side is not parseable, so callers can degrade
 * to "just tell the user both numbers" instead of guessing.
 */
func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult? {
    func parse(_ raw: String) -> [Int]? {
        let core = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-").first.map(String.init) ?? ""
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    guard var left = parse(lhs), var right = parse(rhs) else { return nil }
    while left.count < right.count { left.append(0) }
    while right.count < left.count { right.append(0) }

    for (a, b) in zip(left, right) {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
    }
    return .orderedSame
}
