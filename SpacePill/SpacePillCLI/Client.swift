import Foundation

/**
 * Exit codes, so scripts can branch without parsing English.
 *
 *   0 ok
 *   1 something went wrong
 *   2 the command line was malformed
 *   3 SpacePill.app is not running
 *   4 the space exists but cannot be switched to
 *   5 no such space
 */
enum ExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 2
    case notRunning = 3
    case unreachable = 4
    case notFound = 5
}

/// A failure worth printing and exiting on. `code` is the server's slug when the
/// error came from the app, or a local slug when it did not.
struct CLIFailure: Error {
    let message: String
    let exitCode: ExitCode

    init(_ message: String, _ exitCode: ExitCode = .failure) {
        self.message = message
        self.exitCode = exitCode
    }
}

/**
 * The client half of the SpacePill control socket.
 *
 * This process deliberately knows nothing about Spaces. It cannot -- switching
 * a Space means posting keystrokes, which needs Accessibility, and TCC grants
 * are per-binary. Asking the running app to do it keeps the whole feature on the
 * single grant the user already gave SpacePill.app.
 */
enum Client {
    static let protocolVersion = 1

    static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spacepill/spacepill.sock").path
    }

    static let notRunningMessage =
        "SpacePill isn't running. Launch SpacePill.app and try again."

    /**
     * Sends one request and returns the `data` object from the reply.
     *
     * - Throws: `CLIFailure` with exit code 3 when nothing is listening, or the
     *   server's own error mapped onto an exit code.
     */
    static func send(_ command: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        let fd = try connect()
        defer { close(fd) }

        var request: [String: Any] = ["protocol": protocolVersion, "command": command]
        request["args"] = args

        guard var payload = try? JSONSerialization.data(withJSONObject: request) else {
            throw CLIFailure("Could not encode the request.")
        }
        payload.append(0x0A)

        try writeAll(fd, payload)

        guard let line = readLine(fd),
              let data = line.data(using: .utf8),
              let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CLIFailure("SpacePill sent a reply this version cannot read.")
        }

        if response["ok"] as? Bool == true {
            return response["data"] as? [String: Any] ?? [:]
        }

        let code = response["code"] as? String ?? "error"
        let message = response["error"] as? String ?? "SpacePill reported an unspecified error."
        throw CLIFailure(message, exitCode(for: code))
    }

    private static func exitCode(for code: String) -> ExitCode {
        switch code {
        case "not_found":                       return .notFound
        case "unreachable", "no_shortcut":      return .unreachable
        case "bad_request":                     return .usage
        default:                                return .failure
        }
    }

    // MARK: - Socket plumbing

    private static func connect() throws -> Int32 {
        let path = socketPath
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw CLIFailure("The socket path is too long: \(path)")
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIFailure("Could not create a socket: \(String(cString: strerror(errno)))")
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

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connected == 0 else {
            let failure = errno
            close(fd)
            // ENOENT: never started or shut down cleanly. ECONNREFUSED: a stale
            // socket file left by a crash. Both mean the same thing to the user.
            if failure == ENOENT || failure == ECONNREFUSED {
                throw CLIFailure(notRunningMessage, .notRunning)
            }
            throw CLIFailure("Could not reach SpacePill: \(String(cString: strerror(failure)))", .notRunning)
        }

        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        return fd
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        var failed = false
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written <= 0 { failed = true; return }
                pointer += written
                remaining -= written
            }
        }
        if failed {
            throw CLIFailure("SpacePill closed the connection while the request was being sent.", .notRunning)
        }
    }

    private static func readLine(_ fd: Int32) -> String? {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            accumulated.append(contentsOf: buffer[0..<count])
            if let newline = accumulated.firstIndex(of: 0x0A) {
                return String(data: accumulated[..<newline], encoding: .utf8)
            }
        }

        return accumulated.isEmpty ? nil : String(data: accumulated, encoding: .utf8)
    }
}
