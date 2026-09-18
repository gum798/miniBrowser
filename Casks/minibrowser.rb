cask "minibrowser" do
  version "1.4.0"
  sha256 "d24efbd256b2635661948a621d766ee136bbcd87fd1129f5e610c64d96f95723"

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
