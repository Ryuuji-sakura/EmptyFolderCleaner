#!/bin/bash
#
# Developer ID署名 → 公証 → staple → 検証 までを一気に行う。
#
#   ./Scripts/release.sh
#
# 前提:
#   - Developer ID Application 証明書がキーチェーンにあること
#   - notarytoolの認証情報が "notary" というプロファイル名で保存されていること
#       xcrun notarytool store-credentials "notary" --apple-id <Apple ID> --team-id Y9B2784T8A
#
# アプリとDMGを別々に公証しているのは、DMGだけを公証・stapleすると、
# 中のアプリを取り出したあと初回起動時にオンライン照会が必要になるため。
# 両方stapleしておけばオフラインでも即座に起動できる。

set -euo pipefail

APP_DISPLAY_NAME="空フォルダ削除"
SCHEME="EmptyFolderCleaner"
IDENTITY="Developer ID Application: Ryuuji Hara (Y9B2784T8A)"
NOTARY_PROFILE="notary"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
BUILT_APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
APP="$ROOT/$APP_DISPLAY_NAME.app"
DMG="$ROOT/$APP_DISPLAY_NAME.dmg"
ZIP="$BUILD_DIR/$SCHEME-notarize.zip"
STAGE="$BUILD_DIR/dmg-stage"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

# notarytool は status: Invalid でも終了コード0を返すので、明示的に判定する。
# 失敗したら理由のログをその場で出す（これが無いと原因が分からないまま先へ進む）。
notarize() {
    local artifact="$1" out id
    out="$(xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
    echo "$out"
    if ! grep -q "status: Accepted" <<<"$out"; then
        id="$(sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' <<<"$out" | head -1)"
        printf '\n\033[1;31m公証に失敗しました\033[0m\n'
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE"
        return 1
    fi
}

step "プロジェクトを生成"
cd "$ROOT"
xcodegen generate

step "テストを実行"
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -configuration Debug -derivedDataPath build test 2>&1 | tail -3

step "Developer IDで署名してビルド"
rm -rf "$BUILT_APP"
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -configuration Release -derivedDataPath build build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" 2>&1 | tail -3

step "署名を確認"
# 公証には Hardened Runtime（flags に runtime）と、Appleのタイムスタンプが必須。
codesign -dv --verbose=4 "$BUILT_APP" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|flags"
codesign --verify --strict --deep --verbose=2 "$BUILT_APP"
if codesign -d --entitlements :- "$BUILT_APP" 2>/dev/null | grep -q "get-task-allow"; then
    echo "エラー: get-task-allow が署名に含まれています。このままでは公証に通りません。" >&2
    echo "project.yml の Release 設定に CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO があるか確認してください。" >&2
    exit 1
fi

step "アプリを公証（数分かかります）"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT_APP" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"

step "アプリにstaple"
xcrun stapler staple "$BUILT_APP"

step "配布用の名前でアプリを配置"
rm -rf "$APP"
cp -R "$BUILT_APP" "$APP"

step "DMGを作成"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

step "DMGに署名"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

step "DMGを公証（数分かかります）"
notarize "$DMG"

step "DMGにstaple"
xcrun stapler staple "$DMG"

step "Gatekeeperの判定を確認"
echo "--- アプリ ---"
spctl --assess --type execute --verbose=4 "$APP"
echo "--- DMG ---"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

printf '\n\033[1;32m完了: %s\033[0m\n' "$DMG"
