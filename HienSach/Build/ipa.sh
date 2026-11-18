#!/bin/bash
set -euo pipefail
mkdir -p out
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcodebuild -quiet -project HienSach.xcodeproj -scheme HienSach -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$work/build" CODE_SIGNING_ALLOWED=NO build
mkdir "$work/Payload"
ditto "$work/build/Build/Products/Release-iphoneos/HienSach.app" "$work/Payload/HienSach.app"
app="$work/Payload/HienSach.app"
xcrun lipo "$app/HienSach" -verify_arch arm64
if [[ -d "$app/Frameworks" ]]; then
  find "$app/Frameworks" -type d -name '*.framework' -exec codesign --force --sign - --timestamp=none {} \;
fi
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
out="$PWD/out/HienSach.ipa"
(cd "$work" && /usr/bin/zip -qry "$out" Payload)
unzip -tq "$out"
shasum -a 256 "$out"
