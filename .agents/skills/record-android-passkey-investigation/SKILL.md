---
name: record-android-passkey-investigation
description: Create and maintain a durable, reproducible investigation record for every Android passkey, WebAuthn, Credential Manager, Autofill, WebView, browser, Chromium, or AOSP experiment. Use this alongside investigate-android-passkeys whenever a task observes, compares, builds, or changes passkey behavior, even when the user does not explicitly request a memo.
---

# Record Android Passkey Investigation

Keep the experiment record current while the investigation runs. The record is a required artifact, not an end-of-task reconstruction from memory.

## Start the record

1. Choose a stable directory such as `artifacts/<experiment-slug>/`.
2. Run:

   ```bash
   python3 .agents/skills/record-android-passkey-investigation/scripts/new_record.py \
     --output artifacts/<experiment-slug>/investigation.md \
     --title "<experiment title>" \
     --date YYYY-MM-DD \
     --hypothesis "<falsifiable hypothesis>"
   ```

3. If the record already exists, do not replace it. Read it and continue updating it.
4. Add evidence paths and configuration as soon as they become known. Do not wait for the final handoff.

## Record the experiment

Use `$investigate-android-passkeys` for the technical investigation and this skill for its durable record. Keep ordinary create/get, privileged-browser/provider approval, conditional mediation, and browser Autofill UI as separate cases.

Record all of the following:

- question, falsifiable hypothesis, control, treatment, and stopping condition;
- repository URL, exact commit/tag, file path, and symbol for relevant upstream or local source;
- UTC or local date with timezone, Android version/API, build fingerprint, ABI, emulator/device name;
- WebView/Chrome version, app package ID, version, signing certificate SHA-256, and relevant manifest permissions;
- Credential Manager/provider component and version, without account names or other personal identifiers;
- relying-party origin and RP ID;
- exact build, install, launch, and reproduction commands;
- observed UI, activity transitions, WebAuthn capability values, and targeted logcat excerpts;
- screenshots, UI hierarchy dumps, APKs, logs, hashes, and test reports by durable path;
- result for each control/treatment case, confidence, competing explanations, and remaining uncertainty;
- the smallest next experiment that could distinguish remaining explanations;
- GCP resources created/removed and final audit state, or an explicit statement that none were used.

Prefer exact error types and provider messages over the site's humanized toast. Redact test PINs, account identities, cookies, session values, credential IDs, challenges, and user handles from the memo and excerpts.

## Preserve evidence

- Store raw screenshots, UI XML, and relevant logcat under the experiment directory.
- Copy final APKs or images into the directory when they are needed to reproduce the result.
- Record SHA-256 hashes for final binaries and important derived artifacts.
- Preserve the full log separately from short quoted excerpts.
- Note any workaround used to bypass an unrelated test-harness defect; do not silently treat the workaround as normal product behavior.

## Finalize before handoff

Before declaring the task complete:

1. Replace every `TBD` that is material to the conclusion.
2. State whether the hypothesis was supported, falsified, or remains inconclusive.
3. Verify that control and treatment were run on comparable configurations and disclose any version drift.
4. Confirm that every cited artifact exists and every final binary hash matches.
5. Record tests that passed or failed and any warnings.
6. Record GCP cleanup status, even when it is `not used`.
7. Link the memo and the most useful evidence in the user handoff.

The task is not complete merely because the app builds or a UI error appears; the record must connect the observed behavior to a reproducible cause and explicitly mark uncertainty.
