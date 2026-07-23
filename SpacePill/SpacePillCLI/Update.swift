import Foundation

/**
 * `spacepill update`.
 *
 * Two worlds, and they are not equally safe:
 *
 *  - Installed by Homebrew: hand the whole job to `brew upgrade --cask`, which
 *    already checksums the download. This is the path we want people on.
 *  - Installed by dragging a DMG: SpacePill has to fetch and replace itself.
 *    An update mechanism that installs whatever a URL returns is a remote code
 *    execution primitive, so the downloaded app is verified with `codesign
 *    --verify --deep --strict` *and* required to carry a Developer ID authority
 *    before anything is copied anywhere. If either check fails the install is
 *    refused and the user is pointed at the releases page to decide for
 *    themselves. Unsigned releases therefore cannot be auto-installed at all --
 *    that is the intended outcome, not a bug.
 */
enum Updater {
    static let repository = "jakequist/spacepill"
    static var releasesURL: String { "https://github.com/\(repository)/releases/latest" }
    static var apiURL: String { "https://api.github.com/repos/\(repository)/releases/latest" }

    // MARK: - Entry point

    static func run(checkOnly: Bool) throws {
        let current = Install.resolveVersion()

        if let brew = brewPath(), isCaskInstalled(brew: brew) {
            try updateViaHomebrew(brew: brew, checkOnly: checkOnly, current: current)
            return
        }

        try updateViaGitHub(checkOnly: checkOnly, current: current)
    }

    // MARK: - Homebrew

    private static func brewPath() -> String? {
        firstExisting(["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"])
    }

    private static func isCaskInstalled(brew: String) -> Bool {
        runTool(brew, ["list", "--cask", "spacepill"]).succeeded
    }

    private static func updateViaHomebrew(brew: String, checkOnly: Bool, current: String) throws {
        output("Installed via Homebrew (current version \(current)).")

        if checkOnly {
            let outdated = runTool(brew, ["outdated", "--cask", "spacepill", "--verbose"])
            let report = outdated.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)

            // brew exits non-zero for reasons that have nothing to do with the
            // version -- an untrusted tap, no network, a broken formula. Empty
            // stdout then means "brew could not tell us", not "up to date", and
            // reporting the latter would be a lie that hides a real update.
            guard outdated.succeeded else {
                warn(outdated.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                output("")
                output("Homebrew could not check for updates. Asking GitHub directly instead.")
                output("")
                try updateViaGitHub(checkOnly: true, current: current)
                return
            }

            if report.isEmpty {
                output("SpacePill is up to date.")
            } else {
                output(report)
                output("")
                output("Run `spacepill update` to install it.")
            }
            return
        }

        output("Running: brew upgrade --cask spacepill")
        output("")
        // exec rather than spawn: brew is interactive (it may ask for an admin
        // password) and owns the terminal from here on.
        execute(brew, ["upgrade", "--cask", "spacepill"])
    }

    // MARK: - Direct download

    private static func updateViaGitHub(checkOnly: Bool, current: String) throws {
        output("Current version: \(current)")
        output("Checking \(repository) for a newer release...")

        let release = try fetchLatestRelease()
        output("Latest release:  \(release.version)")

        switch compareVersions(current, release.version) {
        case .some(.orderedSame), .some(.orderedDescending):
            output("")
            output("SpacePill is up to date.")
            return
        case .none:
            output("")
            warn("Could not compare those version numbers; treating the release as newer.")
        case .some(.orderedAscending):
            break
        }

        output("")
        output("An update is available: \(current) -> \(release.version)")

        if checkOnly {
            output("Run `spacepill update` to install it, or download it from:")
            output("  \(release.pageURL)")
            return
        }

        guard let asset = release.diskImageURL else {
            throw CLIFailure("That release has no SpacePill.dmg asset. Download it manually from \(release.pageURL)")
        }

        try installDiskImage(from: asset, version: release.version, pageURL: release.pageURL)
    }

    private struct Release {
        let version: String
        let pageURL: String
        let diskImageURL: URL?
    }

    private static func fetchLatestRelease() throws -> Release {
        guard let url = URL(string: apiURL) else {
            throw CLIFailure("Bad release API URL.")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("spacepill-cli", forHTTPHeaderField: "User-Agent")

        var payload: Data?
        var failure: Error?
        var statusCode = 0

        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            payload = data
            failure = error
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let failure = failure {
            throw CLIFailure("Could not reach GitHub: \(failure.localizedDescription)")
        }
        guard statusCode == 200, let payload = payload else {
            throw CLIFailure("GitHub returned HTTP \(statusCode) for the latest release. Try \(releasesURL)")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw CLIFailure("Could not read GitHub's release response. Try \(releasesURL)")
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let dmgURL = (dmg?["browser_download_url"] as? String).flatMap { URL(string: $0) }

        return Release(
            version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            pageURL: json["html_url"] as? String ?? releasesURL,
            diskImageURL: dmgURL
        )
    }

    private static func installDiskImage(from url: URL, version: String, pageURL: String) throws {
        guard url.scheme == "https" else {
            throw CLIFailure("Refusing to download over \(url.scheme ?? "an unknown scheme"); only HTTPS is allowed.")
        }

        output("Downloading \(url.lastPathComponent)...")
        let download = try downloadToTemporary(url)
        defer { try? FileManager.default.removeItem(at: download.deletingLastPathComponent()) }

        output("Mounting...")
        guard let mountPoint = attach(download) else {
            throw CLIFailure("Could not mount the downloaded disk image.")
        }
        defer { runTool("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }

        let app = URL(fileURLWithPath: mountPoint).appendingPathComponent("SpacePill.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw CLIFailure("The disk image does not contain SpacePill.app.")
        }

        output("Verifying the signature...")
        let verify = runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard verify.succeeded else {
            throw refusal("its code signature did not verify", detail: verify.standardError, pageURL: pageURL)
        }

        let details = runTool("/usr/bin/codesign", ["-dvvv", app.path])
        let authorities = (details.standardOutput + details.standardError)
            .split(separator: "\n")
            .filter { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }

        guard authorities.contains(where: { $0.hasPrefix("Developer ID Application:") }) else {
            let found = authorities.isEmpty ? "none (the app is unsigned or ad-hoc signed)" : authorities.joined(separator: ", ")
            throw refusal("it is not signed with a Developer ID certificate",
                          detail: "Signing authority: \(found)",
                          pageURL: pageURL)
        }

        output("Signature OK: \(authorities.first ?? "")")
        output("Installing to /Applications...")

        // Copy first, swap second. Deleting the installed app before the new one
        // is safely on disk turns a full /Applications or a missing admin right
        // into "SpacePill is gone", which is a much worse failure than "the
        // update did not happen".
        let destination = "/Applications/SpacePill.app"
        let staged = "/Applications/SpacePill.app.spacepill-update"
        try? FileManager.default.removeItem(atPath: staged)

        let copy = runTool("/usr/bin/ditto", [app.path, staged])
        guard copy.succeeded else {
            try? FileManager.default.removeItem(atPath: staged)
            throw CLIFailure("Could not write to /Applications: \(copy.standardError.trimmingCharacters(in: .whitespacesAndNewlines))\nNothing was changed. Install it by hand from \(pageURL)")
        }

        runTool("/usr/bin/pkill", ["-x", "SpacePill"])

        let previous = "/Applications/SpacePill.app.spacepill-previous"
        try? FileManager.default.removeItem(atPath: previous)
        let hadPrevious = FileManager.default.fileExists(atPath: destination)
        if hadPrevious {
            do {
                try FileManager.default.moveItem(atPath: destination, toPath: previous)
            } catch {
                try? FileManager.default.removeItem(atPath: staged)
                throw CLIFailure("Could not replace \(destination): \(error.localizedDescription)\nNothing was changed. Install it by hand from \(pageURL)")
            }
        }

        do {
            try FileManager.default.moveItem(atPath: staged, toPath: destination)
        } catch {
            // Put the old one back rather than leaving the user with nothing.
            if hadPrevious { try? FileManager.default.moveItem(atPath: previous, toPath: destination) }
            throw CLIFailure("Could not move the new build into place: \(error.localizedDescription)\nThe previous version was restored. Install it by hand from \(pageURL)")
        }

        try? FileManager.default.removeItem(atPath: previous)
        runTool("/usr/bin/open", [destination])
        output("Updated to \(version).")
    }

    private static func refusal(_ reason: String, detail: String, pageURL: String) -> CLIFailure {
        var message = "Refusing to install this build: \(reason)."
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            message += "\n\n\(trimmed)"
        }
        message += """


        SpacePill will not install a binary it cannot verify. Nothing was changed.
        Review the release and install it yourself if you trust it:
          \(pageURL)
        """
        return CLIFailure(message)
    }

    private static func downloadToTemporary(_ url: URL) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spacepill-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)

        var failure: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.downloadTask(with: URLRequest(url: url, timeoutInterval: 300)) { temporary, response, error in
            defer { semaphore.signal() }
            if let error = error { failure = error; return }
            guard let temporary = temporary,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                failure = CLIFailure("The download did not complete.")
                return
            }
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                failure = error
            }
        }.resume()
        semaphore.wait()

        if let failure = failure {
            throw CLIFailure("Download failed: \(failure.localizedDescription)")
        }
        return destination
    }

    /// Mounts a disk image and returns its mount point.
    private static func attach(_ image: URL) -> String? {
        let result = runTool("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noverify", "-plist"])
        guard result.succeeded,
              let data = result.standardOutput.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }
}

/// Replaces this process. Only returns if the exec itself fails.
func execute(_ path: String, _ arguments: [String]) -> Never {
    var argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) }
    argv.append(nil)
    execv(path, &argv)

    warn("Could not run \(path): \(String(cString: strerror(errno)))")
    exit(ExitCode.failure.rawValue)
}
