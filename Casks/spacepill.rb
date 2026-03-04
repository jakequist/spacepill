cask "spacepill" do
  version "1.0.4"
  sha256 "4720c883c7b4ac617a20bcb229c2c5b69b8b459e8522364e3fe576bd63b467c0"

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
