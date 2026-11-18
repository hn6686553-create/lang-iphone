#!/bin/bash
set -euo pipefail
udid=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; a=json.load(sys.stdin)["devices"]; print(next(d["udid"] for rt in sorted(a,reverse=True) if ".iOS-" in rt for d in a[rt] if d["name"].startswith("iPhone") and d["isAvailable"]))')
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
status=0
xcodebuild -project HienSach.xcodeproj -scheme HienSach -configuration Debug -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$RUNNER_TEMP/reader-sim" -parallel-testing-enabled NO -resultBundlePath "$RUNNER_TEMP/reader-tests.xcresult" test > "$RUNNER_TEMP/hien-sach-tests.log" 2>&1 || status=$?
grep -E "error:|warning:|Test (Case|Suite)|Executed [0-9]+ tests|failed|succeeded" "$RUNNER_TEMP/hien-sach-tests.log" | tail -100 || true
if [[ -d "$RUNNER_TEMP/reader-tests.xcresult" ]]; then
  xcrun xcresulttool get test-results summary --path "$RUNNER_TEMP/reader-tests.xcresult" || true
fi
xcrun simctl launch "$udid" io.github.hn6686553-create.hiensach || true
sleep 4
xcrun simctl io "$udid" screenshot out/Tu-sach.png || true
exit "$status"
