#!/bin/bash
# Builds ProDisplay.app into ./build using SwiftPM (no Xcode required).
# Usage: ./build.sh            build only
#        ./build.sh install    build, then replace /Applications/ProDisplay.app and relaunch
#        ./build.sh release    build, then create build/ProDisplay-<version>.zip and build/appcast.xml
#                              (Sparkle update feed) to attach to a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

SPARKLE_VERSION=2.10.0 # keep in sync with Package.swift
REPO_URL=https://github.com/xanderlzy/prodisplay

swift build -c release

# Assemble and sign outside this folder: iCloud Drive adds Finder attributes
# to bundles in Documents, which codesign rejects.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ProDisplay.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/ProDisplay "$APP/Contents/MacOS/ProDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
    "$APP/Contents/Frameworks/Sparkle.framework"
xattr -cr "$APP"

# Sign with the local self-signed certificate when present, so macOS permissions
# (Accessibility) survive rebuilds; otherwise fall back to ad-hoc signing.
IDENTITY="ProDisplay Local Signing"
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "warning: '$IDENTITY' certificate not found; signing ad-hoc"
    IDENTITY="-"
fi
# Sparkle's helpers are signed inside-out, as Sparkle's documentation describes.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "$SPARKLE/Autoupdate"
codesign --force --sign "$IDENTITY" "$SPARKLE/Updater.app"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP"

mkdir -p build
rm -rf build/ProDisplay.app
ditto "$APP" build/ProDisplay.app
echo "Built build/ProDisplay.app"

if [[ "${1:-}" == "release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
    ZIP="build/ProDisplay-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Created $ZIP"

    # Sparkle's sign_update tool, cached in .build. It signs with the EdDSA key
    # stored in the login keychain under the account "ProDisplay".
    TOOLS=".build/sparkle-tools-$SPARKLE_VERSION"
    if [[ ! -x "$TOOLS/bin/sign_update" ]]; then
        mkdir -p "$TOOLS"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJ -C "$TOOLS"
    fi
    SIGNATURE=$("$TOOLS/bin/sign_update" --account ProDisplay "$ZIP")

    cat > build/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ProDisplay</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$REPO_URL/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$REPO_URL/releases/download/v$VERSION/ProDisplay-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST
    echo "Created build/appcast.xml"
    echo "Publish with: gh release create v$VERSION $ZIP build/appcast.xml"
fi

if [[ "${1:-}" == "install" ]]; then
    pkill -x ProDisplay && sleep 1 || true
    rm -rf /Applications/ProDisplay.app
    ditto "$APP" /Applications/ProDisplay.app
    open /Applications/ProDisplay.app
    echo "Installed /Applications/ProDisplay.app"
fi
