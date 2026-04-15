cask "spacepill" do
  version "1.1.0"
  sha256 "bc33333172c502db46635c88503a56011411e62bdac7564f221f525e51c7de9a"

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
