# リリースの手順

配布するアプリは **Developer ID Application** の証明書で署名し、Apple の公証（notarization）を通してチケットを添付します。CI で作るアプリはアドホック署名の開発用です。タグを打つと、CI はアプリを添付しない**下書き**だけを作るので、未署名のアプリが正式なリリースとして公開されることはありません。

## 最初に一度だけ

### 公証の認証情報

Apple Developer Program のメンバーシップと、Developer ID Application の証明書（秘密鍵つき）が必要です。Apple Development の証明書では配布できません。

公証の認証情報を、ターミナルで Keychain に保存します。パスワードはアプリ用パスワードを入力します（画面には表示されません）。

```sh
xcrun notarytool store-credentials "uchikoe-notary" \
  --apple-id "you@example.com" --team-id "YOUR_TEAM_ID"
```

パスワードや認証情報を Issue、チャット、リポジトリに書かないでください。

### 更新の署名の鍵

アプリの更新には Sparkle を使い、更新情報（appcast.xml）とアプリを EdDSA の鍵で署名します。秘密鍵はログインキーチェーンに、アカウント名 `uchikoe` で保存しています。

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account uchikoe -p   # 公開鍵を表示
```

公開鍵は `updates/public-key.txt` にあり、アプリの Info.plist に `SUPublicEDKey` として入ります。**秘密鍵をなくすと、配布済みのアプリを二度と更新できません。** 次のコマンドで書き出して、安全な場所（パスワードマネージャーなど）に保管してください。書き出したファイルは、保管したら消してください。リポジトリの中には書き出さず、CI にも置かないでください。

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account uchikoe -x ~/Desktop/uchikoe-sparkle-private.key
```

## 作って確かめる

リリースするコミット（CI が通ったもの）で、更新内容を `updates/<バージョン>.md` に書いてから、署名・公証つきで作ります。

```sh
scripts/lint.sh
scripts/test.sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="uchikoe-notary" \
VERSION="0.1.0" scripts/package-app.sh
```

スクリプトは、Hardened Runtime と安全なタイムスタンプで署名し、zip を公証に出し、チケットを添付して Gatekeeper の判定まで確かめます。そのあと zip とチェックサムを作り直し、`updates/<バージョン>.md` から署名つきの `appcast.xml` を作ります。途中で失敗したら止まるので、原因を直してからやり直してください。

最後に、出来上がったものを確かめます。

```sh
codesign --display --verbose=4 dist/Uchikoe.app
xcrun stapler validate dist/Uchikoe.app
spctl --assess --type execute --verbose dist/Uchikoe.app
(cd dist && shasum -a 256 -c Uchikoe-0.1.0-macOS-arm64.zip.sha256)
```

アプリケーションフォルダに入れて起動し、マイクとアクセシビリティの許可、fn での録音と貼り付け、設定画面、「アップデートを確認…」を実際に確かめます。

## 公開する

1. バージョンのタグ（`v0.1.0` など）を push し、「Prepare release」のワークフローが下書きを作るのを待ちます。下書きが正しいコミットを指していることを確かめます。
2. 下書きの説明を、実際の更新内容と、署名・公証の結果に書き換えます。
3. 確かめた zip、チェックサム、**appcast.xml** の 3 つを添付します。
4. プレリリースの印を外し、**通常のリリース**として、最新のリリースにして公開します。

アプリは `https://github.com/moguone/uchikoe/releases/latest/download/appcast.xml` で更新を確認します。下書きやプレリリースは対象外です。appcast.xml を添付せずに公開すると、更新の確認が失敗します。証明書、秘密鍵、公証の認証情報は、リポジトリにもリリースにも添付しないでください。

## 依存の更新

Dependabot が Sparkle の更新の Pull Request を作ります。Sparkle を上げたときは、`THIRD_PARTY_NOTICES.md` のバージョンと、ライセンスの内容に変わりがないかも確かめてください。

## 参考

- [Apple: Developer ID の証明書](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Apple: 公証の流れ](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
