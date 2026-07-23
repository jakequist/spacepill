import Foundation

/**
 * `spacepill` -- the command-line client for SpacePill.app.
 *
 * Everything here is a thin wrapper over the Unix socket in `Client`: this
 * binary never touches SkyLight, never posts a keystroke, and needs no
 * permissions of its own. See `CLIServer.swift` in the app for why.
 */

// MARK: - Argument parsing

/// Options that consume the following argument. Anything else beginning with
/// `--` is a boolean flag, so a typo surfaces as "unknown flag" rather than
/// silently eating the next word.
private let valueOptions: Set<String> = ["--space", "--color", "--colour"]

struct Arguments {
    private(set) var positional: [String] = []
    private var flags: Set<String> = []
    private var options: [String: String] = [:]

    init(_ raw: [String]) throws {
        var iterator = raw.makeIterator()
        while let token = iterator.next() {
            guard token.hasPrefix("--") else {
                positional.append(token)
                continue
            }

            var name = token
            var inlineValue: String?
            if let separator = token.firstIndex(of: "="), separator != token.startIndex {
                name = String(token[token.startIndex..<separator])
                inlineValue = String(token[token.index(after: separator)...])
            }

            if valueOptions.contains(name) {
                guard let value = inlineValue ?? iterator.next() else {
                    throw CLIFailure("\(name) needs a value.", .usage)
                }
                options[name] = value
            } else {
                guard inlineValue == nil else {
                    throw CLIFailure("\(name) does not take a value.", .usage)
                }
                flags.insert(name)
            }
        }
    }

    func has(_ flag: String) -> Bool { flags.contains(flag) }

    func value(_ names: String...) -> String? {
        names.compactMap { options[$0] }.first
    }

    /// Flags that no command claimed -- almost always a typo.
    func unknownFlags(allowed: Set<String>) -> [String] {
        flags.subtracting(allowed).sorted()
    }

    /// `--space N`, validated.
    func spaceIndex() throws -> Int? {
        guard let raw = value("--space") else { return nil }
        guard let index = Int(raw), index >= 1 else {
            throw CLIFailure("--space needs a positive space number, not \"\(raw)\".", .usage)
        }
        return index
    }
}

// MARK: - Formatting

/// `FFFF9500` (the stored AARRGGBB form) reads better as `#FF9500`.
func displayHex(_ raw: String?) -> String? {
    guard var hex = raw?.uppercased() else { return nil }
    if hex.count == 8, hex.hasPrefix("FF") { hex = String(hex.dropFirst(2)) }
    return "#" + hex
}

func describeSpace(_ space: [String: Any], total: Int?) -> String {
    let index = space["index"] as? Int ?? 0
    var line = total.map { "Space \(index) of \($0)" } ?? "Space \(index)"

    if let label = space["label"] as? String, !label.isEmpty {
        line += ": \(label)"
    } else {
        line += " (unlabelled)"
    }
    if let hex = displayHex(space["hexColor"] as? String) {
        line += "  \(hex)"
    }
    return line
}

// MARK: - Commands

func commandCurrent(_ args: Arguments) throws {
    let status = try Client.send("status")

    if args.has("--json") {
        try emitJSON(status)
        return
    }

    guard let current = status["currentSpace"] as? [String: Any] else {
        throw CLIFailure("SpacePill could not determine the current space.")
    }
    output(describeSpace(current, total: status["spaceCount"] as? Int))
}

func commandList(_ args: Arguments) throws {
    let data = try Client.send("list")

    if args.has("--json") {
        try emitJSON(data)
        return
    }

    let spaces = data["spaces"] as? [[String: Any]] ?? []
    guard !spaces.isEmpty else {
        output("No spaces reported.")
        return
    }

    let labels = spaces.map { ($0["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(unlabelled)" }
    let labelWidth = max(labels.map(\.count).max() ?? 0, 5)
    let indexWidth = max(spaces.compactMap { $0["index"] as? Int }.map { String($0).count }.max() ?? 1, 1)

    for (space, label) in zip(spaces, labels) {
        let index = space["index"] as? Int ?? 0
        let marker = (space["isCurrent"] as? Bool == true) ? "*" : " "
        let color = displayHex(space["hexColor"] as? String) ?? ""

        var line = "\(marker) \(String(index).leftPadded(to: indexWidth))  "
        line += label.rightPadded(to: labelWidth) + "  "
        line += color.rightPadded(to: 7)

        if space["isReachable"] as? Bool == false {
            line += "  (can't switch here)"
        }
        output(line.trimmedTrailing())
    }

    let unreachable = spaces.filter { $0["isReachable"] as? Bool == false }.count
    if unreachable > 0 {
        output("")
        output("\(unreachable) space\(unreachable == 1 ? "" : "s") cannot be switched to. Run `spacepill doctor` to find out why.")
    }
}

func commandSwitch(_ args: Arguments) throws {
    guard let target = args.positional.first else {
        throw CLIFailure("Usage: spacepill switch <index|label>", .usage)
    }

    let data = try Client.send("switch", ["target": target])
    guard let space = data["switchedTo"] as? [String: Any] else {
        output("Switched.")
        return
    }
    output("Switched to \(describeSpace(space, total: nil))")
}

func commandLabel(_ args: Arguments) throws {
    var request: [String: Any] = [:]
    if let index = try args.spaceIndex() { request["index"] = index }

    if args.has("--clear") {
        let data = try Client.send("clear-label", request)
        let index = data["index"] as? Int ?? 0
        output("Cleared the label on space \(index).")
        return
    }

    let text = args.positional.first
    let color = args.value("--color", "--colour")

    guard text != nil || color != nil else {
        throw CLIFailure("Usage: spacepill label <text> [--space N] [--color <hex>]\n       spacepill label --clear [--space N]", .usage)
    }

    if let text = text { request["label"] = text }
    if let color = color { request["hexColor"] = color }

    let data = try Client.send("set-label", request)
    output("Updated " + describeSpace(data, total: nil))
}

func commandNotes(_ args: Arguments) throws {
    var request: [String: Any] = [:]
    if let index = try args.spaceIndex() { request["index"] = index }

    if args.has("--path") {
        let data = try Client.send("notes-path", request)
        output(data["path"] as? String ?? "")
        return
    }

    if args.has("--edit") {
        try editNotes(request)
        return
    }

    if args.has("--set") {
        let text: String
        if let inline = args.positional.first {
            text = inline
        } else {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            text = String(data: input, encoding: .utf8) ?? ""
        }
        request["text"] = text
        let data = try Client.send("notes-set", request)
        warn("Wrote \(data["bytes"] as? Int ?? 0) bytes to the notes for space \(data["index"] as? Int ?? 0).")
        return
    }

    let data = try Client.send("notes-get", request)
    let text = data["text"] as? String ?? ""
    // Print without adding a newline the notes did not have.
    FileHandle.standardOutput.write(Data(text.utf8))
    if !text.isEmpty && !text.hasSuffix("\n") {
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func editNotes(_ request: [String: Any]) throws {
    let existing = try Client.send("notes-get", request)
    let text = existing["text"] as? String ?? ""
    let index = existing["index"] as? Int ?? 0

    let editor = ProcessInfo.processInfo.environment["VISUAL"]
        ?? ProcessInfo.processInfo.environment["EDITOR"]
        ?? "vi"

    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("spacepill-notes-\(index)-\(UUID().uuidString).md")
    try text.write(to: scratch, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: scratch) }

    // Editors own the terminal, so hand them stdio directly rather than
    // capturing it the way `run` does.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "\(editor) \"$1\"", "sh", scratch.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CLIFailure("\(editor) exited with status \(process.terminationStatus); notes were not changed.")
    }

    let edited = (try? String(contentsOf: scratch, encoding: .utf8)) ?? ""
    guard edited != text else {
        warn("No changes.")
        return
    }

    var write = request
    write["text"] = edited
    let data = try Client.send("notes-set", write)
    warn("Wrote \(data["bytes"] as? Int ?? 0) bytes to the notes for space \(data["index"] as? Int ?? 0).")
}

func commandDoctor() throws {
    var healthy = true

    /// `remedy` is only shown on failure -- a passing check that lectures the
    /// user about how to fix it is just noise. `notes` always shows.
    func report(_ passed: Bool, _ headline: String, remedy: [String] = [], notes: [String] = []) {
        output("\(passed ? "  ok  " : " FAIL ") \(headline)")
        for line in notes + (passed ? [] : remedy) {
            output(line.isEmpty ? "" : "       \(line)")
        }
        if !passed { healthy = false }
    }

    output("SpacePill doctor")
    output("")

    let status: [String: Any]
    do {
        status = try Client.send("status")
    } catch let failure as CLIFailure where failure.exitCode == .notRunning {
        report(false, "SpacePill.app is not running", remedy: [
            "Everything else depends on it. Launch SpacePill.app, then run this again.",
            "If it is installed but will not stay open, check the log:",
            "  log show --predicate 'subsystem == \"com.jake.SpacePill\"' --last 5m"
        ])
        throw CLIFailure("", .notRunning)
    }

    report(true, "SpacePill.app is running (version \(status["version"] as? String ?? "unknown"))")

    let permissions = status["permissions"] as? [String: Any] ?? [:]

    report(permissions["accessibility"] as? Bool == true,
           "Accessibility permission",
           remedy: ["Without it SpacePill cannot post the keystrokes that switch spaces,",
            "so Quick Switch and `spacepill switch` do nothing.",
            "Fix: System Settings > Privacy & Security > Accessibility > enable SpacePill."])

    report(permissions["inputMonitoring"] as? Bool == true,
           "Input Monitoring permission",
           remedy: ["Only affects responsiveness: without it the menu bar pill lags about",
            "half a second behind Ctrl+Arrow switches. Everything else still works.",
            "Fix: System Settings > Privacy & Security > Input Monitoring > enable SpacePill."])

    let shortcuts = status["shortcuts"] as? [String: Any] ?? [:]
    let enabled = shortcuts["enabledDesktops"] as? [Int] ?? []
    let maxDesktop = shortcuts["maxDesktop"] as? Int ?? 10

    if enabled.isEmpty {
        report(false, "\"Switch to Desktop N\" keyboard shortcuts: none enabled", remedy: [
            "This is the single most common reason SpacePill appears broken, and it",
            "is not SpacePill's doing: macOS ships these shortcuts turned OFF.",
            "",
            "macOS exposes no API for activating a space. The only way to move is to",
            "replay the shortcut you have bound, so with none bound there is nothing",
            "to replay -- `spacepill switch` and Quick Switch cannot work at all.",
            "",
            "Fix, once, and every desktop you tick becomes reachable:",
            "  1. System Settings > Keyboard > Keyboard Shortcuts...",
            "  2. Select \"Mission Control\" in the sidebar, expand \"Mission Control\".",
            "  3. Tick \"Switch to Desktop 1\", \"Switch to Desktop 2\", and so on.",
            "",
            "Only Desktops 1-\(maxDesktop) exist as shortcuts; anything past that is",
            "unreachable no matter what you do."
        ])
    } else {
        let list = enabled.map(String.init).joined(separator: ", ")
        let missing = (1...maxDesktop).filter { !enabled.contains($0) }
        var notes = [String]()
        if !missing.isEmpty {
            notes.append("Not enabled: \(missing.map(String.init).joined(separator: ", ")).")
            notes.append("Add them in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.")
        }
        report(true, "\"Switch to Desktop N\" shortcuts enabled for desktop \(list)", notes: notes)
    }

    let spaces = (try Client.send("list"))["spaces"] as? [[String: Any]] ?? []
    let reachable = spaces.filter { $0["isReachable"] as? Bool == true }.count
    let beyondMax = spaces.filter { ($0["index"] as? Int ?? 0) > maxDesktop }.count

    var spaceNotes = [String]()
    if reachable < spaces.count {
        spaceNotes.append("\(spaces.count - reachable) cannot be switched to from SpacePill.")
    }
    if beyondMax > 0 {
        spaceNotes.append("\(beyondMax) are past Desktop \(maxDesktop) and are unreachable by design.")
    }
    report(reachable > 0,
           "\(spaces.count) space\(spaces.count == 1 ? "" : "s"), \(reachable) reachable",
           remedy: ["Nothing can be switched to until a Desktop shortcut is enabled."],
           notes: spaceNotes)

    output("")
    output(healthy ? "All checks passed." : "Some checks failed; see the notes above.")

    if !healthy { throw CLIFailure("", .failure) }
}

func commandInstallCLI() throws {
    guard let source = Install.executableURL else {
        throw CLIFailure("Could not work out where this binary lives.")
    }

    let directory = "/usr/local/bin"
    let destination = "\(directory)/spacepill"
    let manager = FileManager.default

    if let existing = try? manager.destinationOfSymbolicLink(atPath: destination),
       URL(fileURLWithPath: existing).resolvingSymlinksInPath().path == source.path {
        output("Already installed: \(destination) -> \(source.path)")
        return
    }

    func manualInstructions(_ reason: String) -> CLIFailure {
        CLIFailure("""
        \(reason)

        Run this to install it with administrator rights:
          sudo mkdir -p \(directory)
          sudo ln -sf "\(source.path)" \(destination)
        """)
    }

    if !manager.fileExists(atPath: directory) {
        do {
            try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw manualInstructions("\(directory) does not exist and could not be created without administrator rights.")
        }
    }

    if manager.fileExists(atPath: destination) || (try? manager.destinationOfSymbolicLink(atPath: destination)) != nil {
        do {
            try manager.removeItem(atPath: destination)
        } catch {
            throw manualInstructions("Something is already at \(destination) and could not be replaced.")
        }
    }

    do {
        try manager.createSymbolicLink(atPath: destination, withDestinationPath: source.path)
    } catch {
        throw manualInstructions("Could not write to \(directory).")
    }

    output("Installed: \(destination) -> \(source.path)")
    if !(ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains(Substring(directory)) {
        output("")
        output("Note: \(directory) is not on your PATH. Add it to your shell profile:")
        output("  export PATH=\"\(directory):$PATH\"")
    }
}

func commandHelp() {
    output("""
    spacepill -- control SpacePill.app from the command line

    USAGE
      spacepill <command> [options]

    COMMANDS
      current [--json]                 Show the space you are on
      list [--json]                    List every space
      switch <index|label>             Jump to a space
      label <text> [--space N] [--color <hex>]
                                       Label the current (or given) space
      label --clear [--space N]        Remove a label and colour
      notes [--space N]                Print a space's notes
      notes --set [--space N]          Replace notes with stdin (or a quoted argument)
      notes --edit [--space N]         Edit notes in $EDITOR
      notes --path [--space N]         Print where the notes file lives
      doctor                           Check permissions and shortcuts
      update [--check]                 Update SpacePill (Homebrew, or a verified download)
      version                          Print the version
      install-cli                      Symlink this binary into /usr/local/bin
      help                             This message

    NOTES
      Omitting --space always means the space you are on right now.
      --json prints the raw response object, for scripting.
      Switching spaces replays your own "Switch to Desktop N" shortcut, which
      macOS ships disabled. Run `spacepill doctor` if a switch does nothing.

    EXIT CODES
      0 success   1 error   2 bad usage
      3 SpacePill.app is not running
      4 that space cannot be switched to
      5 no such space
    """)
}

// MARK: - Dispatch

let allowedFlags: [String: Set<String>] = [
    "current": ["--json"],
    "list": ["--json"],
    "switch": [],
    "label": ["--clear"],
    "notes": ["--set", "--edit", "--path"],
    "doctor": [],
    "update": ["--check"],
    "version": [],
    "install-cli": [],
    "help": []
]

func main() -> Int32 {
    // stdout is block-buffered when it is not a terminal, so piping `spacepill`
    // anywhere reorders it against the unbuffered progress on stderr.
    setvbuf(stdout, nil, _IOLBF, 0)

    var raw = Array(CommandLine.arguments.dropFirst())

    if raw.isEmpty || raw.first == "-h" || raw.first == "--help" || raw.first == "help" {
        commandHelp()
        return ExitCode.ok.rawValue
    }
    if raw.first == "-v" || raw.first == "--version" {
        raw[0] = "version"
    }

    let command = raw.removeFirst()

    do {
        let args = try Arguments(raw)

        guard let permitted = allowedFlags[command] else {
            throw CLIFailure("Unknown command \"\(command)\". Run `spacepill help`.", .usage)
        }
        if let flag = args.unknownFlags(allowed: permitted).first {
            throw CLIFailure("\(command) does not take \(flag). Run `spacepill help`.", .usage)
        }

        switch command {
        case "current":     try commandCurrent(args)
        case "list":        try commandList(args)
        case "switch":      try commandSwitch(args)
        case "label":       try commandLabel(args)
        case "notes":       try commandNotes(args)
        case "doctor":      try commandDoctor()
        case "update":      try Updater.run(checkOnly: args.has("--check"))
        case "version":     output(Install.resolveVersion())
        case "install-cli": try commandInstallCLI()
        default:            commandHelp()
        }
    } catch let failure as CLIFailure {
        if !failure.message.isEmpty { warn(failure.message) }
        return failure.exitCode.rawValue
    } catch {
        warn(error.localizedDescription)
        return ExitCode.failure.rawValue
    }

    return ExitCode.ok.rawValue
}

// MARK: - Small string helpers

extension String {
    func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    func trimmedTrailing() -> String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}

exit(main())
