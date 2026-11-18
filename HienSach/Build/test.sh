#!/bin/bash
set -euo pipefail
udid=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; a=json.load(sys.stdin)["devices"]; print(next(d["udid"] for rt in sorted(a,reverse=True) if ".iOS-" in rt for d in a[rt] if d["name"].startswith("iPhone") and d["isAvailable"]))')
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcodebuild -quiet -project HienSach.xcodeproj -scheme HienSach -configuration Debug -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$RUNNER_TEMP/reader-sim" -parallel-testing-enabled NO -resultBundlePath "$RUNNER_TEMP/reader-tests" test
xcrun simctl launch "$udid" io.github.hn6686553-create.hiensach
sleep 3
xcrun simctl io "$udid" screenshot out/Tu-sach.png
