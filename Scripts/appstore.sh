#!/bin/bash
#
# Mac App Store 提出用の .pkg を作る。
#
#   ./Scripts/appstore.sh
#
# Developer ID 配布用の `release.sh` とは別物で、共通点はほとんど無い。
#   - 署名は Apple Distribution（Developer ID ではない）
#   - .pkg に 3rd Party Mac Developer Installer で署名する
#   - 公証は不要。App Store 側の審査がその役割を果たすので notarytool は使わない
#   - stapler も DMG も不要
#
# 前提:
#   - Apple Distribution 証明書
#   - 3rd Party Mac Developer Installer 証明書
#   （どちらも Xcode → Settings → Accounts → Manage Certificates → + から作る）
#
# このスクリプトはアップロードまではしない。最後に出る手順で、内容を確認してから
# 手で送ること。提出は取り消せない。

set -euo pipefail

SCHEME="EmptyFolderCleaner"
CONFIG="ReleaseMAS"
TEAM_ID="Y9B2784T8A"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build-mas"
ARCHIVE="$OUT/$SCHEME.xcarchive"
EXPORT_DIR="$OUT/export"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

cd "$ROOT"

step "プロジェクトを生成"
xcodegen generate

step "テストを実行"
# ログの出力先は先に作る。ここで作らないと、build-mas/ が無い状態（クリーンな
# チェックアウト直後）でリダイレクトそのものが失敗し、テストが走らない。
mkdir -p "$OUT"
# `| tail` を通すと終了コードが tail のものになり、失敗しても素通りする。
if ! xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
        -configuration Debug -derivedDataPath build test > "$OUT/test.log" 2>&1; then
    grep -E "error:|Executed .* tests" "$OUT/test.log" | tail -20
    echo "テストが失敗しました。詳細: $OUT/test.log" >&2
    exit 1
fi
grep -E "Executed .* tests" "$OUT/test.log" | tail -2

step "アーカイブを作成"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$OUT"
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -configuration "$CONFIG" -derivedDataPath "$OUT" \
    -archivePath "$ARCHIVE" archive 2>&1 | tail -3

step "App Store 用に書き出し"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
# -allowProvisioningUpdates は、App ID と Mac App Store 用プロファイルを
# 必要に応じて作らせるために要る。証明書が既にあれば新規発行はされない。
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" -allowProvisioningUpdates 2>&1 | tail -3

PKG="$EXPORT_DIR/$SCHEME.pkg"

step "署名と entitlements を検証"
APP_IN_PKG="$OUT/verify"
rm -rf "$APP_IN_PKG"
pkgutil --expand-full "$PKG" "$APP_IN_PKG" > /dev/null
APP="$(find "$APP_IN_PKG" -maxdepth 4 -name "*.app" -type d | head -1)"

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
echo "$ENTITLEMENTS" | plutil -p - 2>/dev/null || echo "$ENTITLEMENTS"

# App Store 提出物には application-identifier が必須で、get-task-allow があると弾かれる。
# この2点は project.yml の CODE_SIGN_INJECT_BASE_ENTITLEMENTS の設定次第で簡単に壊れる。
if ! grep -q "application-identifier" <<<"$ENTITLEMENTS"; then
    echo "エラー: com.apple.application-identifier が入っていません。" >&2
    echo "project.yml の ReleaseMAS に CODE_SIGN_INJECT_BASE_ENTITLEMENTS: YES があるか確認してください。" >&2
    exit 1
fi
if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
    echo "エラー: get-task-allow が入っています。この署名では提出できません。" >&2
    exit 1
fi
if [ ! -e "$APP/Contents/embedded.provisionprofile" ]; then
    echo "エラー: プロビジョニングプロファイルが埋め込まれていません。" >&2
    exit 1
fi
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^Authority=Apple Distribution|TeamIdentifier"
pkgutil --check-signature "$PKG" 2>&1 | sed -n '2,4p'
rm -rf "$APP_IN_PKG"

printf '\n\033[1;32m完了: %s\033[0m\n' "$PKG"
cat <<EOF

App Store Connect へ送るには、次のどちらかで:

  1. Xcode → Window → Organizer → 該当アーカイブ → Distribute App
  2. Transporter.app に $PKG をドロップ

送信前に App Store Connect 側でアプリを登録しておくこと
（マイApp → + → 新規App / バンドルID: com.ryuujisakura.emptyfoldercleaner）。
提出は取り消せないので、内容を確認してから送ること。

EOF
