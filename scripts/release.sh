#!/usr/bin/env bash
# Build a release .app, zip it, refresh the Homebrew cask (version + sha256),
# and optionally publish a GitHub release so `brew install --cask` works.
#
# Usage:
#   ./scripts/release.sh [version]            # build dist/miniBrowser.zip + update cask
#   ./scripts/release.sh [version] --publish  # …and create/upload the GitHub release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:-1.0.0}"
[[ "$VERSION" == --* ]] && { echo "usage: release.sh [version] [--publish]"; exit 1; }

echo "› Building release app…"
./scripts/build-app.sh --no-install >/dev/null
APP="$ROOT/dist/miniBrowser.app"
ZIP="$ROOT/dist/miniBrowser.zip"

echo "› Zipping…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

CASK="$ROOT/Casks/minibrowser.rb"
/usr/bin/sed -i '' -E \
  "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

echo "✓ $ZIP"
echo "  version $VERSION"
echo "  sha256  $SHA"
echo "✓ updated $CASK"

if [[ "${2:-}" == "--publish" ]]; then
  echo "› Publishing GitHub release v${VERSION}"
  gh release create "v$VERSION" "$ZIP" \
    --title "miniBrowser $VERSION" \
    --notes "Install: \`brew install --cask https://raw.githubusercontent.com/gum798/miniBrowser/main/Casks/minibrowser.rb\`"
  echo "✓ released — remember to commit the updated cask"
fi
