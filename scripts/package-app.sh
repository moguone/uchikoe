#!/bin/bash
# Uchikoe.app を組み立てて署名し、配布用の zip とチェックサムを作る。
#
#   scripts/package-app.sh                       # 開発用（アドホック署名）
#   CODE_SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=uchikoe-notary \
#     VERSION=0.1.0 scripts/package-app.sh       # 配布用（署名・公証・appcast.xml）
#
# アドホック署名はビルドのたびに署名が変わるので、マイクやアクセシビリティの許可を取り直すことになる。
# 手元で使い続けるなら、CODE_SIGN_IDENTITY に自分の証明書（Apple Development など）を指定する。
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:-0.0.0}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "VERSION は数字をドットでつないだ形にする" >&2; exit 1; }
identity="${CODE_SIGN_IDENTITY:--}"
if [[ -n "${NOTARY_PROFILE:-}" && "$identity" == "-" ]]; then
  echo "公証には CODE_SIGN_IDENTITY（Developer ID Application）が要る" >&2
  exit 1
fi
output_dir="${OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app="$output_dir/Uchikoe.app"
if pgrep -fq "^$app/Contents/MacOS/Uchikoe"; then
  echo "$app が起動中なので置き換えない。終了してから実行する" >&2
  exit 1
fi

swift build --configuration release --arch arm64
bin_dir="$(swift build --configuration release --arch arm64 --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/Uchikoe" "$app/Contents/MacOS/Uchikoe"
ditto "$bin_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp -R Resources/vocabularies "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Third-Party Notices.md"

# アプリの中のファイル名は英数字だけにする。日本語の名前は、Finder でコピーしたり zip を展開したりすると
# Unicode の正規化が変わり、署名が合わなくなって「壊れている」と判定される
if find "$app" | LC_ALL=C grep -q '[^ -~]'; then
  echo "アプリの中に英数字以外のファイル名がある:" >&2
  find "$app" | LC_ALL=C grep '[^ -~]' >&2
  exit 1
fi

# アイコン（Resources/AppIcon.png、1024×1024）から icns を作る
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$app/Contents/Resources/AppIcon.icns"

public_key=""
[[ -f updates/public-key.txt ]] && public_key="$(tr -d '[:space:]' < updates/public-key.txt)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Uchikoe</string>
  <key>CFBundleDisplayName</key><string>Uchikoe</string>
  <key>CFBundleIdentifier</key><string>io.github.moguone.uchikoe</string>
  <key>CFBundleExecutable</key><string>Uchikoe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleDevelopmentRegion</key><string>ja</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 moguone. MIT License.</string>
  <key>NSMicrophoneUsageDescription</key><string>話した内容を、この Mac の中だけで文字にするためにマイクを使います。</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Apple の音声認識を、この Mac の中だけで使います。</string>
  <key>SUFeedURL</key><string>https://github.com/moguone/uchikoe/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$public_key</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUEnableSystemProfiling</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
# 公開鍵がないビルドでは、アプリが更新を確認しない（AppUpdater が SUPublicEDKey の有無を見る）
if [[ -z "$public_key" ]]; then
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$app/Contents/Info.plist"
fi

# Sparkle を arm64 だけにしてから、内側の部品から順に署名する
runtime_options="$([[ "$identity" == "-" ]] && echo 0 || echo runtime)"
timestamp=()
[[ "$identity" != "-" ]] && timestamp=(--timestamp)
framework="$app/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' file; do
  [[ -L "$file" ]] && continue
  file -b "$file" | grep -q '^Mach-O' || continue
  archs="$(lipo -archs "$file")"
  [[ " $archs " == *" arm64 "* ]] || { echo "arm64 がない: $file" >&2; exit 1; }
  if [[ "$archs" != "arm64" ]]; then
    lipo "$file" -thin arm64 -output "$file.arm64"
    chmod "$(stat -f %Lp "$file")" "$file.arm64"
    mv "$file.arm64" "$file"
  fi
done < <(find "$framework" -type f -print0)
for target in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc \
  Versions/B/XPCServices/Downloader.xpc .; do
  codesign --force --options "$runtime_options" --preserve-metadata=entitlements ${timestamp[@]+"${timestamp[@]}"} \
    --sign "$identity" "$framework/$target"
done
codesign --force --options "$runtime_options" ${timestamp[@]+"${timestamp[@]}"} --entitlements Uchikoe.entitlements \
  --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

archive="$output_dir/Uchikoe-$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
(cd "$output_dir" && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  scripts/make-appcast.sh "$archive"
fi
printf 'App: %s\nArchive: %s\n' "$app" "$archive"
