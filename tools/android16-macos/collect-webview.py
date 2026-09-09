#!/usr/bin/env python3
"""One-shot artifact collection for the currently running, authorized build."""
import hashlib
import pathlib
import re
import subprocess
import sys
import time


vm, destination = sys.argv[1:]
if not re.fullmatch(r"aospman-webview-arm64-[a-z0-9-]+", vm):
    raise SystemExit("Unexpected build VM name")
out = pathlib.Path(destination).resolve()
out.mkdir(parents=True, exist_ok=True)
common = ["--project=aospman", "--zone=asia-northeast1-b"]
remote = "/work/export/webview/"


def run(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def collect(filename, expected):
    final = out / filename
    if final.exists():
        if digest(final) != expected:
            raise RuntimeError(f"Existing artifact differs: {filename}")
        return
    partial = out / (filename + ".part")
    result = run(["gcloud", "compute", "scp", *common,
                  vm + ":" + remote + filename, str(partial)], timeout=600)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    if digest(partial) != expected:
        raise RuntimeError(f"Downloaded artifact hash differs: {filename}")
    partial.replace(final)
    print(f"SHA-256 verified: {filename} {expected}", flush=True)


deadline = time.monotonic() + 8 * 60 * 60
done = set()
while time.monotonic() < deadline and len(done) < 2:
    for filename, hashfile in [
        ("control-SystemWebView64.apk", "control.sha256"),
        ("treatment-SystemWebView64.apk", "SHA256SUMS"),
    ]:
        if filename in done:
            continue
        try:
            # The build publishes the checksum only after copying the complete APK.
            result = run(["gcloud", "compute", "ssh", vm, *common,
                          "--command=cat " + remote + hashfile])
            if result.returncode:
                if "not found" in result.stderr and "resource" in result.stderr:
                    raise SystemExit("VM disappeared; inspect the lifecycle audit")
                continue
            for line in result.stdout.splitlines():
                fields = line.split()
                if (len(fields) == 2 and fields[1].removeprefix("./") == filename
                        and re.fullmatch(r"[0-9a-f]{64}", fields[0])):
                    collect(filename, fields[0])
                    (out / (filename + ".sha256")).write_text(
                        fields[0] + "  " + filename + "\n")
                    done.add(filename)
                    break
        except (subprocess.TimeoutExpired, RuntimeError) as error:
            print(f"Collection will retry: {error}", flush=True)
    if len(done) < 2:
        time.sleep(30)
if len(done) != 2:
    raise SystemExit("Collection deadline reached before both APKs were retrieved")
print("Both APKs are durable locally. VM cleanup is left to the build operator.", flush=True)
