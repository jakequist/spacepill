cask "spacepill" do
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/jakequist/spacepill/releases/download/v#{version}/SpacePill.dmg"
  name "SpacePill"
  desc "Native macOS menu bar indicator for virtual desktops (Spaces)"
  homepage "https://github.com/jakequist/spacepill"

  app "SpacePill.app"

  uninstall quit: "com.jakequist.SpacePill"

  zap trash: [
    "~/Library/Application Support/SpacePill",
    "~/Library/Preferences/com.jake.SpacePill.plist",
  ]
end
