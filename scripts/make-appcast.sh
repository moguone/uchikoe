#!/bin/bash
# 配布用の zip から、署名付きの更新情報（appcast.xml）を作る。
# 更新内容は updates/<version>.md に書いておく。署名には Keychain の Sparkle の鍵（アカウント uchikoe）を使う。
set -euo pipefail
cd "$(dirname "$0")/.."
archive="${1:?使い方: scripts/make-appcast.sh dist/Uchikoe-<version>-macOS-arm64.zip}"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
filename="$(basename "$archive")"
version="${filename#Uchikoe-}"
version="${version%-macOS-arm64.zip}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "zip の名前が想定と違う: $filename" >&2; exit 1; }
[[ -f "updates/$version.md" ]] || { echo "updates/$version.md がない" >&2; exit 1; }
output_dir="$(dirname "$archive")"
staging="$(mktemp -d "$output_dir/.appcast.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$archive" "$staging/$filename"
cp "updates/$version.md" "$staging/${filename%.zip}.md"
release_url="https://github.com/moguone/uchikoe/releases"
bin=.build/artifacts/sparkle/Sparkle/bin
"$bin/generate_appcast" --account uchikoe --maximum-deltas 0 --maximum-versions 1 --embed-release-notes \
  --download-url-prefix "$release_url/download/v$version/" \
  --link "$release_url/tag/v$version" --full-release-notes-url "$release_url/tag/v$version" \
  -o "$staging/appcast.xml" "$staging"
"$bin/sign_update" --account uchikoe --verify "$staging/appcast.xml"
cp "$staging/appcast.xml" "$output_dir/appcast.xml"
printf '署名付きの更新情報: %s\n' "$output_dir/appcast.xml"
