## 背景・目的

WebView のパスキー調査を Chromium に提案しやすい単位へ分割するため、まず **共通 CredMan ブリッジの抽出（CL1）** を独立したパッチとして保存します。WebView の conditional mediation 有効化、権限・provider approval、Chrome 固有 UI の移植とは分離した変更です。

既存の複合プロトタイプ `chromium-webview-browser-conditional.patch` は変更していません。新旧パッチを重ねて適用するものではありません。この PR は aospman のパッチ・検証記録を更新するもので、Chromium Gerrit の patchset は更新しません。

## 変更内容

- `CredManHelper` の通知名を既存のイベント用語に揃えて `onCredManUiClosed` に整理。`WebauthnBrowserBridge` は Chrome の独自選択 UI、`WebauthnCredManBridge` はフレーム単位の CredMan delegate への通知という責務を明確化。
- `getCredManBridge()` の非 null 契約により、冗長な `assumeNonNull` の削除は維持。native のフレーム・delegate の有効性確認は維持。
- Chromium README に APP/BROWSER の origin の違いを説明し、Integration を Chrome credential-selection UI と Credential Manager state/Autofill に分割。
- Java・native・WebView に 17 テストメソッドを追加。遅延コールバック、abort 後の再要求、navigation/frame destruction、APP/BROWSER の conditional get/create 非対応を検証。
- Chrome の古いテスト用 `cleanupCredManRequest()` override を削除。実行で見つかった既存 hybrid テストの cleanup 待機競合も、近隣テストと同じ bounded polling で修正（期待値は 1 回のまま）。

## 検証結果

同じ Chromium base `e972dac6c18230a8cbae2a744593916a7da1d82c`、Android x64、同一 AVD/ビルド設定で比較しました。

| 対象 | 変更前の成功数 | 最終変更後の成功数 |
| --- | ---: | ---: |
| WebAuthn Robolectric（SDK 29 / 36） | 162 | 178 |
| native delegate / factory（API 34） | 6 | 13 |
| WebView WebAuthn（API 34・single/multiprocess） | 12 | 16 |
| WebView WebAuthn（API 33・single/multiprocess） | 12 | 16 |
| Chrome WebAuthn / touch-to-fill（API 34） | 125 | 125 |

追加 17 メソッドの **31 実行パターンすべて成功**。既存テストの欠落なし。通常の回帰テストは `--num-retries=0` で実行しています。Chrome の既存 runtime skip 2 件と discovery 時の disabled 1 件は前後で同一で、成功数には含めていません。

hybrid テストの失敗は、保存した変更前 APK でも 20 回中 4 回、待機修正前の変更後 APK でも 20 回中 2 回再現しました。待機修正後は予定した **20 回すべて成功**。失敗した履歴も証跡として残しています。

9 月 11 日に確認した upstream main `e56f04e7cf5069c69db0ea27f75c49a24014fbac` の対象ファイルにも、最終パッチの `git apply --check` は成功しました。ただし、その新しい main のビルド/CQ は実施していません。ビルドは `treat_warnings_as_errors=false` です。

## 証跡とレビュー順序

1. `patches/chromium-webauthn-credman-bridge.md`：背景・責務・適用手順・対象外の整理。
2. `patches/chromium-webauthn-credman-bridge.patch`：Chromium 用の独立パッチ（20 ファイル）。
3. `artifacts/chromium-review-fixes-20260911/comparison.json`：個々のテスト名・追加パターン・skip の前後比較。`node artifacts/chromium-review-fixes-20260911/compare-results.mjs` で再検証できます。
4. 同ディレクトリの `investigation.md`：構成、失敗の切り分け、制約、コマンド、GCP cleanup。

PR に含めるのはパッチと小さな検証記録です。生の test-launcher JSON は生成物として扱い、比較結果とコードを先にレビューできるようにしています。約 4 GB の APK・全ログはローカルの調査ディレクトリへ保存し、APK は全件チェックサム照合済みです。承認された Spot VM と 500 GB ディスクは削除し、最終 GCP 監査もクリーンです。

実 Credential Provider による end-to-end のパスキー登録・認証、WebView BROWSER の新しい conditional 成功経路、permission/flag の組合せ、手動 UI smoke、CTS/CQ は今回の完了範囲に含めません。Chromium への提出前には、人間による全行レビューと別機能 CL の launch/permission/provider 確認が必要です。
