#!/usr/bin/env python3
"""Tests for the runner's Google Drive layer, run against fake_drive.py (no network, no Minecraft).

Covers: small multipart uploads, 20 MB resumable uploads in 8 MiB chunks, resuming after a dropped
response, refreshing the access token after a 401, a revoked grant with a clear message, and atomic
downloads (no .part file is left behind and the target is complete).
"""

import hashlib
import importlib.util
import os
import random
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
from fake_drive import FakeDrive, serve  # noqa: E402

drive = FakeDrive()
server = serve(drive, "127.0.0.1", 0)
base = f"http://127.0.0.1:{server.server_address[1]}"
os.environ.update({
    "GDRIVE_CLIENT_ID": "test-client",
    "GDRIVE_REFRESH_TOKEN": "test-refresh",
    "VOXEL_DRIVE_API": f"{base}/drive/v3",
    "VOXEL_DRIVE_UPLOAD": f"{base}/upload/drive/v3",
    "VOXEL_TOKEN_URL": f"{base}/token",
    "VOXEL_DRIVE_FOLDER_ID": "root",
    "VOXEL_WORKDIR": tempfile.mkdtemp(prefix="voxelops-unit-"),
})
spec = importlib.util.spec_from_file_location("voxelops_runner", REPO / "assets" / "runtime" / "voxelops_runner.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)  # the runner only starts when executed as a script


def check(condition, message):
    if not condition:
        print(f"FAIL: {message}")
        server.shutdown()
        raise SystemExit(1)
    print(f"ok: {message}")


def md5(data):
    return hashlib.md5(data).hexdigest()


def files_named(parent, name):
    return [e for e in drive.children(parent) if e["name"] == name]


client = runner.Drive()
folder = drive.create_folder("root", "NovaCraft")

# 1. Small upload (multipart) and its verification.
small = b"voxelops small file\n"
result = client.write_bytes(folder, "small.txt", small, "text/plain")
check(drive.read(drive.find(folder, "small.txt")) == small, "small file uploaded")
check(result.get("md5Checksum") == md5(small), "small upload returns the Drive md5 for verification")

# 2. Large upload (20 MB > 8 MiB chunk size) through the resumable protocol.
big = random.Random(7).randbytes(20 * 1024 * 1024)
big_path = Path(runner.TMP) / "big.bin"
big_path.write_bytes(big)
client.write_path(folder, "big.bin", str(big_path), "application/zip")
check(drive.read(drive.find(folder, "big.bin")) == big, "20 MB resumable upload stored byte for byte")

# 3. A chunk is stored but its response is lost: the runner must ask Drive where it stopped and resume.
drive.fail_put_after_store = True
client.write_path(folder, "resumed.bin", str(big_path), "application/zip")
copies = files_named(folder, "resumed.bin")
check(len(copies) == 1 and drive.read(copies[0]["id"]) == big, "resumed upload finishes with exactly one correct copy")

# 4. Access token expires during a run: one 401 refreshes the token and the call succeeds.
drive.expire_token_once = True
names = [e["name"] for e in client.list_children(folder)]
check("big.bin" in names, "401 from Drive refreshes the access token and the call is retried")

# 5. Revoked grant: a clear reconnect message instead of a raw HTTP error.
client._token = None
drive.revoked = True
try:
    client._access()
    check(False, "revoked grant must raise")
except RuntimeError as error:
    check("Reconnect Google Drive" in str(error), "revoked grant reports a friendly reconnect message")
finally:
    drive.revoked = False

# 6. Atomic download: complete file, no leftover .part file.
target = Path(runner.TMP) / "downloaded.bin"
client.download_to(drive.find(folder, "big.bin"), str(target))
check(target.read_bytes() == big and not Path(str(target) + ".part").exists(), "download is complete and atomic")

# 7. Backup of a stopped server: a zip with the world and server.properties, uploaded and verified.
import io  # noqa: E402
import zipfile  # noqa: E402

runner_obj = runner.Runner()
runner_obj.ensure_folders()
root = Path(runner.ROOT)
(root / "world").mkdir(parents=True, exist_ok=True)
(root / "world" / "level.dat").write_bytes(b"level-bytes")
(root / "server.properties").write_text("motd=test\n", encoding="utf-8")
runner_obj.make_backup("manual")
backups = [e for e in drive.children(runner_obj.backups) if e["name"].startswith("manual-")]
check(len(backups) == 1, "manual backup uploaded to backups/")
archive = zipfile.ZipFile(io.BytesIO(drive.read(backups[0]["id"])))
check(archive.read("world/level.dat") == b"level-bytes" and "server.properties" in archive.namelist(),
      "backup archive contains the world and server.properties")

server.shutdown()
print("ALL DRIVE LAYER TESTS PASSED")
