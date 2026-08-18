# Passkey Test Lab working agreement

This file is the canonical handoff for the web application in this directory. It supplements the parent `../AGENTS.md`; for work confined to this app, use this file as the application specification.

## Purpose and current production target

- This is a deliberately small Japanese test site for passkey creation, ordinary WebAuthn login, passkey autofill/Conditional UI, logout, and an authenticated page.
- Production URL and WebAuthn origin: `https://passkey-test-lab-production.up.railway.app`.
- Production RP ID: `passkey-test-lab-production.up.railway.app`.
- Do not use real email addresses, secrets, or personally identifying data as test usernames.

## Runtime and dependencies

- Use rbenv Ruby `4.0.0`; `.ruby-version`, `Gemfile`, `Gemfile.lock`, and both Docker stages must stay on Ruby 4.0.0 unless the user explicitly requests an upgrade.
- The shell used by Codex may not initialize rbenv shims. Run Ruby, Bundler, and tests with `rbenv exec` and confirm `rbenv exec ruby -v` before diagnosing version-related failures.
- The application is Sinatra + Puma + `webauthn-ruby`. The current lockfile resolves Sinatra 4.2.1, Puma 7.2.1, and WebAuthn 3.4.3. Do not upgrade them incidentally.
- Puma runs a single process (`workers 0`) with 1–3 threads. Production sets `PUMA_MAX_THREADS=3`.
- Static assets are local. Do not add telemetry, remote fonts, analytics, polling, or other idle outbound traffic; the service is intended to sleep in Railway Serverless mode.

## Source map

- `app.rb`: Sinatra configuration, secure cookie session, WebAuthn configuration, HTML routes, and JSON API routes.
- `lib/passkey_store.rb`: file-backed user and credential store with file locking and atomic rename.
- `public/app.js`: WebAuthn binary/JSON conversion, registration, explicit login, Conditional Mediation, tabs, and UI status.
- `public/styles.css`: responsive UI; no external design dependencies.
- `views/index.erb`: registration/login test page.
- `views/account.erb`: authenticated page and logout control.
- `test/app_test.rb`: Rack tests and an end-to-end cryptographic ceremony using `WebAuthn::FakeClient`.
- `Dockerfile`: deterministic Ruby 4.0.0 multi-stage production image. OpenSSL build headers are required for Ruby 4's OpenSSL gem.
- `railway.toml`: Docker build, start command, restart policy, and `/health` check.

## HTTP contract

- `GET /`: unauthenticated registration/login page; redirects authenticated sessions to `/account`.
- `GET /account`: authenticated-only page.
- `POST /logout`: clears the session and redirects to `/`.
- `GET /health`: Railway health endpoint returning `{"status":"ok"}`.
- `POST /api/register/options` and `/api/register/verify`: registration ceremony.
- `POST /api/login/options` and `/api/login/verify`: authentication ceremony. An empty username intentionally starts usernameless authentication for autofill.
- JSON API requests require `Content-Type: application/json`; keep API errors as JSON.

## WebAuthn invariants

Do not weaken these to make a test pass:

- Production must use HTTPS, and `WEBAUTHN_ORIGIN` and `WEBAUTHN_RP_ID` must exactly match the Railway domain above.
- Registration requests `resident_key: "required"`, `user_verification: "required"`, and `attestation: "none"`. The resident credential is required for usernameless passkey login and autofill.
- Authentication requests `user_verification: "required"`.
- Usernameless login deliberately has an empty `allowCredentials` list. Resolve the account from the returned credential ID and validate the returned user handle.
- Keep challenge verification, origin/RP ID verification, public-key signature verification, sign-counter persistence, and user-handle matching intact.
- Challenges live in the signed session and are cleared after verification or a WebAuthn error.
- The login input must retain `autocomplete="username webauthn"`.
- Keep Conditional Mediation feature detection and its abort behavior when explicit login or registration starts.
- Preserve the manual ArrayBuffer/base64url conversion code unless verified target WebViews all support the newer parsing/serialization helpers.
- Ordinary WebAuthn and Conditional UI are separate capabilities. A browser may pass explicit login while reporting autofill unsupported; do not treat that result as a server failure.

## Persistence and scaling constraint

- Production stores data at `PASSKEY_STORE_PATH=/data/passkeys.json` on the attached Railway Volume.
- Local development defaults to `data/passkeys.json`, which is gitignored.
- The JSON store is acceptable only for this low-traffic, one-replica test service. Keep Railway at one replica. Before adding replicas or multiple writers, replace it with a transactional database and migration plan.
- Preserve file locking, global credential-ID uniqueness, atomic writes, public-key encoding, and sign-count updates in `PasskeyStore`.
- Do not delete or reset production passkey data unless the user explicitly asks. Empty users can be created when registration options are requested, so avoid production registration calls in automated smoke tests.

## Railway inventory and required settings

- Project: `aospman` (`750917fb-e11b-4433-af35-44a732905f0f`).
- Environment: `production` (`cf5c1656-ae34-4230-bbb3-a9624c8c0aaf`).
- Service: `passkey-test-lab` (`03eb36e8-5749-4814-9ca5-b3ec7ca70418`).
- Volume: `passkey-test-lab-volume` (`64e8eb24-f47c-422c-bfed-a3360360e4bc`), mounted at `/data`.
- Keep exactly one application service. Do not create another service, database, domain, or volume without explicit user authorization.
- Required resource settings: Serverless enabled, 1 replica, CPU limit `0.5`, memory limit `500000000` bytes (Railway's 0.5 GB setting).
- Required environment variable names: `RACK_ENV`, `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `PASSKEY_STORE_PATH`, `PUMA_MAX_THREADS`, and secret `SESSION_SECRET`. Never print, read back, commit, or replace the session secret without need.
- Deployments are external mutations. Do not deploy merely because local code changed; deploy only when the user asks for it.
- When deployment is authorized, run Railway CLI commands from this directory, confirm the linked project/service first, and use `railway up --ci --message "..."`. Do not create a new service as a fallback for a link or deployment problem.
- After an authorized deployment or settings change, confirm `latestDeployment.status == "SUCCESS"`, `sleepApplication == true`, CPU/memory limits, one replica, `/data` in `volumeMounts`, and a 200 response from `/health`.

## Development and verification workflow

Run the smallest relevant checks, but always run the full WebAuthn test before handing off an authentication change:

```sh
rbenv exec ruby -v
rbenv exec bundle install
rbenv exec bundle exec ruby -Itest test/app_test.rb
node --check public/app.js
```

- The full test must continue to cover registration verification, authenticated-page access, logout, and authentication verification with the same fake authenticator—not only option JSON shape.
- For Docker/runtime changes, also run `docker build -t passkey-test-lab:ruby-4.0 .`, start a disposable container, verify `/health`, verify the container reports Ruby 4.0.0, then stop it.
- For production smoke tests, use `/health`, `GET /`, and usernameless `/api/login/options`. Do not synthesize a production registration unless the user asked for test data.
- For UI changes, check both login and registration panels at a narrow and a wide viewport and inspect browser console errors.
- A real passkey picker, biometric prompt, Credential Manager provider, and autofill UI require testing on the target browser/device. Use the parent passkey investigation skill and adb UI debugger when that device-level evidence is requested.

## Change discipline

- Keep the site simple, Japanese, mobile-friendly, and usable in custom Android browsers.
- Preserve unrelated local edits and the persistent data model.
- Add focused regression tests for fixes and security-sensitive behavior.
- If routes, files, runtime versions, production identifiers, persistence, resource limits, or deployment procedure change, update this `AGENTS.md` in the same change so it remains the canonical handoff.
