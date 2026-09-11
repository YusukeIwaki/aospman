#!/usr/bin/env node
// Compare Chromium test-launcher JSON, without counting retries as extra tests.
// Usage: node compare-results.mjs /path/to/chromium-review-fixes-20260911
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = process.argv[2] ?? dirname(fileURLToPath(import.meta.url));
// Existing, source-verified assumptions at the pinned revision/configuration.
// These remain skipped, never counted as successful tests.
const expectedChromeSkips = new Set([
  'org.chromium.chrome.browser.touch_to_fill.TouchToFillPasswordManagerIntegrationTest#testConsumesGenericMotionEventsToPreventMouseClicksThroughSheet', // @DisableIf.Build(sdk_equals = 34).
  'org.chromium.chrome.browser.webauth.Fido2CredentialRequestTest#testMakeCredential_doesNotSetPaymentOptionsWhenNonPaymentCredential', // Requires !BuildConfig.ENABLE_ASSERTS.
]);
const additions = {
  'junit.json': [
    'testStartGetRequest_withoutBrowserBridge_success',
    'testStartGetRequest_withoutBrowserBridge_userCancel',
    'testCancelConditionalGetAssertion_withoutInitializedBrowserBridge_cleansUp',
    'testConditionalGetAssertion_cancelBeforePrefetchResponse_canStartNextRequest',
    'testConditionalGetAssertion_withoutBrowserBridge_passwordIsForwarded',
    'testConditionalMediation_webAuthnModeApp_notSupported',
    'testConditionalMediation_webAuthnModeBrowser_notSupported',
    'testConditionalGetCredential_webauthnModeBrowser_notImplemented',
  ],
  'native-api34.json': [
    'NavigationAllowsNewConditionalRequest',
    'SameDocumentNavigationKeepsRequest',
    'UncommittedNavigationKeepsRequest',
    'DeletedFrameDoesNotKeepPendingRequest',
    'NewConditionalRequestAfterCleanup',
    'PasswordFillingConsumesFillingCallback',
    'CredentialsReadyNotificationAfterCleanup',
  ],
  'webview-api34.json': [
    'testAppModeDoesNotSupportConditionalMediation',
    'testBrowserModeDoesNotSupportConditionalMediation',
  ],
  'webview-api33.json': [
    'testAppModeDoesNotSupportConditionalMediation',
    'testBrowserModeDoesNotSupportConditionalMediation',
  ],
  'chrome-api34.json': [],
};
const variantsPerAddedMethod = {
  'junit.json': 2, // Robolectric SDK 29 and SDK 36.
  'native-api34.json': 1,
  'webview-api34.json': 2, // Single-process and multiprocess.
  'webview-api33.json': 2,
};

function readRun(phase, file) {
  const report = JSON.parse(readFileSync(join(root, phase, file), 'utf8'));
  if (!Array.isArray(report.per_iteration_data)) {
    throw new Error(`${phase}/${file}: missing per_iteration_data`);
  }
  const tests = new Map();
  for (const iteration of report.per_iteration_data) {
    for (const [name, results] of Object.entries(iteration)) {
      tests.set(name, [...(tests.get(name) ?? []), ...results]);
    }
  }
  const skipped = [...tests].filter(([, results]) =>
    results.length === 1 && results[0].status === 'SKIPPED').map(([name]) => name).sort();
  const passedOnce = [...tests].filter(([, results]) =>
    results.length === 1 && results[0].status === 'SUCCESS').length;
  const nonPassing = [...tests].filter(([name, results]) =>
    results.length !== 1 || (results[0].status !== 'SUCCESS' &&
      !(file === 'chrome-api34.json' && expectedChromeSkips.has(name) &&
        results[0].status === 'SKIPPED')));
  return {
    tests,
    summary: {
      reported: tests.size,
      passedOnce,
      skipped,
      nonPassing: nonPassing.map(([name, results]) => ({
        name, statuses: results.map(result => result.status),
      })),
      disabledListedByJson: report.disabled_tests ?? [],
    },
  };
}

const summaries = [];
const errors = [];
for (const phase of ['control', 'treatment']) {
  for (const prefix of ['', 'chrome-']) {
    try {
      const code = readFileSync(join(root, phase, `${prefix}exit-code.txt`), 'utf8').trim();
      const finishedAt = readFileSync(join(root, phase, `${prefix}finished-at.txt`), 'utf8').trim();
      if (code !== '0' || !finishedAt) errors.push(`${phase}/${prefix}pipeline incomplete`);
    } catch (error) {
      errors.push(`${phase}/${prefix}pipeline: ${error.message}`);
    }
  }
}
for (const [file, methods] of Object.entries(additions)) {
  try {
    const control = readRun('control', file);
    const treatment = readRun('treatment', file);
    const removed = [...control.tests.keys()].filter(name => !treatment.tests.has(name));
    const added = [...treatment.tests.keys()].filter(name => !control.tests.has(name));
    const addedMethods = methods.map(method => {
      const pattern = new RegExp(`[.#]${method}(?:$|\\[|__)`);
      return { method, variants: added.filter(name => pattern.test(name)) };
    });
    if (!control.tests.size || !treatment.tests.size) errors.push(`${file}: empty run`);
    if (removed.length) errors.push(`${file}: existing tests disappeared`);
    if (control.summary.nonPassing.length || treatment.summary.nonPassing.length) {
      errors.push(`${file}: non-success or repeated result; inspect details`);
    }
    if (JSON.stringify(control.summary.skipped) !== JSON.stringify(treatment.summary.skipped)) {
      errors.push(`${file}: control/treatment skip sets differ`);
    }
    if (file === 'chrome-api34.json' &&
        JSON.stringify(control.summary.skipped) !== JSON.stringify([...expectedChromeSkips].sort())) {
      errors.push(`${file}: expected skip configuration changed; re-audit assumptions`);
    }
    for (const { method, variants } of addedMethods) {
      if (variants.length !== variantsPerAddedMethod[file]) {
        errors.push(`${file}: ${method}: expected ${variantsPerAddedMethod[file]} added variants, got ${variants.length}`);
      }
    }
    const expectedVariants = new Set(addedMethods.flatMap(item => item.variants));
    const unexpectedAdded = added.filter(name => !expectedVariants.has(name));
    if (unexpectedAdded.length) errors.push(`${file}: unaccounted-for added variants`);
    summaries.push({
      file, control: control.summary, treatment: treatment.summary,
      removed, addedMethods, unexpectedAdded,
    });
  } catch (error) {
    errors.push(`${file}: ${error.message}`);
  }
}
const cleanupDiagnostics = [];
const cleanupTest = 'org.chromium.chrome.browser.webauth.Fido2CredentialRequestTest#testGetAssertion_conditionalUiHybrid_success';
for (const phase of ['control', 'treatment', 'fixed']) {
  try {
    const report = JSON.parse(readFileSync(join(root, 'cleanup-diagnostic', `${phase}.json`), 'utf8'));
    const statuses = report.per_iteration_data.map(iteration => {
      if (Object.keys(iteration).length !== 1 || iteration[cleanupTest]?.length !== 1) {
        throw new Error(`${phase}: unexpected test names or retries`);
      }
      return iteration[cleanupTest][0].status;
    });
    const counts = statuses.reduce((result, status) => {
      result[status] = (result[status] ?? 0) + 1;
      return result;
    }, {});
    if (statuses.length !== 20) errors.push(`cleanup/${phase}: expected 20 planned iterations`);
    if (phase === 'fixed') {
      const code = readFileSync(join(root, 'cleanup-diagnostic', 'fixed-exit-code.txt'), 'utf8').trim();
      const finishedAt = readFileSync(join(root, 'cleanup-diagnostic', 'fixed-finished-at.txt'), 'utf8').trim();
      if (counts.SUCCESS !== 20 || code !== '0' || !finishedAt) {
        errors.push('cleanup/fixed: all 20 iterations must pass');
      }
    } else {
      if (statuses.some(status => !['SUCCESS', 'FAILURE'].includes(status))) {
        errors.push(`cleanup/${phase}: unexpected diagnostic status`);
      }
      if (phase === 'control' && !counts.FAILURE) {
        errors.push('cleanup/control: the reported baseline race was not reproduced');
      }
    }
    cleanupDiagnostics.push({ phase, counts });
  } catch (error) {
    errors.push(`cleanup/${phase}: ${error.message}`);
  }
}
console.log(JSON.stringify({ ok: errors.length === 0, errors, suites: summaries, cleanupDiagnostics }, null, 2));
process.exitCode = errors.length ? 1 : 0;
