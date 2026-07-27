cask "spacepill" do
  version "1.2.0"
  sha256 "e65cd032af75aaada0a54da7aadcd770d104b8f78ed4e90f66cfe329ec33269c"

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
