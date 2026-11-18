#!/usr/bin/env python3
"""Build Lặng for iPhone using Xcode. The owner signs the exported IPA on device."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


def read_plist(path):
    with path.open("rb") as file:
        return plistlib.load(file)


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def validate_ids(base, group):
    identifier = r"[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+"
    if not re.fullmatch(identifier, base):
        raise ValueError("Nhập Bundle ID cụ thể đã đăng ký trên Apple Developer.")
    if not group.startswith("group.") or not re.fullmatch(identifier, group):
        raise ValueError("App Group phải là mã đã đăng ký và bắt đầu bằng group.")


def check_bundles(app, base, group):
    expected = {base + suffix for suffix in ("", ".monitor", ".shield", ".action", ".report")}
    extensions = sorted(app.rglob("*.appex"))
    if len(extensions) != 4:
        raise ValueError(f"Thiếu phần mở rộng của Lặng. Tìm thấy {len(extensions)}/4.")
    ordered = []
    for bundle in [*extensions, app]:
        info = read_plist(bundle / "Info.plist")
        ident = info["CFBundleIdentifier"]
        if ident not in expected or (bundle == app) != (ident == base):
            raise ValueError(f"Bundle ID không khớp: {ident}")
        expected.remove(ident)
        needs_group = ident in (base, base + ".monitor")
        if needs_group and info.get("LangAppGroup") != group:
            raise ValueError(f"App Group chưa khớp với {ident}")
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError(f"{ident} không phải bản dành cho iPhone thật.")
        executable = bundle / info["CFBundleExecutable"]
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError(f"Thiếu tệp chạy của {ident}")
        arches = subprocess.check_output(["xcrun", "lipo", "-archs", str(executable)], text=True).split()
        if "arm64" not in arches:
            raise ValueError(f"{ident} thiếu kiến trúc arm64.")
        ordered.append((bundle, needs_group))
    return ordered


def prepare_for_resigning(app, project, base, group, work):
    # Stage the capability requests in the code signatures so a resigner can read them.
    # These local '-' signatures carry no Apple identity or provisioning profile.
    ordered = check_bundles(app, base, group)
    plain = project / "Config/Family.entitlements"
    shared = read_plist(project / "Config/SharedFamily.entitlements")
    shared["com.apple.security.application-groups"] = [group]
    group_file = work / "group-entitlements.plist"
    group_file.write_bytes(plistlib.dumps(shared))
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
    nested = [p for p in app.rglob("*") if not p.is_symlink() and p.suffix in (".framework", ".dylib")]
    for binary in sorted(nested, key=lambda p: len(p.parts), reverse=True):
        run(*command, binary)
    for bundle, needs_group in ordered:
        run(*command, "--generate-entitlement-der", "--entitlements", group_file if needs_group else plain, bundle)
        run("codesign", "--verify", "--strict", bundle)


def build(base, group, output):
    validate_ids(base, group)
    if sys.platform != "darwin" or not shutil.which("xcodebuild"):
        raise ValueError("Bước biên dịch cần Xcode trên macOS. Có thể chạy bằng GitHub Actions.")
    project = Path(__file__).resolve().parents[1]
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lang-build-") as scratch:
        work = Path(scratch)
        derived = work / "DerivedData"
        run("xcodebuild", "-project", project / "Lang.xcodeproj", "-scheme", "Lang",
            "-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
            "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
            f"LANG_BUNDLE_BASE={base}", f"LANG_APP_GROUP={group}", "build")
        app = work / "Payload/Lang.app"
        app.parent.mkdir()
        run("/usr/bin/ditto", derived / "Build/Products/Release-iphoneos/Lang.app", app)
        prepare_for_resigning(app, project, base, group, work)
        # Zip the containing Payload directory, preserving the executable bits and symlinks.
        with tempfile.TemporaryDirectory(dir=output.parent, prefix=".lang-export-") as export:
            archive = Path(export) / "Lang.ipa"
            run("/usr/bin/zip", "-q", "-r", "-y", archive, "Payload", cwd=work)
            run("/usr/bin/unzip", "-tqq", archive)
            os.replace(archive, output)
    print(f"IPA chờ ký bằng chứng chỉ của bạn: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True, help="Bundle ID gốc của app")
    parser.add_argument("--app-group", default="", help="Mặc định là group.<Bundle ID>")
    parser.add_argument("--output", type=Path, default=Path("Lang.ipa"))
    args = parser.parse_args()
    try:
        build(args.bundle_id, args.app_group or "group." + args.bundle_id, args.output)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
