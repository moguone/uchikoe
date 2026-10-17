# コントリビュート

Issue や Pull Request を歓迎します。大きな変更は、先に Issue で相談してください。

## 開発の準備

- Apple シリコンの Mac、macOS 26 以降
- Xcode（Swift 6.2 以降）

```sh
scripts/test.sh       # 単体テスト
scripts/lint.sh       # swift format の決まりに沿っているか
scripts/format.sh     # swift format で整形する
scripts/package-app.sh
open dist/Uchikoe.app
```

ビルドだけなら `swift build` で確かめられます。マイクやアクセシビリティの許可には Info.plist のあるアプリが要るので、動作の確認は `scripts/package-app.sh` で作ったアプリで行ってください。

## 構成

| 場所 | 役割 |
|---|---|
| `Sources/UchikoeCore/` | テストできる部品。語彙リスト（`Vocabulary`）、フィラーの除去（`TextCleanup`）、録音のキー（`Shortcut`）、清書（`Polisher`） |
| `Sources/Uchikoe/` | アプリ本体。録音、音声認識、キー入力の見張り、貼り付け、メニューバー、設定画面、アップデート |
| `Resources/` | アプリのアイコンと、最初に入っている語彙リスト（1 行に 1 語で「表記 = 読み, 読み」） |
| `Tests/UchikoeCoreTests/` | `UchikoeCore` の単体テスト |
| `scripts/` | テスト、整形、アプリの組み立て、更新情報の作成 |
| `updates/` | 各バージョンの更新内容と、更新の署名の公開鍵 |

## Pull Request の前に

- `scripts/lint.sh` と `scripts/test.sh` が通ることを確かめてください。CI でも同じものを動かします。
- 音声認識、マイク、アクセシビリティにかかわる変更は、`scripts/package-app.sh` で作ったアプリで実際に話して確かめてください。
- 外部に通信する処理を足す変更は、README の「プライバシー」の表も直してください。音声や文字にした結果を外に送る変更は受け付けません。
