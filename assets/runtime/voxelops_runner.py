#!/usr/bin/env python3
"""VoxelOps runner (GitHub-hosted runner, Python standard library only).

The runner executes one Minecraft server inside a GitHub Actions job. Google Drive is the source of
truth:

* On start it pulls the server folder from Drive (atomic downloads, md5 verified).
* While running it saves the world and uploads changed files on a timer.
* Before a stop or restart it saves, uploads, creates a backup, stops Minecraft and uploads again.
* It never deletes Drive files during a normal sync. Deletions happen only for an explicit restore,
  and only after the restored world has been uploaded and verified.
* Commands from the app arrive as small JSON files in _voxelops/control/commands.

This file is generated and committed by VoxelOps. Local edits are overwritten on the next refresh.
"""

import collections
import glob
import hashlib
import json
import os
import random
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone

UA = "VoxelOps-Runner/1.1 (+https://github.com/abiedadam0077/Min2)"
DRIVE = os.environ.get("VOXEL_DRIVE_API", "https://www.googleapis.com/drive/v3").rstrip("/")
UPLOAD = os.environ.get("VOXEL_DRIVE_UPLOAD", "https://www.googleapis.com/upload/drive/v3").rstrip("/")
TOKEN_URL = os.environ.get("VOXEL_TOKEN_URL", "https://oauth2.googleapis.com/token")
FOLDER_MIME = "application/vnd.google-apps.folder"
CHUNK = 8 * 1024 * 1024
MULTIPART_LIMIT = 4 * 1024 * 1024
SYSTEM_DIR = "_voxelops"
WORLD_DIRS = ["world", "world_nether", "world_the_end"]
SYNC_DIRS = WORLD_DIRS + ["mods", "plugins", "config"]
TOP_FILES = ["server.properties", "eula.txt", "server-icon.png"]
ROOT = os.path.abspath(os.environ.get("VOXEL_WORKDIR", "minecraft"))
TMP = tempfile.mkdtemp(prefix="voxelops-")
LOG_LINES = collections.deque(maxlen=400)
LOG_LOCK = threading.Lock()
IP_PATTERN = re.compile(r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def redact(text):
    """Player IP addresses must not appear in public Actions logs."""
    return IP_PATTERN.sub("[ip]", text)


def log(message):
    line = f"[{datetime.now(timezone.utc).strftime('%H:%M:%S')}] {redact(str(message))}"
    print(line, flush=True)
    with LOG_LOCK:
        LOG_LINES.append(line)


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        raise SystemExit(f"Missing required environment variable {name}")
    return value


class HttpError(Exception):
    def __init__(self, status, body=b""):
        super().__init__(f"HTTP {status}")
        self.status = status
        self.body = body


def http(method, url, data=None, headers=None, timeout=120, stream_to=None):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("User-Agent", UA)
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if stream_to:
                tmp_path = stream_to + ".part"
                os.makedirs(os.path.dirname(stream_to) or ".", exist_ok=True)
                with open(tmp_path, "wb") as fh:
                    shutil.copyfileobj(resp, fh, CHUNK)
                os.replace(tmp_path, stream_to)
                return resp.status, dict(resp.headers), b""
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as err:
        if err.code == 308:
            # "Resume Incomplete" is part of the resumable upload protocol, not a redirect.
            return 308, dict(err.headers), err.read()
        raise HttpError(err.code, err.read()[:2000]) from None


def retry(fn, attempts=5):
    delay = 2
    for attempt in range(1, attempts + 1):
        try:
            return fn()
        except HttpError as err:
            if err.status in (429, 500, 502, 503, 504) and attempt < attempts:
                time.sleep(delay)
                delay = min(delay * 2, 60)
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt < attempts:
                time.sleep(delay)
                delay = min(delay * 2, 60)
                continue
            raise


def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


class Drive:
    """Minimal Google Drive v3 client: listing, folders, downloads, multipart and resumable uploads."""

    def __init__(self):
        self.client_id = env("GDRIVE_CLIENT_ID", required=True)
        self.refresh_token = env("GDRIVE_REFRESH_TOKEN", required=True)
        self._token = None
        self._expires = 0.0

    def _access(self, force=False):
        if self._token and not force and time.time() < self._expires - 60:
            return self._token
        body = urllib.parse.urlencode({
            "client_id": self.client_id,
            "refresh_token": self.refresh_token,
            "grant_type": "refresh_token",
        }).encode()
        _, _, raw = retry(lambda: http("POST", TOKEN_URL, data=body,
                                       headers={"Content-Type": "application/x-www-form-urlencoded"}))
        payload = json.loads(raw.decode())
        self._token = payload["access_token"]
        self._expires = time.time() + int(payload.get("expires_in", 3000))
        return self._token

    def _auth(self, extra=None):
        headers = {"Authorization": f"Bearer {self._access()}"}
        headers.update(extra or {})
        return headers

    def json_call(self, method, url, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        headers = self._auth({"Content-Type": "application/json; charset=UTF-8"} if data else {})
        _, _, raw = retry(lambda: http(method, url, data=data, headers=headers))
        return json.loads(raw.decode()) if raw else {}

    @staticmethod
    def _q(value):
        return value.replace("\\", "\\\\").replace("'", "\\'")

    def list_children(self, parent, folders=None):
        results, token = [], None
        while True:
            clauses = [f"'{self._q(parent)}' in parents", "trashed = false"]
            if folders is True:
                clauses.append(f"mimeType = '{FOLDER_MIME}'")
            elif folders is False:
                clauses.append(f"mimeType != '{FOLDER_MIME}'")
            params = {"q": " and ".join(clauses), "pageSize": "1000",
                      "fields": "nextPageToken,files(id,name,mimeType,md5Checksum,size,modifiedTime)"}
            if token:
                params["pageToken"] = token
            payload = self.json_call("GET", f"{DRIVE}/files?{urllib.parse.urlencode(params)}")
            results.extend(payload.get("files", []))
            token = payload.get("nextPageToken")
            if not token:
                return results

    def find(self, parent, name, folder=None):
        clauses = [f"'{self._q(parent)}' in parents", f"name = '{self._q(name)}'", "trashed = false"]
        if folder is True:
            clauses.append(f"mimeType = '{FOLDER_MIME}'")
        params = {"q": " and ".join(clauses), "pageSize": "5",
                  "fields": "files(id,name,mimeType,md5Checksum,size,modifiedTime)"}
        files = self.json_call("GET", f"{DRIVE}/files?{urllib.parse.urlencode(params)}").get("files", [])
        return files[0] if files else None

    def ensure_folder(self, parent, name):
        found = self.find(parent, name, folder=True)
        if found:
            return found["id"]
        created = self.json_call("POST", f"{DRIVE}/files?fields=id",
                                 {"name": name, "mimeType": FOLDER_MIME, "parents": [parent]})
        return created["id"]

    def download_to(self, file_id, path):
        url = f"{DRIVE}/files/{file_id}?alt=media"
        retry(lambda: http("GET", url, headers=self._auth(), timeout=900, stream_to=path))

    def download_bytes(self, file_id):
        url = f"{DRIVE}/files/{file_id}?alt=media"
        _, _, raw = retry(lambda: http("GET", url, headers=self._auth(), timeout=300))
        return raw

    def read_json(self, parent, name):
        found = self.find(parent, name)
        if not found:
            return None
        try:
            return json.loads(self.download_bytes(found["id"]).decode())
        except (ValueError, HttpError):
            return None

    def write_bytes(self, parent, name, data, mime, file_id=None):
        if isinstance(data, str):
            data = data.encode()
        if file_id is None:
            existing = self.find(parent, name)
            file_id = existing["id"] if existing else None
        if len(data) <= MULTIPART_LIMIT:
            return self._simple_write(parent, name, data, mime, file_id)
        return self._resumable(parent, name, mime, file_id, len(data), lambda s, e: data[s:e])

    def write_path(self, parent, name, path, mime, file_id=None):
        size = os.path.getsize(path)
        if file_id is None:
            existing = self.find(parent, name)
            file_id = existing["id"] if existing else None
        if size <= MULTIPART_LIMIT:
            with open(path, "rb") as fh:
                return self._simple_write(parent, name, fh.read(), mime, file_id)

        def reader(start, end):
            with open(path, "rb") as fh:
                fh.seek(start)
                return fh.read(end - start)
        return self._resumable(parent, name, mime, file_id, size, reader)

    def _simple_write(self, parent, name, data, mime, file_id):
        if file_id:
            url = f"{UPLOAD}/files/{file_id}?uploadType=media&fields=id,md5Checksum"
            _, _, raw = retry(lambda: http("PATCH", url, data=data,
                                           headers=self._auth({"Content-Type": mime}), timeout=300))
            return json.loads(raw.decode())
        boundary = "voxelops" + str(random.randrange(10 ** 12))
        meta = json.dumps({"name": name, "parents": [parent], "mimeType": mime}).encode()
        body = b"".join([
            f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode(), meta,
            f"\r\n--{boundary}\r\nContent-Type: {mime}\r\n\r\n".encode(), data,
            f"\r\n--{boundary}--".encode(),
        ])
        url = f"{UPLOAD}/files?uploadType=multipart&fields=id,md5Checksum"
        headers = self._auth({"Content-Type": f"multipart/related; boundary={boundary}"})
        _, _, raw = retry(lambda: http("POST", url, data=body, headers=headers, timeout=300))
        return json.loads(raw.decode())

    def _resumable(self, parent, name, mime, file_id, total, read_chunk):
        if file_id:
            url = f"{UPLOAD}/files/{file_id}?uploadType=resumable&fields=id,md5Checksum"
            method, meta = "PATCH", b"{}"
        else:
            url = f"{UPLOAD}/files?uploadType=resumable&fields=id,md5Checksum"
            method = "POST"
            meta = json.dumps({"name": name, "parents": [parent], "mimeType": mime}).encode()
        headers = self._auth({"Content-Type": "application/json; charset=UTF-8",
                              "X-Upload-Content-Type": mime, "X-Upload-Content-Length": str(total)})
        req = urllib.request.Request(url, data=meta, method=method)
        req.add_header("User-Agent", UA)
        for key, value in headers.items():
            req.add_header(key, value)
        with urllib.request.urlopen(req, timeout=120) as resp:
            location = resp.headers.get("Location")
        if not location:
            raise RuntimeError("Drive did not return a resumable upload session")
        offset = 0
        while True:
            end = min(offset + CHUNK, total)
            chunk = read_chunk(offset, end) if total else b""
            range_header = f"bytes {offset}-{end - 1}/{total}" if total else "bytes */0"
            try:
                status, hdrs, raw = http("PUT", location, data=chunk,
                                         headers={"Content-Range": range_header, "Content-Type": mime},
                                         timeout=600)
            except HttpError as err:
                if err.status in (429, 500, 502, 503, 504):
                    time.sleep(3)
                    continue
                raise
            if status == 308:
                received = hdrs.get("Range")
                offset = int(received.split("-")[-1]) + 1 if received else end
                continue
            return json.loads(raw.decode())

    def rename(self, file_id, name):
        self.json_call("PATCH", f"{DRIVE}/files/{file_id}?fields=id", {"name": name})

    def trash(self, file_id):
        self.json_call("PATCH", f"{DRIVE}/files/{file_id}?fields=id", {"trashed": True})


def verify_upload(result, local_md5, name):
    remote = result.get("md5Checksum")
    if remote and remote != local_md5:
        raise RuntimeError(f"upload verification failed for {name}")


def remote_tree(drive, folder_id):
    """Returns {relative path: file} for every non-folder below folder_id."""
    result = {}
    stack = [(folder_id, "")]
    while stack:
        current, base = stack.pop()
        for item in drive.list_children(current):
            rel = f"{base}{item['name']}"
            if item["mimeType"] == FOLDER_MIME:
                stack.append((item["id"], rel + "/"))
            else:
                result[rel] = item
    return result


class Server:
    """Owns the Minecraft process, the console buffer and the player count."""

    def __init__(self):
        self.proc = None
        self.started_at = None
        self.state = "offline"
        self.players = 0
        self.max_players = 0
        self.saved_event = threading.Event()
        self.done_event = threading.Event()
        self.last_error = None
        self.exit_code = None
        self.cpu_percent = None
        self.rss_mb = None
        self._cpu_last = None
        self.memory_mb = 0

    def start(self, command, memory_mb):
        log("Starting Minecraft: " + " ".join(command[:5]) + " ...")
        self.state = "starting"
        self.saved_event.clear()
        self.done_event.clear()
        self.exit_code = None
        self.memory_mb = memory_mb
        self.proc = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8",
                                     errors="replace")
        self.started_at = time.time()
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        for raw in self.proc.stdout:
            line = raw.rstrip("\n")
            log(line)
            if "Saved the game" in line:
                self.saved_event.set()
            if "Done (" in line:
                self.state = "running"
                self.done_event.set()
            if "Stopping the server" in line:
                self.state = "stopping"
            match = re.search(r"There are (\d+) of a max of (\d+) players", line)
            if match:
                self.players = int(match.group(1))
                self.max_players = int(match.group(2))
            if re.search(r"\b(ERROR|Exception)\b", line) and "Caused by" not in line:
                self.last_error = line[-300:]
        self.exit_code = self.proc.wait()

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def send(self, text):
        if not self.alive():
            return False
        try:
            self.proc.stdin.write(text + "\n")
            self.proc.stdin.flush()
            return True
        except (BrokenPipeError, OSError, ValueError):
            return False

    def sample(self):
        """CPU percent and RSS of the Minecraft process, read from /proc on Linux."""
        if not self.alive():
            self.cpu_percent, self.rss_mb = None, None
            return
        try:
            with open(f"/proc/{self.proc.pid}/stat") as fh:
                fields = fh.read().split(")")[-1].split()
            ticks = int(fields[11]) + int(fields[12])
            clock = os.sysconf("SC_CLK_TCK")
            cpus = os.cpu_count() or 1
            now = time.time()
            if self._cpu_last:
                previous_ticks, previous_time = self._cpu_last
                elapsed = max(now - previous_time, 0.001)
                self.cpu_percent = round(100.0 * (ticks - previous_ticks) / clock / elapsed / cpus, 1)
            self._cpu_last = (ticks, now)
            with open(f"/proc/{self.proc.pid}/status") as fh:
                for line in fh:
                    if line.startswith("VmRSS:"):
                        self.rss_mb = int(line.split()[1]) // 1024
                        break
        except (OSError, ValueError, IndexError):
            pass


class Runner:
    def __init__(self):
        self.drive = Drive()
        self.folder = env("VOXEL_DRIVE_FOLDER_ID", required=True)
        self.server = Server()
        self.run_id = env("GITHUB_RUN_ID", "local")
        self.repo = env("GITHUB_REPOSITORY", "")
        self.ref = env("GITHUB_REF_NAME", "main")
        self.workflow = env("VOXEL_WORKFLOW_FILE", "voxelops-server.yml")
        self.limit_seconds = int(env("VOXEL_RUN_LIMIT_MINUTES", "330")) * 60
        self.software = env("VOXEL_SOFTWARE", "vanilla")
        self.mc_version = env("VOXEL_MC_VERSION", "")
        self.loader = env("VOXEL_LOADER_VERSION", "")
        self.runtime = {"memoryMb": 3072, "syncIntervalMinutes": 10, "backupIntervalMinutes": 180,
                        "backupRetention": 7, "autoContinue": True}
        self.started = time.time()
        self.stop_requested = False
        self.restart_requested = False
        self.kill_requested = False
        self.continue_after = False
        self.tailscale_ip = None
        self.last_sync = None
        self.last_backup = None
        self.sync_state = "idle"
        self.restarts = 0
        self.last_status = 0.0
        self.last_live = 0.0
        self.last_list = 0.0
        self.last_runtime = 0.0
        self.last_tailscale = 0.0
        self.last_sync_check = time.time()
        self.last_backup_check = time.time()

    # ----- Drive layout -----
    def ensure_folders(self):
        self.system = self.drive.ensure_folder(self.folder, SYSTEM_DIR)
        self.control = self.drive.ensure_folder(self.system, "control")
        self.commands = self.drive.ensure_folder(self.control, "commands")
        self.logs = self.drive.ensure_folder(self.system, "logs")
        self.imports = self.drive.ensure_folder(self.system, "imports")
        self.backups = self.drive.ensure_folder(self.folder, "backups")
        self.server_cache = self.drive.ensure_folder(self.folder, "server")

    def refresh_runtime(self):
        data = self.drive.read_json(self.control, "runtime.json")
        if isinstance(data, dict):
            self.runtime.update({k: v for k, v in data.items() if k in self.runtime})
        self.last_runtime = time.time()

    # ----- status and console -----
    def write_status(self, final=False):
        alive = self.server.alive() and not final
        status = {
            "state": self.server.state if alive else "offline",
            "updatedAt": now_iso(),
            "players": self.server.players if alive else 0,
            "maxPlayers": self.server.max_players,
            "minecraftVersion": self.mc_version,
            "cpuPercent": self.server.cpu_percent if alive else None,
            "ramUsedMb": self.server.rss_mb if alive else None,
            "ramTotalMb": int(self.runtime.get("memoryMb", 0)) or None,
            "uptimeSeconds": int(time.time() - self.server.started_at) if alive and self.server.started_at else None,
            "tailscaleIp": self.tailscale_ip,
            "syncState": self.sync_state,
            "lastError": self.server.last_error,
            "runId": self.run_id,
            "lastBackupAt": self.last_backup,
            "lastSyncAt": self.last_sync,
            "runnerVersion": "1.1",
        }
        self.drive.write_bytes(self.control, "status.json", json.dumps(status), "application/json")
        self.last_status = time.time()

    def write_live_log(self):
        with LOG_LOCK:
            text = "\n".join(list(LOG_LINES)[-400:]) + "\n"
        self.drive.write_bytes(self.control, "live.log", text, "text/plain")
        self.last_live = time.time()

    def process_commands(self):
        items = sorted(self.drive.list_children(self.commands, folders=False), key=lambda f: f["name"])
        for item in items:
            try:
                command = json.loads(self.drive.download_bytes(item["id"]).decode())
            except (ValueError, HttpError):
                command = {}
            kind = str(command.get("type", ""))
            payload = command.get("payload") or {}
            log(f"Command received: {kind}")
            try:
                self.handle(kind, payload)
            except (HttpError, OSError, RuntimeError, zipfile.BadZipFile) as error:
                self.server.last_error = f"Command {kind} failed: {error}"[:300]
                log(self.server.last_error)
            self.drive.trash(item["id"])

    def handle(self, kind, payload):
        if kind == "console":
            text = str(payload.get("text", ""))[:256]
            if text and not self.server.send(text):
                log("Console input ignored: the server is not running.")
        elif kind == "stop":
            self.stop_requested = True
            self.continue_after = False
        elif kind == "restart":
            self.restart_requested = True
        elif kind == "kill":
            self.kill_requested = True
            self.continue_after = False
        elif kind == "backup":
            self.flush()
            self.make_backup("manual")
        elif kind == "sync":
            self.sync_up()
        elif kind == "restore":
            self.restore_from(str(payload.get("fileId", "")))
        elif kind == "import":
            self.restore_from(str(payload.get("fileId", "")), importing=True)
        else:
            log(f"Unknown command ignored: {kind}")

    # ----- save and upload -----
    def flush(self):
        if self.server.alive():
            self.server.saved_event.clear()
            self.server.send("save-all flush")
            if not self.server.saved_event.wait(90):
                log("Timed out waiting for the world flush; uploading what is on disk.")

    def push_file(self, parent, name, local, mime, remote=None):
        digest = md5_of(local)
        if remote is None:
            remote = self.drive.find(parent, name)
        if remote and remote.get("md5Checksum") == digest:
            return
        last_error = None
        for attempt in range(3):
            try:
                result = self.drive.write_path(parent, name, local, mime, file_id=remote["id"] if remote else None)
                verify_upload(result, digest, name)
                return
            except (HttpError, OSError, RuntimeError, urllib.error.URLError) as error:
                last_error = error
                time.sleep(2 * (attempt + 1))
        raise RuntimeError(f"could not upload {name}: {last_error}")

    def push_dir(self, folder, replace=False):
        """Uploads new and changed files. Remote-only files are removed only when replace is True."""
        local_root = os.path.join(ROOT, folder)
        remote_root = self.drive.ensure_folder(self.folder, folder)
        remote = remote_tree(self.drive, remote_root)
        local_files = {}
        if os.path.isdir(local_root):
            for base, _, names in os.walk(local_root):
                for name in names:
                    full = os.path.join(base, name)
                    local_files[os.path.relpath(full, local_root).replace(os.sep, "/")] = full
        folder_ids = {"": remote_root}
        for rel, full in sorted(local_files.items()):
            parts = rel.split("/")
            for i in range(len(parts) - 1):
                key = "/".join(parts[: i + 1])
                if key not in folder_ids:
                    folder_ids[key] = self.drive.ensure_folder(folder_ids["/".join(parts[:i])], parts[i])
            parent_id = folder_ids["/".join(parts[:-1])]
            self.push_file(parent_id, parts[-1], full, "application/octet-stream", remote=remote.get(rel))
        if replace:
            for rel, meta in remote.items():
                if rel not in local_files:
                    self.drive.trash(meta["id"])

    def sync_up(self):
        """Uploads every changed file. Never deletes Drive data. Failures keep local data and retry later."""
        self.sync_state = "syncing"
        try:
            self.flush()
            for name in TOP_FILES:
                local = os.path.join(ROOT, name)
                if os.path.exists(local):
                    mime = "text/plain" if name.endswith((".properties", ".txt")) else "application/octet-stream"
                    self.push_file(self.folder, name, local, mime)
            for folder in SYNC_DIRS:
                self.push_dir(folder)
            self.last_sync = now_iso()
            self.sync_state = "idle"
            meta = self.drive.read_json(self.folder, "metadata.json") or {}
            meta["lastSyncAt"] = self.last_sync
            if self.last_backup:
                meta["lastBackupAt"] = self.last_backup
            self.drive.write_bytes(self.folder, "metadata.json", json.dumps(meta, indent=2), "application/json")
            log("Sync complete.")
        except (HttpError, OSError, RuntimeError, urllib.error.URLError, ValueError) as error:
            self.sync_state = "error"
            self.server.last_error = f"Sync failed, will retry: {error}"[:300]
            log(self.server.last_error)

    def pull_all(self):
        """Startup only: restores every file from Drive. Downloads are atomic and md5 verified."""
        for name in TOP_FILES:
            found = self.drive.find(self.folder, name)
            if found:
                target = os.path.join(ROOT, name)
                self.drive.download_to(found["id"], target)
                if found.get("md5Checksum") and md5_of(target) != found["md5Checksum"]:
                    raise RuntimeError(f"download verification failed for {name}")
        eula = os.path.join(ROOT, "eula.txt")
        content = open(eula).read() if os.path.exists(eula) else ""
        if "eula=true" not in content:
            with open(eula, "w") as fh:
                fh.write("eula=true\n")
        for folder in SYNC_DIRS:
            self.pull_dir(folder)

    def pull_dir(self, folder):
        local_root = os.path.join(ROOT, folder)
        remote_root = self.drive.ensure_folder(self.folder, folder)
        remote = remote_tree(self.drive, remote_root)
        os.makedirs(local_root, exist_ok=True)
        for rel, meta in remote.items():
            target = os.path.join(local_root, *rel.split("/"))
            if os.path.exists(target) and meta.get("md5Checksum") and md5_of(target) == meta["md5Checksum"]:
                continue
            log(f"Downloading {folder}/{rel}")
            self.drive.download_to(meta["id"], target)
            if meta.get("md5Checksum") and md5_of(target) != meta["md5Checksum"]:
                raise RuntimeError(f"download verification failed for {folder}/{rel}")
        for base, _, names in os.walk(local_root):
            for name in names:
                full = os.path.join(base, name)
                if os.path.relpath(full, local_root).replace(os.sep, "/") not in remote:
                    os.remove(full)

    # ----- backups, restores and imports -----
    def make_backup(self, kind):
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        name = f"{kind}-{stamp}.zip"
        path = os.path.join(TMP, name)
        self.sync_state = "backup"
        try:
            with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for folder in WORLD_DIRS:
                    base = os.path.join(ROOT, folder)
                    for root_dir, _, names in os.walk(base):
                        for name_in in names:
                            full = os.path.join(root_dir, name_in)
                            archive.write(full, os.path.relpath(full, ROOT).replace(os.sep, "/"))
                props = os.path.join(ROOT, "server.properties")
                if os.path.exists(props):
                    archive.write(props, "server.properties")
            digest = md5_of(path)
            result = self.drive.write_path(self.backups, name, path, "application/zip")
            verify_upload(result, digest, name)
            self.last_backup = now_iso()
            if kind == "auto":
                self.prune_backups()
            log(f"Backup {name} uploaded and verified.")
        except (HttpError, OSError, RuntimeError, urllib.error.URLError, zipfile.BadZipFile) as error:
            self.server.last_error = f"Backup failed: {error}"[:300]
            log(self.server.last_error)
        finally:
            if os.path.exists(path):
                os.remove(path)
            self.sync_state = "idle"

    def prune_backups(self):
        keep = int(self.runtime.get("backupRetention", 7))
        autos = sorted((f for f in self.drive.list_children(self.backups, folders=False)
                        if f["name"].startswith("auto-")), key=lambda f: f["name"], reverse=True)
        for old in autos[keep:]:
            self.drive.trash(old["id"])

    def apply_archive(self, file_id):
        """Replaces the world with an archive. The previous world stays on disk until upload succeeds."""
        archive = os.path.join(TMP, "restore.zip")
        extract = os.path.join(TMP, "restore")
        shutil.rmtree(extract, ignore_errors=True)
        self.drive.download_to(file_id, archive)
        stash = os.path.join(ROOT, ".voxel-previous")
        try:
            with zipfile.ZipFile(archive) as zf:
                if zf.testzip() is not None:
                    raise RuntimeError("The archive is damaged.")
                zf.extractall(extract)
            if not os.path.exists(os.path.join(extract, "world", "level.dat")):
                if os.path.exists(os.path.join(extract, "level.dat")):
                    os.makedirs(os.path.join(extract, "world"), exist_ok=True)
                    shutil.move(os.path.join(extract, "level.dat"), os.path.join(extract, "world", "level.dat"))
                else:
                    raise RuntimeError("The archive does not contain a Minecraft world (level.dat).")
            shutil.rmtree(stash, ignore_errors=True)
            os.makedirs(stash)
            for folder in WORLD_DIRS:
                current = os.path.join(ROOT, folder)
                if os.path.exists(current):
                    os.replace(current, os.path.join(stash, folder))
                source = os.path.join(extract, folder)
                if os.path.isdir(source):
                    os.replace(source, current)
            try:
                for folder in WORLD_DIRS:
                    if os.path.isdir(os.path.join(ROOT, folder)):
                        self.push_dir(folder, replace=True)
            except (HttpError, OSError, RuntimeError, urllib.error.URLError) as error:
                for folder in WORLD_DIRS:
                    shutil.rmtree(os.path.join(ROOT, folder), ignore_errors=True)
                    if os.path.exists(os.path.join(stash, folder)):
                        os.replace(os.path.join(stash, folder), os.path.join(ROOT, folder))
                raise RuntimeError(f"restore rolled back after upload failure: {error}") from None
            shutil.rmtree(stash, ignore_errors=True)
        finally:
            shutil.rmtree(extract, ignore_errors=True)
            if os.path.exists(archive):
                os.remove(archive)

    def restore_from(self, file_id, importing=False):
        if not file_id:
            raise RuntimeError("Missing archive id")
        self.graceful_stop("import" if importing else "restore")
        self.make_backup("prerestore")
        self.apply_archive(file_id)
        self.restart_requested = False
        self.stop_requested = False
        self.launch()

    def apply_pending_imports(self):
        for item in sorted(self.drive.list_children(self.imports, folders=False), key=lambda f: f["name"]):
            if item["name"].startswith("applied-"):
                continue
            log(f"Applying imported world {item['name']}")
            self.make_backup("prerestore")
            self.apply_archive(item["id"])
            self.drive.rename(item["id"], "applied-" + item["name"])

    # ----- Minecraft software -----
    def install_software(self):
        os.makedirs(ROOT, exist_ok=True)
        if self.software == "vanilla":
            manifest = json.loads(http("GET", "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")[2].decode())
            entry = next(v for v in manifest["versions"] if v["id"] == self.mc_version)
            details = json.loads(http("GET", entry["url"])[2].decode())
            self.download(details["downloads"]["server"]["url"], os.path.join(ROOT, "server.jar"))
        elif self.software == "fabric":
            loader, installer = (self.loader.split("|") + ["", ""])[:2]
            url = f"https://meta.fabricmc.net/v2/versions/loader/{self.mc_version}/{loader}/{installer}/server/jar"
            self.download(url, os.path.join(ROOT, "fabric-server-launch.jar"))
        elif self.software in ("forge", "neoforge"):
            if not glob.glob(os.path.join(ROOT, "libraries", "**", "unix_args.txt"), recursive=True):
                base = ("https://maven.minecraftforge.net/net/minecraftforge/forge" if self.software == "forge"
                        else "https://maven.neoforged.net/releases/net/neoforged/neoforge")
                prefix = self.software if self.software == "neoforge" else "forge"
                installer = os.path.join(TMP, "installer.jar")
                self.download(f"{base}/{self.loader}/{prefix}-{self.loader}-installer.jar", installer)
                log("Running the loader installer. This takes a few minutes on the first start.")
                subprocess.run(["java", "-jar", installer, "--installServer"], cwd=ROOT, check=True, timeout=1500)
        elif self.software == "paper":
            url = f"https://fill.papermc.io/v3/projects/paper/versions/{self.mc_version}/builds/{self.loader}"
            info = json.loads(http("GET", url)[2].decode())
            self.download(info["downloads"]["server:default"]["url"], os.path.join(ROOT, "server.jar"))
        elif self.software == "purpur":
            self.download(f"https://api.purpurmc.org/v2/purpur/{self.mc_version}/{self.loader}/download",
                          os.path.join(ROOT, "server.jar"))
        elif self.software == "spigot":
            self.install_spigot()
        else:
            raise RuntimeError(f"Unsupported software: {self.software}")

    def install_spigot(self):
        cached_name = f"spigot-{self.mc_version}.jar"
        cached = self.drive.find(self.server_cache, cached_name)
        if cached:
            self.drive.download_to(cached["id"], os.path.join(ROOT, "server.jar"))
            return
        build_dir = os.path.join(TMP, "buildtools")
        os.makedirs(build_dir, exist_ok=True)
        tools = os.path.join(build_dir, "BuildTools.jar")
        self.download("https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar",
                      tools)
        log("Compiling Spigot with BuildTools. This takes several minutes the first time.")
        subprocess.run(["java", "-jar", tools, "--rev", self.mc_version], cwd=build_dir, check=True, timeout=3600)
        produced = glob.glob(os.path.join(build_dir, f"spigot-{self.mc_version}*.jar"))
        if not produced:
            raise RuntimeError("BuildTools did not produce a Spigot jar.")
        shutil.copy(produced[0], os.path.join(ROOT, "server.jar"))
        self.drive.write_path(self.server_cache, cached_name, os.path.join(ROOT, "server.jar"),
                              "application/java-archive")

    def download(self, url, target):
        os.makedirs(os.path.dirname(target), exist_ok=True)
        log(f"Downloading {os.path.basename(target)}")
        retry(lambda: http("GET", url, timeout=900, stream_to=target))

    def build_command(self, memory_mb):
        flags = [
            "-XX:+UseG1GC", "-XX:+ParallelRefProcEnabled", "-XX:MaxGCPauseMillis=200",
            "-XX:+UnlockExperimentalVMOptions", "-XX:+DisableExplicitGC", "-XX:G1NewSizePercent=30",
            "-XX:G1MaxNewSizePercent=40", "-XX:G1HeapRegionSize=8M", "-XX:G1ReservePercent=20",
            "-XX:InitiatingHeapOccupancyPercent=15",
        ]
        memory = [f"-Xms{memory_mb}M", f"-Xmx{memory_mb}M"]
        if self.software in ("forge", "neoforge"):
            args = sorted(glob.glob(os.path.join(ROOT, "libraries", "**", "unix_args.txt"), recursive=True))
            if not args:
                raise RuntimeError("The loader installer did not generate its launch arguments.")
            with open(os.path.join(ROOT, "user_jvm_args.txt"), "w") as fh:
                fh.write("\n".join(memory + flags) + "\n")
            return ["java", "@user_jvm_args.txt", f"@{os.path.relpath(args[0], ROOT)}", "nogui"]
        jar = "fabric-server-launch.jar" if self.software == "fabric" else "server.jar"
        return ["java", *memory, *flags, "-jar", jar, "nogui"]

    def launch(self):
        memory = int(self.runtime.get("memoryMb", 3072))
        self.server.start(self.build_command(memory), memory)
        self.write_status()

    # ----- shutdown sequences -----
    def stop_server(self, reason):
        if not self.server.alive():
            self.server.state = "offline"
            return
        log(f"Stopping the server ({reason}).")
        self.server.send("say VoxelOps: saving the world and stopping shortly.")
        self.server.state = "stopping"
        self.server.send("stop")
        try:
            self.server.proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            log("The server did not stop in time; terminating it.")
            self.server.proc.terminate()
            try:
                self.server.proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.server.proc.kill()
        self.server.state = "offline"

    def graceful_stop(self, reason):
        """Save -> upload -> backup -> stop -> upload again. Used for stop, restart, restore and time limit."""
        if self.server.alive():
            self.flush()
            self.sync_up()
            self.make_backup("auto")
            self.stop_server(reason)
        self.sync_up()

    def kill_server(self):
        if self.server.alive():
            self.server.proc.kill()
            self.server.proc.wait(timeout=60)
        self.server.state = "offline"

    # ----- main loop -----
    def run(self):
        self.ensure_folders()
        self.write_status()
        self.install_software()
        self.refresh_runtime()
        self.sync_state = "restoring"
        self.write_status()
        self.pull_all()
        self.apply_pending_imports()
        self.sync_state = "idle"
        self.launch()
        self.tailscale_ip = self.read_tailscale_ip()
        self.last_tailscale = time.time()
        while True:
            now = time.time()
            if self.kill_requested:
                log("Kill requested: terminating the server without saving.")
                self.kill_server()
                break
            if now - self.started > self.limit_seconds and not self.stop_requested:
                log("Approaching the six-hour job limit: saving and handing over to a new run.")
                self.continue_after = bool(self.runtime.get("autoContinue", True))
                self.stop_requested = True
            if self.stop_requested:
                self.graceful_stop("stop")
                break
            if self.restart_requested:
                self.restart_requested = False
                log("Restart requested.")
                self.graceful_stop("restart")
                self.launch()
            if self.server.proc is not None and not self.server.alive() and not self.stop_requested:
                code = self.server.exit_code
                log(f"The server exited with code {code}.")
                self.sync_up()
                if code not in (0, None) and self.restarts < 3:
                    self.restarts += 1
                    time.sleep(20)
                    self.launch()
                else:
                    break
            if self.server.state == "running" and now - self.last_list > 60:
                self.server.send("list")
                self.last_list = now
            if now - self.last_runtime > 60:
                self.refresh_runtime()
            if now - self.last_tailscale > 600:
                self.tailscale_ip = self.read_tailscale_ip()
                self.last_tailscale = now
            self.server.sample()
            sync_seconds = int(self.runtime.get("syncIntervalMinutes", 10)) * 60
            if self.server.state == "running" and now - self.last_sync_check > sync_seconds:
                self.last_sync_check = now
                self.sync_up()
            backup_seconds = int(self.runtime.get("backupIntervalMinutes", 0) or 0) * 60
            if self.server.state == "running" and backup_seconds > 0 and now - self.last_backup_check > backup_seconds:
                self.last_backup_check = now
                self.make_backup("auto")
            try:
                self.process_commands()
            except (HttpError, OSError, urllib.error.URLError) as error:
                log(f"Command poll failed: {error}")
            if now - self.last_status > 15:
                self.write_status()
            if now - self.last_live > 15:
                self.write_live_log()
            time.sleep(5)
        self.finish()

    def read_tailscale_ip(self):
        if env("VOXEL_TAILSCALE_ENABLED", "false") != "true":
            return None
        try:
            out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=20)
            lines = out.stdout.strip().splitlines()
            return lines[0] if out.returncode == 0 and lines else None
        except (OSError, subprocess.SubprocessError):
            return None

    def finish(self):
        if self.server.alive():
            self.graceful_stop("shutdown")
        self.sync_state = "idle"
        self.server.state = "offline"
        try:
            self.write_status(final=True)
            self.write_live_log()
            archive = os.path.join(TMP, f"run-{self.run_id}.log")
            with open(archive, "w", encoding="utf-8") as fh:
                with LOG_LOCK:
                    fh.write("\n".join(LOG_LINES) + "\n")
            self.drive.write_path(self.logs, f"run-{self.run_id}.log", archive, "text/plain")
        except (HttpError, OSError, urllib.error.URLError, RuntimeError) as error:
            log(f"Could not write the final status: {error}")
        if self.continue_after and not self.kill_requested:
            self.dispatch_next()

    def dispatch_next(self):
        token = env("GITHUB_TOKEN", "")
        if not self.repo or not token:
            log("No GitHub token available; the server will not continue automatically.")
            return
        url = f"https://api.github.com/repos/{self.repo}/actions/workflows/{self.workflow}/dispatches"
        try:
            http("POST", url, data=json.dumps({"ref": self.ref}).encode(), headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json",
            })
            log("The next run was dispatched to continue the server.")
        except HttpError as error:
            log(f"Could not dispatch the next run (HTTP {error.status}).")


def main():
    runner = Runner()
    finished = {"value": False}

    def on_signal(signum, _frame):
        if not finished["value"]:
            log(f"Signal {signum} received: saving and stopping.")
            runner.stop_requested = True
            runner.continue_after = False

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    try:
        runner.run()
    except Exception as error:  # every fatal error is written to status and to the console
        log(f"Fatal error: {error}")
        runner.server.last_error = f"Fatal: {error}"[:300]
        try:
            runner.finish()
        except Exception as inner:  # best effort during shutdown
            log(f"Shutdown error: {inner}")
        raise
    finally:
        finished["value"] = True
        shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    main()
