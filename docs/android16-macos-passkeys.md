# Android 16・改造WebView・LightningをMacで比較する

Android 16のAOSPイメージにChromiumからビルドしたWebViewを組み込み、Apple Silicon MacのAndroid Emulatorで動作を確認した。さらにLightningを未改造版と `.passkey` 対応版で共存させ、2つのRPで比較した。

`passkeys-debugger.io` では、未改造版は作成・Autofillとも `NotSupportedError` になった。対応版は作成を完了し、空の入力欄から保存済みパスキーを選択して署名付きの認証結果を返した。既存の改造WebViewと、両アプリを明示的に許可したテスト用プロバイダを使った結果である。

## 再現用の変更

| ファイル | 役割 |
| --- | --- |
| [Android 16ビルド・起動手順](../tools/android16-macos/README.md) | Linuxでarm64 Androidをビルドし、Macの専用AVDで起動する |
| [AOSPへのWebView組み込みパッチ](../patches/aosp-android16-preserve-webview-signature.patch) | 完全なWebView APKを署名保持で取り込む。Soongの検査は有効のまま |
| [既存のChromiumパッチ](../patches/chromium-webview-browser-conditional.patch) | BROWSERモードのCredential Manager経路とconditional getを有効化する |
| [Lightningパッチ](../patches/lightning-browser-passkey.patch) | WebAuthnのBROWSER設定、origin/candidate権限、名前・パッケージの `.passkey` suffix、独立したtask affinity |
| [Lightningビルド手順](../patches/lightning-browser-passkey.md) | 未改造版と対応版のビルド・インストール |
| [テスト用プロバイダの設定パッチ](../patches/test-provider-lightning-allowlist.patch) | 両方のLightningのパッケージと署名を明示的に許可する |

AOSPとChromiumのAndroid向けバイナリはLinuxでクロスビルドした。macOSで実行するのは完成したarm64エミュレータであり、Lightningの2 APKとテスト用プロバイダはMacでビルドした。

## 固定した構成

| 対象 | リビジョン・設定 |
| --- | --- |
| AOSP | `https://android.googlesource.com/platform/manifest`、`android-16.0.0_r4`、manifest commit `15128c9e27cfa599c48d294babd39286ee8f1426` |
| AOSPターゲット | `sdk_phone64_arm64-aosp_current-userdebug` |
| Chromium | `https://chromium.googlesource.com/chromium/src.git`、`98596990901c11e89a24f6217f1b66513b065026`、`154.0.8016.0` |
| WebViewターゲット | `system_webview_64_apk`、`target_cpu="arm64"` |
| Lightning | `https://github.com/anthonycr/Lightning-Browser.git`、`6b222ad616d4563f2b3a5b8a37e33b3e4042de28` |
| Lightningビルド | Plus debug、`5.1.0` / `102`、min SDK 28、target SDK 37、AndroidX WebKit 1.17.0 |
| ビルドツール | Gradle 9.7.1、AGP 9.4.0、Kotlin 2.4.10、compile SDK 37.1、build-tools 37.0.0、Temurin JDK 21.0.12.1+1 |
| AVD | `aospman_android16`、`emulator-5560`、Android 16/API 36、arm64、4 CPU・4 GiB RAM |
| ビルド識別子 | `Android/sdk_phone64_arm64/emu64a:16/BP4A.251205.006/aospman-android16-arm64:userdebug/test-keys` |
| プロバイダ | `com.example.aospman.passkeyprovider`、`1.0` / `1`、target SDK 35 |
| 有効・優先コンポーネント | `com.example.aospman.passkeyprovider/com.example.android.authentication.myvault.data.MyVaultService` |

LightningのAPI利用箇所は `app/src/main/java/acr/browser/lightning/browser/tab/WebViewFactory.kt:createWebView`。上流にある `IMPORTANT_FOR_AUTOFILL_YES` を維持し、`WEB_AUTHENTICATION` の対応を確認して `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER` を設定した。Manifestには `CREDENTIAL_MANAGER_SET_ORIGIN` と `CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS` を追加した。

両ブラウザの署名SHA-256は `d6b890eca6f4708aff24be19176c56afee38d8d4d5612a9964f5f581ccc2b4b1`。プロバイダの署名SHA-256は `718ee94d925d8fb9e560909b56e15cf526d49cf07a732cf6f513619398b1b0b2`。テスト用許可設定はパッケージと署名の組を固定し、既存のorigin・署名検証を維持する。別の署名鍵を使う場合は、その鍵に対する明示的な許可設定が必要になる。

## 2026-09-10: passkeys-debugger.ioでの比較

RP originは `https://www.passkeys-debugger.io`、RP IDは `www.passkeys-debugger.io`。作成はサイトの初期設定を使用した。

- User Verification: Required
- Authenticator Attachment: Platform
- Resident Key: Preferred
- Attestation: Direct
- WebAuthn Hints: 空

ユーザー名とchallengeはサイトがテスト用に生成した値を使用した。2つのAPK、WebView、プロバイダのハッシュは前日の成果物と一致し、比較中に変更していない。

| 確認項目 | Lightning（未改造） | Lightning.passkey |
| --- | --- | --- |
| パッケージ | `acr.browser.lightning` | `acr.browser.lightning.passkey` |
| `typeof PublicKeyCredential` | `undefined` | `function` |
| conditional availability | APIなし | `true` |
| platform authenticator availability | APIなし | `true` |
| 作成ボタン | `NotSupportedError: Error connecting to Web Authentication service.`、保存画面なし | 正しいRPの保存画面 → 通常の端末認証 → 作成結果がサイトに返る |
| 空のユーザー名欄でAutofill | 同じ `NotSupportedError`。保存済みRPパスキーが存在しても候補なし | 保存済みパスキーの候補 → 通常の端末認証 → assertionがサイトに返る |

Autofillでは両方ともCredential IDを空にし、ユーザー名を空にしてから設定を有効にした。DOMの `autocomplete="webauthn"` と値の長さ0を確認し、入力欄をタップした。対応版の成功時に通常のログインボタンは押していない。未改造版のAutofill比較は、対応版でRPパスキーを作成した後に実施した。

サイトは空のユーザー名にフォーム検証エラーを表示するが、Autofillの非同期処理は別に起動する。対応版は同じ空欄状態で完了した。未改造版の失敗はフォーム検証表示だけから推測したものではなく、コンソールでWebAuthnの `NotSupportedError` を確認した。

### 返却データの検証範囲

対応版の作成結果では、`webauthn.create`、期待するorigin、RP ID hash、作成要求と返却challengeの一致、UP/UVを確認した。Autofillの結果では、`webauthn.get`、同じcredential、期待するoriginとRP ID hash、UP/UVを確認し、作成結果の公開鍵でES256署名をローカル検証した。

このデバッガーは結果を表示・解析する構成で、サイトの表示だけをRPサーバーのログイン成功とは扱っていない。ログインの呼び出し経路は新しいoptionsを生成するため、画面のPreview Requestのchallengeと返却challengeは異なった。実際に `get` に渡されたchallengeは採取しておらず、この検証にサーバー側challenge照合は含まれない。

稼働サイトのソースcommitは公開情報から特定していない。代わりに、両ブラウザが読み込んだ同じdeploymentのscript URLを照合し、取得したJavaScriptのSHA-256で固定した。作成・ログイン処理を含む `0~zf~mqxievtg.js` のSHA-256は `9dbb2f393e1f7b7be9cbb98f6a794115365fcd412876d77495aad8382fda3587`。その `al`、`au`、`am` 関数でcreate、get、conditional effectと入力欄の設定を確認した。

公開可能な証拠:

- [構成・API判定・例外・署名検証結果](evidence/passkeys-debugger-20260910/results.json)
- [取得したサイト資材のURL・ハッシュ](evidence/passkeys-debugger-20260910/source-provenance.json)
- [匿名化したCredential Managerログ](evidence/passkeys-debugger-20260910/logcat.txt)
- [未改造版のAutofillエラー画面](evidence/passkeys-debugger-20260910/control-autofill-error.png)

### 同じサイトでの再現手順

1. ビルド・起動手順に従って専用AVDを起動し、通常の画面ロック解除を行う。テスト用プロバイダを有効・優先にする。
2. 両方のLightning APKをインストールし、どちらも同じWebViewとプロバイダを使っていることを確認する。
3. 各ブラウザで `https://www.passkeys-debugger.io/#debugger` を開く。案内モーダルやバナーが出た場合は画面の閉じる操作で閉じる。
4. 未改造版で初期設定の作成ボタンを押し、例外と保存画面の有無を記録する。
5. 対応版で同じ設定の作成を実行し、テスト用プロバイダを選んで端末認証を完了する。返った作成結果を保存する。
6. Login with passkeyタブのSettingsを開く。Credential IDを空、ユーザー名も空にしてAutofillを有効にする。
7. 空のユーザー名欄をタップし、保存済みパスキーを選択して端末認証を完了する。返ったassertionを保存する。
8. パスキーが保存された状態で未改造版にも同じAutofill設定を適用し、候補の有無と例外を確認する。

UI操作はadbで行い、各操作後にスクリーンショットとUI XMLを保存した。CDPは読み取り専用のDOM/API確認、コンソール観測、サイトが表示したJSONの採取に使用した。認証APIの差し替え、JavaScriptによる認証実行、ページの書き換えは行っていない。

## 先行する検証

2026-09-08〜09のAOSP/WebView検証では、同じブラウザfixtureで未改造WebViewと改造WebViewを比較した。改造版でAndroid 16上の通常create/getとconditional getが成功した。最初のconditional assertionのchallenge不一致と、候補が出なかったreloadも保存してあり、反復時の信頼性まで証明した結果ではない。

2026-09-09のLightning比較では `https://passkey-test-lab-production.up.railway.app` を使用した。未改造LightningはAPIを利用できず、対応版は作成・通常ログイン・AutofillログインすべてでRPサーバーの検証と認証済みページへの遷移に成功した。このRPでの結果と、今回のデバッガーでの表示・ローカル署名検証を区別する。

## 成果物の識別

| APK | SHA-256 |
| --- | --- |
| 未改造Lightning | `a59a85e6024c9b1aeb908694de41a9d50d94fc13ee010ab572ccbe040ca63e07` |
| Lightning.passkey | `951a481a4e7b19139fee383c6a3d09b1bbe27c4a9c721efd0b67f94b893f2833` |
| 許可設定更新後のテスト用プロバイダ | `a1bbe99ae9d741ba74b3bd176dbc6dd558a7355e327277e1400af86eaa9092d4` |
| 改造WebView | `bf0c5f74c1275d622ecca1f0bf7a8e180fd50ad2a8a1da892809c310fcbfc914` |
| 同一revision・署名の未改造WebView | `fcfa19c150cd8177c355f8062a98c9bb2a7d6d4acdbf5c6397afd4ddb02c73a6` |

イメージ、APK、完全なビルドログ、元のスクリーンショット・UI XML、PINを含むローカル設定はリポジトリ内の次のローカル成果物ディレクトリに保存した。これらはGitの除外対象であり、このPRには含めない。

- `artifacts/android16-macos-emulator-20260908/`
- `artifacts/lightning-passkey-20260909/`
- `artifacts/passkeys-debugger-lightning-20260910/`

各ディレクトリの `investigation.md` が詳細記録で、APK・パッチ・証拠のハッシュも保存している。新しいcloneではビルド手順から再生成する必要がある。

## 検証と残る範囲

完全なarm64 WebViewとAOSPイメージのビルド、署名を保持したAPK取り込み、Macでの起動、2つのLightningのビルド・共存インストールを実施した。Lightningの初回ビルドはJBRに `jlink` がなく失敗したが、完全なJDK 21で解消した。SDKやアプリの互換性コードを変更する回避策は不要だった。テスト用プロバイダの既存unit test 1件も成功したが、包括的なtrust-policyテストではない。

今回のアプリ設定はまとめて評価したため、権限ごとの必要性を個別に切り分けてはいない。Google Password Managerの承認、Chrome Password ManagerのUI、未改造WebViewのconditional対応、conditional create、実機、incognito、Lite、release署名、負荷・反復試験は対象外。

AOSP/Chromiumビルドに使用した管理対象Spot VMとディスクは成果物回収後に削除済み。最終実行監査はinstances、disks、reserved addresses、snapshots、custom imagesすべて空だった。Lightningとデバッガーの比較ではGCPを使用していない。採取用プロセスとadb転送を終了し、一時的なAC電源設定を戻して、AVDと両アプリは残した。
