#!/usr/bin/env bash
# Setup OpenWhoop iOS app (local-only mode; server optional later).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"
SECRETS="$IOS/OpenWhoop/Config/Secrets.xcconfig"
EXAMPLE="$IOS/OpenWhoop/Config/Secrets.example.xcconfig"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen..."
  brew install xcodegen
fi

if [[ ! -f "$SECRETS" ]]; then
  cp "$EXAMPLE" "$SECRETS"
  echo "Created $SECRETS (local-only placeholders; edit when you add a server)."
fi

cd "$IOS"
xcodegen generate
echo ""
echo "Done. Next steps:"
echo "  1. Install Xcode from the App Store (required for iPhone builds)."
echo "  2. open $IOS/OpenWhoop.xcodeproj"
echo "  3. Signing & Capabilities → select your Apple ID Team"
echo "  4. Run on a physical iPhone (iOS 16+), tab Device → connect strap"
echo ""
echo "Optional server: see server/README.md and edit Secrets.xcconfig with WHOOP_BASE_URL + WHOOP_API_KEY."
