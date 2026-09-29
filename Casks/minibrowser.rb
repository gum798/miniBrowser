cask "minibrowser" do
  version "1.4.1"
  sha256 "7ec1cd4ed3e1e54636071424a35316c3052e87cc957723750742b0347afdad1a"

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
