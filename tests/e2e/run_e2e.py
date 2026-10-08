#!/usr/bin/env python3
"""End-to-end test of the VoxelOps runner on a GitHub-hosted runner.

What is real: the runner script, Java, Minecraft Server (downloaded from Mojang), the command queue,
status and console files, zip backups, the restore path and the process lifecycle.
What is replaced: Google Drive's HTTP API, served by fake_drive.py on localhost (test only).

Scenario
1. Seed a server folder (metadata, server.properties, eula, runtime settings).
2. Start the runner. Wait for "running". Send a console command. Wait for a player list.
3. Queue "backup" -> a manual zip with world/level.dat must appear in Drive.
4. Queue "stop" -> Minecraft saves, backs up, stops; status offline; world uploaded; run log uploaded.
5. Start a fresh runner (empty machine). It must download the world from Drive before starting.
6. Queue "restore" with the manual backup -> pre-restore backup created, world replaced, server running.
7. Queue "stop" -> clean exit.
"""

import io
import json
import os
import random
import shutil
import socket
import subprocess
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from fake_drive import FakeDrive, serve  # noqa: E402

REPO = HERE.parents[1]
RUNNER = REPO / "assets" / "runtime" / "voxelops_runner.py"
WORK = Path(os.environ.get("RUNNER_TEMP") or "/tmp") / "voxelops-e2e"
RESULTS = {}
# A marker file inside the world. Minecraft rewrites level.dat on every start, so byte-for-byte comparison
# of level.dat is not a valid check on a live server; the marker proves which world content was restored.
MARKER = "voxelops-marker.txt"


def notice(message):
    print(f"::notice title=e2e::{message}", flush=True)


def fail(message):
    print(f"::error title=e2e::{message}", flush=True)
    raise SystemExit(1)


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(predicate, timeout, label, interval=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    fail(f"timed out waiting for {label}")


class Harness:
    def __init__(self, drive, folder_id):
        self.drive = drive
        self.folder = folder_id

    def child(self, parent, name):
        found = self.drive.find(parent, name)
        if not found:
            raise KeyError(name)
        return found

    def system_control(self):
        system = self.child(self.folder, "_voxelops")
        return self.child(system, "control")

    def status(self):
        try:
            return json.loads(self.drive.read(self.child(self.system_control(), "status.json")).decode())
        except KeyError:
            return {}

    def live_log(self):
        try:
            return self.drive.read(self.child(self.system_control(), "live.log")).decode(errors="replace")
        except KeyError:
            return ""

    def queue(self, kind, payload=None):
        system = self.child(self.folder, "_voxelops")
        control = self.child(system, "control")
        commands = self.child(control, "commands")
        name = f"{time.time_ns()}-{random.randrange(36 ** 4):04x}.json"
        body = json.dumps({"type": kind, "requestedAt": time.time(), "payload": payload or {}}).encode()
        self.drive.put_file(commands, name, body, "application/json")

    def folder_files(self, path):
        current = self.folder
        for part in path:
            current = self.child(current, part)
        return [e for e in self.drive.children(current)]

    def backup(self, prefix):
        try:
            backups = self.child(self.folder, "backups")
        except KeyError:
            return None
        for entry in self.drive.children(backups):
            if entry["name"].startswith(prefix) and entry["name"].endswith(".zip"):
                return entry
        return None


def start_runner(env, log_path):
    handle = open(log_path, "a", encoding="utf-8")
    return subprocess.Popen([sys.executable, str(RUNNER)], env=env, stdout=handle, stderr=subprocess.STDOUT)


def count_in(path, needle):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").count(needle)
    except FileNotFoundError:
        return 0


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    drive = FakeDrive()
    port = free_port()
    serve(drive, "127.0.0.1", port)
    base = f"http://127.0.0.1:{port}"

    storage = drive.create_folder("root", "Minecraft Servers")
    folder = drive.create_folder(storage, "NovaCraft")
    drive.put_file(folder, "metadata.json", json.dumps({
        "schema": 1, "name": "NovaCraft", "software": "vanilla", "minecraftVersion": "1.21.4",
        "javaMajor": 21, "githubRepo": "e2e/e2e",
    }).encode(), "application/json")
    drive.put_file(folder, "server.properties",
                   b"online-mode=false\nserver-port=25565\nlevel-name=world\nmax-players=5\nmotd=VoxelOps E2E\n",
                   "text/plain")
    drive.put_file(folder, "eula.txt", b"eula=true\n", "text/plain")
    system = drive.create_folder(folder, "_voxelops")
    control = drive.create_folder(system, "control")
    drive.create_folder(control, "commands")
    drive.put_file(control, "runtime.json", json.dumps({
        "memoryMb": 1536, "syncIntervalMinutes": 1, "backupIntervalMinutes": 0,
        "backupRetention": 3, "autoContinue": False,
    }).encode(), "application/json")
    harness = Harness(drive, folder)

    env = dict(os.environ)
    env.update({
        "VOXEL_DRIVE_FOLDER_ID": folder, "GDRIVE_CLIENT_ID": "e2e-client", "GDRIVE_REFRESH_TOKEN": "e2e-refresh",
        "VOXEL_DRIVE_API": f"{base}/drive/v3", "VOXEL_DRIVE_UPLOAD": f"{base}/upload/drive/v3",
        "VOXEL_TOKEN_URL": f"{base}/token", "VOXEL_SOFTWARE": "vanilla", "VOXEL_MC_VERSION": "1.21.4",
        "VOXEL_SERVER_NAME": "NovaCraft", "VOXEL_RUN_LIMIT_MINUTES": "90", "VOXEL_WORKDIR": str(WORK / "minecraft"),
        "VOXEL_TAILSCALE_ENABLED": "false", "GITHUB_RUN_ID": "e2e-run-1",
    })
    log_one = WORK / "runner-1.log"
    log_two = WORK / "runner-2.log"

    # 1-2. First run: start, reach running, console and player list.
    proc = start_runner(env, log_one)
    wait_for(lambda: harness.status().get("state") == "running", 900, "server running (first run)")
    notice("first run reached running state")
    harness.queue("console", {"text": "say voxelops-e2e"})
    wait_for(lambda: "voxelops-e2e" in harness.live_log(), 240, "console output")
    wait_for(lambda: "players online" in harness.live_log(), 240, "player list from the server")
    RESULTS["console_and_players"] = True
    (WORK / "minecraft" / "world" / MARKER).write_text("marker-A", encoding="utf-8")

    # 3. Manual backup must be uploaded and contain the world.
    harness.queue("backup")
    manual = wait_for(lambda: harness.backup("manual-"), 420, "manual backup in Drive")
    archive = zipfile.ZipFile(io.BytesIO(drive.read(manual["id"])))
    names = archive.namelist()
    if "world/level.dat" not in names:
        fail(f"manual backup has no world/level.dat: {names[:5]}")
    if f"world/{MARKER}" not in names or archive.read(f"world/{MARKER}").decode() != "marker-A":
        fail("manual backup does not contain the marker that was written before the backup")
    RESULTS["manual_backup_entries"] = len(names)
    notice(f"manual backup uploaded with {len(names)} entries")

    # 4. Stop: save, backup, stop, upload.
    harness.queue("stop")
    wait_for(lambda: proc.poll() is not None, 900, "runner exit after stop")
    if proc.returncode not in (0, None):
        fail(f"runner exited with {proc.returncode} after stop")
    status = harness.status()
    if status.get("state") != "offline":
        fail(f"status after stop is {status.get('state')}, expected offline")
    world_files = [e["name"] for e in harness.folder_files(["world"])]
    if "level.dat" not in world_files:
        fail(f"world/level.dat is missing in Drive after stop: {world_files[:8]}")
    if harness.backup("auto-") is None:
        fail("no automatic backup was created when the server stopped")
    if not any(e["name"].startswith("run-") for e in harness.drive.children(harness.child(system, "logs"))):
        fail("the run log was not uploaded")
    RESULTS["stop_saved_and_uploaded"] = True
    notice("first run stopped cleanly; world, backup and run log are in Drive")

    # 5. Second run on an empty machine: the world must come from Drive.
    shutil.rmtree(WORK / "minecraft", ignore_errors=True)
    env["GITHUB_RUN_ID"] = "e2e-run-2"
    proc = start_runner(env, log_two)
    wait_for(lambda: (WORK / "minecraft" / "world" / "level.dat").exists(), 300, "world downloaded from Drive")
    wait_for(lambda: harness.status().get("state") == "running", 900, "server running (second run)")
    pulled_marker = WORK / "minecraft" / "world" / MARKER
    if not pulled_marker.exists() or pulled_marker.read_text(encoding="utf-8") != "marker-A":
        fail("the second run did not pull the marker from Drive")
    RESULTS["world_pulled_from_drive"] = True
    # Make the local world differ from the backup so the restore has something to prove.
    pulled_marker.write_text("marker-B", encoding="utf-8")
    notice("second run pulled the world from Drive and reached running state")

    # 6. Restore the manual backup.
    harness.queue("restore", {"fileId": manual["id"], "name": manual["name"]})
    wait_for(lambda: harness.backup("prerestore-"), 600, "pre-restore backup")
    wait_for(lambda: count_in(log_two, "Starting Minecraft:") >= 2, 600, "server restarted after restore")
    wait_for(lambda: harness.status().get("state") == "running", 900, "server running after restore")
    restored = (WORK / "minecraft" / "world" / MARKER)
    restored_text = restored.read_text(encoding="utf-8") if restored.exists() else ""
    if restored_text != "marker-A":
        fail(f"restored world does not match the backup (marker is {restored_text!r}, expected 'marker-A')")
    if not (WORK / "minecraft" / "world" / "level.dat").exists():
        fail("restored world has no level.dat")
    RESULTS["restore_matches_backup"] = True
    notice("restore created a pre-restore backup and the server runs the restored world")

    # 7. Final stop.
    harness.queue("stop")
    wait_for(lambda: proc.poll() is not None, 900, "runner exit after final stop")
    RESULTS["final_exit_code"] = proc.returncode
    notice("E2E RESULTS " + json.dumps(RESULTS, sort_keys=True))
    print(json.dumps(RESULTS, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as error:  # report the unexpected failure and show the runner tail
        print(f"::error title=e2e::{type(error).__name__}: {error}", flush=True)
        for name in ("runner-1.log", "runner-2.log"):
            path = WORK / name
            if path.exists():
                tail = path.read_text(encoding="utf-8", errors="replace").splitlines()[-60:]
                print(f"---- {name} (last lines) ----")
                print("\n".join(tail))
        raise SystemExit(1)
