cask "minibrowser" do
  version "1.4.2"
  sha256 "7c1b3945590f8f1a07562734d48d5f8e1a086576931a27b8ec97b7a2efa5783c"

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
