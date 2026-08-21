cask "minibrowser" do
  version "1.3.0"
  sha256 "9ebada0a36ecfb13944b778c10af2a1ba44015ec297601ba518d08942f04d3ba"

  url "https://github.com/gum798/miniBrowser/releases/download/v#{version}/miniBrowser.zip"
  name "miniBrowser"
  desc "Mini web browser with an iPhone Safari-style interface"
  homepage "https://github.com/gum798/miniBrowser"

  depends_on macos: :tahoe

  app "miniBrowser.app"

  # The app is ad-hoc signed (not notarized), so drop the download quarantine
  # flag on install — otherwise Gatekeeper blocks the first launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/miniBrowser.app"]
  end

  zap trash: "~/Library/Application Support/miniBrowser"
end
