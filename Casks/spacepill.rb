cask "spacepill" do
  version "1.1.2"
  sha256 "97772898209958485053792c62723cbd3a333859bc4f455bdfb13b9c4562bde8"

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
