// Read-only verification of the source export and approved Gerrit description.
// Usage: node verify-export.mjs /path/to/chromium-checkout
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const repo = resolve(root, '../..');
const chromium = process.argv[2];
if (!chromium) throw new Error('Supply a Chromium checkout containing PS5 and PS6.');
const base = '1a4f4dba744599726855e4b1ccb7c3f328cd7b01';
const ps5 = '4f984322475c16188601bf0a6e01a758fe65d26b';
const ps6 = 'a991e498fa0fef2028edd9b8f2dacf8a54c32235';
const tree = 'd2b4982a792fce53e0d09aabbb0c6d9761523fc0';
const git = (...args) => execFileSync('git', args, {cwd: chromium, maxBuffer: 8 * 1024 * 1024});
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const patch = readFileSync(join(repo, 'patches/chromium-webauthn-credman-bridge.patch'));
const description = readFileSync(join(repo, 'patches/chromium-webauthn-credman-bridge-description.txt'));
const checks = [], errors = [];
const check = (ok, name) => (ok ? checks : errors).push(name);
check(git('show', '-s', '--format=%P', ps6).toString().trim() === base, 'PS6 has the pinned parent');
for (const revision of [ps5, ps6]) {
  check(git('show', '-s', '--format=%T', revision).toString().trim() === tree, `${revision}: expected identical source tree`);
}
check(git('diff', '--binary', '--no-ext-diff', '--no-color', '--abbrev=10', base, ps6).equals(patch),
    'Exported patch is byte-identical to the PS6 source diff');
const commit = git('cat-file', 'commit', ps6).toString();
check(commit.slice(commit.indexOf('\n\n') + 2) === description.toString(),
    'Description is byte-identical to the PS6 commit message');
check(sha256(patch) === '9ada64624484a70dca42c29c7f2a91d36a23589a7254864b8ff0abf5edb8e6f3',
    'Patch matches the frozen Android validation input');

const url = 'https://chromium-review.googlesource.com/changes/8381617/detail?o=CURRENT_REVISION&o=CURRENT_COMMIT';
const response = await fetch(url, {signal: AbortSignal.timeout(30000)});
if (!response.ok) throw new Error(`Gerrit GET failed: ${response.status}`);
const detail = JSON.parse((await response.text()).replace(/^\)\]\}'\n/, ''));
check(detail.current_revision === ps6 && detail.revisions?.[ps6]?._number === 6,
    'Fresh Gerrit response identifies PS6 as current');
check(detail.work_in_progress === true && detail.status === 'NEW', 'Gerrit remains open and WIP');
check(detail.revisions?.[ps6]?.commit?.message === description.toString(),
    'Published Gerrit description matches the exported message');
console.log(JSON.stringify({ok: errors.length === 0, checkedAt: new Date().toISOString(),
  base, revision: ps6, tree, patchSha256: sha256(patch), descriptionSha256: sha256(description),
  checks, errors, note: 'Source-export identity checks only; not Android runtime validation.'}, null, 2));
process.exitCode = errors.length ? 1 : 0;
