import Foundation
import AppKit
import ApplicationServices
import IOKit.hid

/**
 * A local control channel for the `spacepill` command-line client.
 *
 * The CLI deliberately owns no state and talks to no private API. Switching a
 * Space means posting keystrokes, which needs Accessibility, and TCC keys that
 * grant to the *binary that posts them* -- a standalone CLI would therefore need
 * its own grant and would trigger a second, scarier-looking prompt. Routing
 * every request through the already-trusted app avoids that entirely, and keeps
 * a single source of truth for labels, colours and notes.
 *
 * Transport is a Unix domain socket at `~/.spacepill/spacepill.sock`, chmod 0600
 * so only the owning user can talk to it. One line of UTF-8 JSON per request,
 * one line back, then the server closes:
 *
 *     -> {"protocol":1,"command":"list","args":{}}
 *     <- {"ok":true,"data":{"spaces":[...]}}
 *     <- {"ok":false,"code":"not_found","error":"No space matching \"9\""}
 *
 * Threading: `accept` and all socket I/O happen off the main queue, but every
 * command handler runs inside a single `DispatchQueue.main.sync` hop, because
 * SkyLight, AppKit and the `@Published` manager state are all main-queue-only.
 */
final class CLIServer {
    /// Wire protocol version. Bump only for incompatible changes; the client
    /// sends it on every request and the server refuses anything it doesn't know.
    static let protocolVersion = 1

    static let socketURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".spacepill/spacepill.sock")
    }()

    private let settingsManager: SettingsManager
    private let spaceManager: SpaceManager
    private let notesManager: NotesManager

    private let acceptQueue = DispatchQueue(label: "com.jake.SpacePill.cli.accept")
    private let connectionQueue = DispatchQueue(label: "com.jake.SpacePill.cli.conn", attributes: .concurrent)

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var isRunning = false

    /// Requests larger than this are dropped rather than buffered. Notes are the
    /// only unbounded payload and 4 MB is far past anything a human will type.
    private static let maxRequestBytes = 4 * 1024 * 1024

    init(settingsManager: SettingsManager, spaceManager: SpaceManager, notesManager: NotesManager) {
        self.settingsManager = settingsManager
        self.spaceManager = spaceManager
        self.notesManager = notesManager
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /**
     * Binds and starts listening. Any socket left behind by a crash is unlinked
     * first -- `bind` fails with EADDRINUSE on a stale inode even though nothing
     * is listening on it.
     */
    func start() {
        guard !isRunning else { return }

        let path = CLIServer.socketURL.path
        let directory = CLIServer.socketURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            Log.app.error("CLI socket path is too long for sockaddr_un; CLI disabled")
            return
        }

        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.app.error("CLI socket() failed: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            guard let base = raw.baseAddress else { return }
            let bytes = Array(path.utf8)
            base.copyMemory(from: bytes, byteCount: bytes.count)
            base.storeBytes(of: 0, toByteOffset: bytes.count, as: UInt8.self)
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            Log.app.error("CLI bind() failed: \(String(cString: strerror(errno)), privacy: .public)")
            close(fd)
            return
        }

        // Owner-only: anything on this socket can relabel spaces and read notes.
        chmod(path, 0o600)

        guard listen(fd, 16) == 0 else {
            Log.app.error("CLI listen() failed: \(String(cString: strerror(errno)), privacy: .public)")
            close(fd)
            unlink(path)
            return
        }

        // Non-blocking so the dispatch source drains the backlog and returns
        // instead of parking a queue thread inside accept().
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        listenFD = fd
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPending()
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.listenFD)
            self.listenFD = -1
        }
        source.resume()
        acceptSource = source

        Log.app.info("CLI socket listening at \(path, privacy: .public)")
    }

    /**
     * Stops listening and removes the socket file. Idempotent, and safe to call
     * from a signal handler's main-queue block.
     */
    func stop() {
        guard isRunning else { return }
        isRunning = false

        acceptSource?.cancel()
        acceptSource = nil
        unlink(CLIServer.socketURL.path)
        Log.app.info("CLI socket closed")
    }

    // MARK: - Accept / read loop

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }

            // BSD-derived kernels hand the accepted socket the listener's file
            // status flags, so it arrives non-blocking and the first read()
            // returns EAGAIN whenever the request has not landed yet -- an
            // intermittent "empty request" that looks like a client bug.
            // Clear it and let SO_RCVTIMEO bound the wait instead.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) & ~O_NONBLOCK)

            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            connectionQueue.async { [weak self] in
                self?.serve(client: client)
            }
        }
    }

    private func serve(client: Int32) {
        defer { close(client) }

        guard let line = readLine(from: client) else {
            respond(client, failure: "bad_request", "Request was empty, oversized, or not valid UTF-8.")
            return
        }

        guard let data = line.data(using: .utf8),
              let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            respond(client, failure: "bad_request", "Request was not a JSON object.")
            return
        }

        let version = (request["protocol"] as? NSNumber)?.intValue ?? 0
        guard version == CLIServer.protocolVersion else {
            respond(client, failure: "unsupported_protocol",
                    "This SpacePill speaks protocol \(CLIServer.protocolVersion), the client asked for \(version). Update whichever is older.")
            return
        }

        guard let command = request["command"] as? String else {
            respond(client, failure: "bad_request", "Request is missing \"command\".")
            return
        }
        let args = request["args"] as? [String: Any] ?? [:]

        Log.app.debug("CLI command \(command, privacy: .public)")

        // Every handler touches SkyLight or @Published state, so all of them run
        // on the main queue. Handlers are short; nothing here does I/O that could
        // stall the UI beyond a settings write.
        let result: Result<[String: Any], CommandError> = DispatchQueue.main.sync {
            do {
                return .success(try self.handle(command: command, args: args))
            } catch let error as CommandError {
                return .failure(error)
            } catch {
                return .failure(CommandError("internal_error", error.localizedDescription))
            }
        }

        switch result {
        case .success(let payload):
            respond(client, success: payload)
        case .failure(let error):
            respond(client, failure: error.code, error.message)
        }
    }

    private func readLine(from fd: Int32) -> String? {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            accumulated.append(contentsOf: buffer[0..<count])

            if let newline = accumulated.firstIndex(of: 0x0A) {
                return String(data: accumulated[..<newline], encoding: .utf8)
            }
            if accumulated.count > CLIServer.maxRequestBytes { return nil }
        }

        // Tolerate a client that closed its write end without a trailing newline.
        return accumulated.isEmpty ? nil : String(data: accumulated, encoding: .utf8)
    }

    private func respond(_ fd: Int32, success data: [String: Any]) {
        write(fd, payload: ["ok": true, "data": data])
    }

    private func respond(_ fd: Int32, failure code: String, _ message: String) {
        Log.app.notice("CLI error \(code, privacy: .public): \(message, privacy: .public)")
        write(fd, payload: ["ok": false, "code": code, "error": message])
    }

    private func write(_ fd: Int32, payload: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        data.append(0x0A)

        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Foundation.write(fd, pointer, remaining)
                if written <= 0 { return }
                pointer += written
                remaining -= written
            }
        }
    }

    // MARK: - Commands

    private struct CommandError: Error {
        let code: String
        let message: String
        init(_ code: String, _ message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Runs on the main queue.
    private func handle(command: String, args: [String: Any]) throws -> [String: Any] {
        switch command {
        case "status":      return status()
        case "list":        return listSpaces()
        case "switch":      return try switchSpace(args: args)
        case "set-label":   return try setLabel(args: args)
        case "clear-label": return try clearLabel(args: args)
        case "notes-get":   return try notesGet(args: args)
        case "notes-set":   return try notesSet(args: args)
        case "notes-path":  return try notesPath(args: args)
        default:
            throw CommandError("unknown_command", "SpacePill does not know the command \"\(command)\".")
        }
    }

    private func status() -> [String: Any] {
        SpaceShortcuts.refresh()

        var payload: [String: Any] = [
            "version": CLIServer.appVersion,
            "spaceCount": SkyLight.getAllSpacesMetadata().count,
            "permissions": [
                "accessibility": AXIsProcessTrusted(),
                "inputMonitoring": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            ],
            "shortcuts": [
                "enabledDesktops": SpaceShortcuts.reachableDesktops().sorted(),
                "maxDesktop": SpaceShortcuts.maxDesktop
            ]
        ]

        if let current = SkyLight.getActiveSpaceMetadata() {
            payload["currentSpace"] = describe(current, isCurrent: true, reachable: nil)
        }

        return payload
    }

    private func listSpaces() -> [String: Any] {
        SpaceShortcuts.refresh()

        let currentUUID = SkyLight.getActiveSpaceMetadata()?.uuid
        let reachable = SpaceShortcuts.reachableDesktops()

        let spaces = SkyLight.getAllSpacesMetadata().map { metadata in
            describe(metadata,
                     isCurrent: metadata.uuid == currentUUID,
                     reachable: reachable.contains(metadata.index))
        }

        return ["spaces": spaces]
    }

    private func switchSpace(args: [String: Any]) throws -> [String: Any] {
        guard let target = (args["target"] as? String)?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            throw CommandError("bad_request", "switch needs a target: an index, a label, or a UUID.")
        }

        SpaceShortcuts.refresh()
        let metadata = SkyLight.getAllSpacesMetadata()

        guard let space = resolve(target: target, in: metadata) else {
            throw CommandError("not_found", "No space matching \"\(target)\".")
        }

        // EXPERIMENTAL branch: the direct SkyLight method reaches any Space, so
        // the old "past Desktop 10 / shortcut not enabled" gates are gone -- the
        // only requirement is that the Space exists (canSwitchToSpace).
        guard SkyLight.canSwitchToSpace(index: space.index) else {
            throw CommandError("not_found", "Space \(space.index) does not exist.")
        }

        guard SkyLight.switchToSpace(index: space.index) else {
            throw CommandError("switch_failed", "SpacePill could not switch to space \(space.index).")
        }

        return ["switchedTo": [
            "index": space.index,
            "uuid": space.uuid,
            "label": settingsManager.spaceConfigs[space.uuid]?.label as Any
        ].compactMapValues { $0 is NSNull ? nil : $0 }]
    }

    private func setLabel(args: [String: Any]) throws -> [String: Any] {
        let space = try resolveSpace(args: args)
        var config = settingsManager.spaceConfigs[space.uuid] ?? SpaceConfig()

        if let label = args["label"] as? String {
            config.label = label.isEmpty ? nil : label
        }
        if let hex = args["hexColor"] as? String {
            guard let normalized = CLIServer.normalizeHex(hex) else {
                throw CommandError("bad_request", "\"\(hex)\" is not a hex colour. Use RGB, RRGGBB, or AARRGGBB.")
            }
            config.hexColor = normalized
        }

        settingsManager.spaceConfigs[space.uuid] = config
        Log.settings.info("CLI set config for space \(space.index, privacy: .public)")

        return describe(space, isCurrent: nil, reachable: nil)
    }

    private func clearLabel(args: [String: Any]) throws -> [String: Any] {
        let space = try resolveSpace(args: args)
        settingsManager.clearConfig(for: space.uuid)
        Log.settings.info("CLI cleared config for space \(space.index, privacy: .public)")
        return describe(space, isCurrent: nil, reachable: nil)
    }

    private func notesGet(args: [String: Any]) throws -> [String: Any] {
        let space = try resolveSpace(args: args)
        return ["index": space.index, "text": notesManager.notes(forSpace: space.index)]
    }

    private func notesSet(args: [String: Any]) throws -> [String: Any] {
        guard let text = args["text"] as? String else {
            throw CommandError("bad_request", "notes-set needs \"text\".")
        }
        let space = try resolveSpace(args: args)
        notesManager.setNotes(text, forSpace: space.index)
        Log.notes.info("CLI wrote notes for space \(space.index, privacy: .public)")
        return ["index": space.index, "bytes": text.utf8.count]
    }

    private func notesPath(args: [String: Any]) throws -> [String: Any] {
        let space = try resolveSpace(args: args)
        return ["index": space.index, "path": notesManager.notesURL(forSpace: space.index).path]
    }

    // MARK: - Helpers

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func describe(_ metadata: SpaceMetadata, isCurrent: Bool?, reachable: Bool?) -> [String: Any] {
        let config = settingsManager.spaceConfigs[metadata.uuid]
        var entry: [String: Any] = [
            "index": metadata.index,
            "uuid": metadata.uuid
        ]
        if let label = config?.label, !label.isEmpty { entry["label"] = label }
        if let hex = config?.hexColor { entry["hexColor"] = hex }
        if let isCurrent = isCurrent { entry["isCurrent"] = isCurrent }
        if let reachable = reachable { entry["isReachable"] = reachable }
        return entry
    }

    /// Resolves the `index` / `uuid` args. Omitting both means the current space.
    private func resolveSpace(args: [String: Any]) throws -> SpaceMetadata {
        let metadata = SkyLight.getAllSpacesMetadata()

        if let uuid = args["uuid"] as? String {
            guard let match = metadata.first(where: { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }) else {
                throw CommandError("not_found", "No space with UUID \(uuid).")
            }
            return match
        }

        if let index = (args["index"] as? NSNumber)?.intValue {
            guard let match = metadata.first(where: { $0.index == index }) else {
                throw CommandError("not_found", "There is no space \(index); this Mac has \(metadata.count).")
            }
            return match
        }

        guard let current = SkyLight.getActiveSpaceMetadata() else {
            throw CommandError("no_current_space", "SpacePill could not determine the current space.")
        }
        return current
    }

    /**
     * Matches a free-form switch target against the spaces, in decreasing order
     * of how sure we can be: an integer is an index, 36 characters is a UUID,
     * anything else is a label (exact first, then a unique case-insensitive
     * prefix, so `spacepill switch wo` finds "Work").
     */
    private func resolve(target: String, in metadata: [SpaceMetadata]) -> SpaceMetadata? {
        if let index = Int(target) {
            return metadata.first { $0.index == index }
        }

        if let match = metadata.first(where: { $0.uuid.caseInsensitiveCompare(target) == .orderedSame }) {
            return match
        }

        let labelled = metadata.compactMap { space -> (SpaceMetadata, String)? in
            guard let label = settingsManager.spaceConfigs[space.uuid]?.label, !label.isEmpty else { return nil }
            return (space, label)
        }

        if let exact = labelled.first(where: { $0.1.caseInsensitiveCompare(target) == .orderedSame }) {
            return exact.0
        }

        let prefixed = labelled.filter { $0.1.lowercased().hasPrefix(target.lowercased()) }
        return prefixed.count == 1 ? prefixed[0].0 : nil
    }

    /**
     * Accepts `#RGB`, `RRGGBB`, `#AARRGGBB` and friends, and normalises to the
     * 8-digit AARRGGBB form that `Color.toHex()` writes, so a label set from the
     * CLI is byte-identical to one set from Quick Edit.
     */
    static func normalizeHex(_ raw: String) -> String? {
        let hex = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        switch hex.count {
        case 3:
            return "FF" + hex.map { String(repeating: String($0), count: 2) }.joined()
        case 6:
            return "FF" + hex
        case 8:
            return hex
        default:
            return nil
        }
    }
}
