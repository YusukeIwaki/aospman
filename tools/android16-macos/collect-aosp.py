#!/usr/bin/env python3
"""Collect the completed image from the single authorized AOSP build VM."""
import hashlib
import pathlib
import re
import subprocess
import sys
import time

vm, destination = sys.argv[1:]
if not re.fullmatch(r"aospman-android16-arm64-[a-z0-9-]+", vm):
    raise SystemExit("Unexpected AOSP build VM name")
out = pathlib.Path(destination).resolve()
out.mkdir(parents=True, exist_ok=True)
common = ["--project=aospman", "--zone=asia-northeast1-b"]
remote = "/work/export/aosp/"
required = {"android16-arm64-image.tar.gz", "integrated-webview.apk"}


def run(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


deadline = time.monotonic() + 8 * 60 * 60
while time.monotonic() < deadline:
    try:
        result = run(["gcloud", "compute", "ssh", vm, *common,
                      "--command=cat " + remote + "SHA256SUMS"])
        if result.returncode:
            if "not found" in result.stderr and "resource" in result.stderr:
                raise SystemExit("VM disappeared; inspect the lifecycle audit")
        else:
            hashes = {}
            for line in result.stdout.splitlines():
                fields = line.split()
                if (len(fields) == 2 and fields[1] in required
                        and re.fullmatch(r"[0-9a-f]{64}", fields[0])):
                    hashes[fields[1]] = fields[0]
            if hashes.keys() == required:
                for filename, expected in hashes.items():
                    final = out / filename
                    if final.exists():
                        if digest(final) != expected:
                            raise SystemExit("Existing artifact differs: " + filename)
                        continue
                    partial = out / (filename + ".part")
                    copy = run(["gcloud", "compute", "scp", *common,
                                vm + ":" + remote + filename, str(partial)], 1800)
                    if copy.returncode:
                        raise RuntimeError(copy.stderr.strip())
                    if digest(partial) != expected:
                        raise RuntimeError("Downloaded artifact hash differs: " + filename)
                    partial.replace(final)
                    print("SHA-256 verified: " + filename + " " + expected, flush=True)
                (out / "SHA256SUMS").write_text(result.stdout)
                print("Image and integrated APK are durable locally. Retrieve metadata and clean up the VM.", flush=True)
                break
    except (subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"Collection will retry: {error}", flush=True)
    time.sleep(30)
else:
    raise SystemExit("Collection deadline reached before image retrieval")
