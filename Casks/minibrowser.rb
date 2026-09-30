cask "minibrowser" do
  version "1.4.3"
  sha256 "5489e06aca3ccd152954ae9bd5a10b02a227b6c5eb890e2e0a92e9d6dd73f5a0"

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
