cask "spacepill" do
  version "1.1.1"
  sha256 "cccd7ff7245ed291e89b044c97c1c2866863d6b9510612619bd43b6ff659b6d0"

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
