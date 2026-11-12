#!/bin/bash
# Build locally without signing or publishing a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."
test -d Vendor/VLCKit/VLCKit-all.xcframework || bash scripts/fetch-vlckit.sh
mkdir -p build output
xcodebuild -project DouDuo.xcodeproj -scheme DouDuo -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/ReleaseDerivedData build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 \
  > build/unsigned-build.log 2>&1
stage=$(mktemp -d "$PWD/build/unsigned-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
ditto build/ReleaseDerivedData/Build/Products/Release-iphoneos/DouDuo.app "$stage/Payload/DouDuo.app"
python3 - "$stage" <<'PY'
import pathlib, plistlib, shutil, subprocess, sys
stage = pathlib.Path(sys.argv[1])
app = stage / 'Payload/DouDuo.app'
with (app / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert info['CFBundleShortVersionString'] == '1.3.11', info
assert info['CFBundleVersion'] == '92', info
assert info['CFBundleIdentifier'] == 'com.zenghongjvn.douduo', info
assert info['MinimumOSVersion'] == '27.1', info
assert info['UIDeviceFamily'] == [1], info
# CODE_SIGNING_ALLOWED=NO skips Xcode's normal framework architecture thinning.
# This app only targets arm64 iPhones; retain the exact upstream arm64 VLC slice.
for framework in (app / 'Frameworks').glob('*.framework'):
    binary = framework / framework.stem
    if not binary.is_file():
        continue
    archs = subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split()
    assert 'arm64' in archs, (binary, archs)
    if archs != ['arm64']:
        thin = binary.with_suffix('.arm64')
        subprocess.run(['xcrun', 'lipo', str(binary), '-thin', 'arm64', '-output', str(thin)], check=True)
        thin.replace(binary)
    assert subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).strip() == 'arm64'
for signature in app.rglob('_CodeSignature'):
    shutil.rmtree(signature)
for profile in app.rglob('embedded.mobileprovision'):
    profile.unlink()
PY
artifact="$PWD/output/DouDuo-1.3.11-build92-Duo-unsigned.ipa"
(cd "$stage" && /usr/bin/ditto -c -k --norsrc --keepParent Payload "$artifact")
unzip -tq "$artifact"
(cd output && shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256")
printf 'Unsigned IPA: %s\n' "$artifact"
