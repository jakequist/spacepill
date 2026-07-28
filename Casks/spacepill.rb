cask "spacepill" do
  version "1.2.1"
  sha256 "c6cd86732e3d3d013f73c409336be28af9db164ae6d7c0913ac6034f34e3eabd"

  url "https://github.com/jakequist/spacepill/releases/download/v#{version}/SpacePill.dmg"
  name "SpacePill"
  desc "Native macOS menu bar indicator for virtual desktops (Spaces)"
  homepage "https://github.com/jakequist/spacepill"

  depends_on macos: ">= :ventura"

  app "SpacePill.app"
  # The CLI ships inside the bundle and talks to the running app over a Unix
  # socket, so it needs no permissions of its own.
  binary "#{appdir}/SpacePill.app/Contents/Helpers/spacepill"

  # Must match CFBundleIdentifier in SpacePill/SpacePill/Resources/Info.plist.
  uninstall quit: "com.jake.SpacePill"

  # SpacePill keeps settings and per-space notes in ~/.spacepill; the
  # Preferences plist only lingers for users who predate that migration.
  zap trash: [
    "~/.spacepill",
    "~/Library/Preferences/com.jake.SpacePill.plist",
  ]
end
