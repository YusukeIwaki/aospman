# Passkey Test Lab

rbenv の Ruby 4.0.0 + Sinatra で作った、WebAuthn パスキーの動作確認用サイトです。Railway のコンテナも同じ Ruby 4.0.0 で動作します。

- discoverable credential（resident key 必須）の作成
- ユーザー名指定またはユーザー名なしのパスキーログイン
- `autocomplete="username webauthn"` と Conditional Mediation による autofill
- ログイン済みページとログアウト
- JSON ファイルへの認証情報永続化（Railway では Volume を `/data` にマウント）

## ローカル起動

WebAuthn は `localhost` を secure context として扱います。依存関係の導入とテストは rbenv で Ruby 4.0.0 を選択して実行します。

```sh
rbenv local 4.0.0
rbenv exec bundle install
npm ci
./node_modules/.bin/playwright install chromium
rbenv exec bundle exec ruby -Itest test/app_test.rb
rbenv exec bundle exec smartest smartest/passkey_flow_test.rb
```

## ブラウザE2Eテスト

Smartest 0.7.0とPlaywright 1.61.0の仮想WebAuthn Authenticatorを使い、ブラウザ上で次のフローを検証します。

- パスキー作成、認証済みページ表示、ログアウト
- discoverable credentialを使ったユーザー名なしログイン
- `mediation: "conditional"` から登録済みパスキーを使う再ログイン

既定はChromiumです。Playwrightの各ブラウザを導入した環境では、同じテストをFirefoxとWebKitでも実行できます。

```sh
rbenv exec bundle exec smartest smartest/passkey_flow_test.rb
BROWSER=firefox rbenv exec bundle exec smartest smartest/passkey_flow_test.rb
BROWSER=webkit rbenv exec bundle exec smartest smartest/passkey_flow_test.rb
```

このテストはWebAuthnのcreate/get、署名検証、セッション遷移、およびConditional Mediationのアプリケーション経路を担保します。OSやブラウザが表示する実際のパスキー候補UI、Credential Manager、Android WebViewのautofill統合は仮想Authenticatorの対象外なので、対象端末でも別途確認してください。

Pull RequestではGitHub ActionsがRackテストとJavaScript構文チェックに加え、Chromium、Firefox、WebKitの3ブラウザで同じSmartest E2Eを実行します。

コンテナで起動する場合:

```sh
docker build -t passkey-test-lab .
docker run --rm -p 3000:3000 \
  -e RACK_ENV=development \
  -e WEBAUTHN_ORIGIN=http://localhost:3000 \
  -e WEBAUTHN_RP_ID=localhost \
  -e SESSION_SECRET=development-session-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  passkey-test-lab
```

`http://localhost:3000` を開いて確認します。

## 環境変数

| 変数 | 用途 |
| --- | --- |
| `WEBAUTHN_ORIGIN` | ブラウザから見える HTTPS Origin |
| `WEBAUTHN_RP_ID` | Origin のホスト名に一致する RP ID |
| `SESSION_SECRET` | 64文字以上のランダムなセッション署名鍵 |
| `PASSKEY_STORE_PATH` | 認証情報を保存する JSON ファイル |
| `PORT` | HTTP listen port（Railway が自動設定） |

## Android での確認メモ

通常の WebAuthn と Conditional UI は別機能です。Chrome では両方を確認できます。Android WebView ベースのブラウザでは、通常のパスキー認証が動作しても Conditional Mediation が未対応の場合があり、その場合はページ上部に「Autofill 未対応」と表示されます。
