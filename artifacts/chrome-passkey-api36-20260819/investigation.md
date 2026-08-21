# Chrome passkey investigation record

Date: 2026-08-19 (Asia/Tokyo)

## Hypothesis

Chrome on the Android CLI-created Google Play AVD can complete ordinary WebAuthn create/get and conditional mediation against `https://passkey-test-lab-production.up.railway.app`.

Distinguishing success criteria:

- ordinary create shows Credential Manager, stores a credential, and reaches `/api/register/verify`;
- ordinary get returns that credential and reaches `/api/login/verify`;
- conditional mediation presents the stored passkey when the username field is focused and completes login.

## Configuration

- AVD: `medium_phone`, serial `emulator-5554`
- Android: 16 / API 36 / `arm64-v8a`
- Build fingerprint: `google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.D1/13818094:user/release-keys`
- System image: `system-images/android-36/google_apis_playstore/arm64-v8a/`
- Chrome package: `com.android.chrome`
- Chrome: `133.0.6943.137` (`versionCode=694313732`, signing token `e3ca78d8`, APK signing v3)
- Google Play services: `25.08.34 (260400-739221510)` (`versionCode=250834035`)
- Credential service: `com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService`
- Autofill service: `com.google.android.gms/.autofill.service.AutofillService`
- Credential provider: Google Password Manager
- Google accounts: initially 0; an authorized test account was added during the run (identity omitted)
- RP origin: `https://passkey-test-lab-production.up.railway.app`
- RP ID: `passkey-test-lab-production.up.railway.app`
- Canceled pre-account username: `[redacted-test-user-a]`
- Successful test username: `[redacted-test-user-b]`
- Workspace revision at start: `edb485fa5ca25083e941bbace91045cdfaedf126`
- Deployed Railway revision: not independently proven from the running service

## Test configuration changes

- Set a disposable emulator PIN with `adb shell locksettings set-pin "$TEST_PIN"`; the test value is redacted.
- Verified `secure=true` and the lock screen enabled.
- No Google account credentials were entered by the investigating agent. A test account appeared on the device while the run was active, after the Google sign-in screen had been reached.
- No display-size override was used.
- Chrome was left on the authenticated `/account` page at handoff.

## Observations

1. Chrome initially produced an ANR in `org.chromium.chrome.browser.firstrun.FirstRunActivity`: input dispatch timed out waiting for a focus event. Force-stopping Chrome without clearing app data and relaunching removed the ANR.
2. The page reported `WebAuthn 対応` and `Autofill 対応`.
3. The deployed production client has a pre-WebAuthn form-ordering bug. It calls `setBusy(form, true)` before `new FormData(form).get("username")`; disabled controls are omitted from FormData, so registration and explicit login submit a null username and report `ユーザー名は2〜64文字で入力してください`.
4. A tab-local DevTools runtime shim made FormData preserve the passed form's username while the input was disabled. The shim disappeared on reload and did not modify deployed code or server-side validation.
5. Before a Google account was present, `navigator.credentials.create()` reached Android Credential Manager, offered cross-device creation, and later offered `This device` after the PIN was configured. Selecting it required Google Account sign-in, so the first ceremony was canceled.
6. After the test account was added, the create prompt explicitly offered to save the passkey to Google Password Manager for `[redacted-test-user-b]`.
7. Selecting Continue and satisfying the secure `BiometricPrompt` with the test PIN completed registration. The server redirected to `/account` and displayed `登録パスキー 1件`, the expected RP ID, and the expected origin.
8. After logout, the page entered `Autofill 待機中`. Focusing the username field opened Google Password Manager and displayed the saved `[redacted-test-user-b]` passkey.
9. Selecting that conditional candidate and satisfying the PIN completed `/api/login/verify` and returned to the authenticated `/account` page.
10. After another logout, explicit login was tested separately by supplying `[redacted-test-user-b]` and pressing `パスキーでログイン`. The flow invoked the FIDO authentication activity directly, accepted the PIN, and returned to the authenticated `/account` page.

## Result

- Ordinary WebAuthn create and server verification: **passed**.
- Ordinary WebAuthn get/login and server verification: **passed**.
- Conditional mediation candidate presentation: **passed**.
- Conditional mediation login and server verification: **passed**.
- Device-local passkey storage through Google Password Manager: **passed**.

The successful test user has one registered credential according to the application account page. The earlier options request likely left another redacted test user in the Railway store with zero credentials; this is inferred from server behavior and was not checked by directly reading production storage.

## Alternative explanations and limitations

- Chrome 133 and Play services 25.08 are old relative to the 2026-08-19 test date, and Chrome displayed an update-available indicator. The result proves this pinned configuration, not every current Chrome/Play-services combination.
- The exact source revision deployed to Railway was not exposed by the service. The deployed `/app.js` was fetched and directly confirmed to contain the FormData ordering bug, but its commit identity remains unknown.
- The test required a tab-local compatibility shim because of that deployed-site bug. The same flows should be rerun after deploying the source-order fix, without the shim.
- No second physical device was used to complete the cross-device QR flow.

## Next smallest experiment

1. Deploy the existing FormData ordering fix so each handler reads `username` before `setBusy(form, true)`.
2. Update Chrome and Google Play services through Play Store.
3. Repeat create, explicit get, and conditional get without a DevTools shim.
4. Remove test-only server records and the emulator test PIN/account when they are no longer needed.

## Cloud resources

- GCP resources created: none
- GCP resources removed: none
