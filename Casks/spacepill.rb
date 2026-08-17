cask "spacepill" do
  version "1.3.1"
  sha256 "8414ab6f1f787828df7699b1b42871aa9575d100d54863306e05042875743816"

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
