"""In-memory Google Drive v3 subset for the end-to-end test of the runner.

This server exists only inside the test job. The production runner talks to Google when
VOXEL_DRIVE_API / VOXEL_DRIVE_UPLOAD / VOXEL_TOKEN_URL are not set. The app never uses this file.
It implements exactly the calls the runner makes: token, files.list (q, pageSize, fields),
files.get (alt=media), files.create (folder), files.update (name, trashed), multipart upload,
resumable upload (create and update) with Content-Range and 308 responses, and media update.
"""

import hashlib
import json
import re
import threading
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

FOLDER = "application/vnd.google-apps.folder"


def _now():
    return datetime.now(timezone.utc).isoformat()


class FakeDrive:
    def __init__(self):
        self.lock = threading.RLock()
        self.files = {}
        self.sessions = {}
        # Fault injection for tests (all off by default).
        self.fail_put_after_store = False  # next chunk is stored, then answered with 503 (lost response)
        self.expire_token_once = False     # next authenticated call answers 401 once
        self.revoked = False               # token endpoint answers invalid_grant
        self.add_entry("root", "root", FOLDER, [], b"")

    def add_entry(self, file_id, name, mime, parents, content):
        self.files[file_id] = {
            "id": file_id, "name": name, "mimeType": mime, "parents": list(parents),
            "trashed": False, "content": content, "modifiedTime": _now(),
        }
        return file_id

    def create_folder(self, parent, name):
        with self.lock:
            return self.add_entry(uuid.uuid4().hex[:16], name, FOLDER, [parent], b"")

    def put_file(self, parent, name, content, mime):
        with self.lock:
            existing = self.find(parent, name)
            if existing:
                self.files[existing]["content"] = content
                self.files[existing]["modifiedTime"] = _now()
                return existing
            return self.add_entry(uuid.uuid4().hex[:16], name, mime, [parent], content)

    def find(self, parent, name):
        for entry in self.files.values():
            if not entry["trashed"] and entry["name"] == name and parent in entry["parents"]:
                return entry["id"]
        return None

    def children(self, parent):
        with self.lock:
            return [e for e in self.files.values() if not e["trashed"] and parent in e["parents"]]

    def read(self, file_id):
        with self.lock:
            return self.files[file_id]["content"]

    def meta(self, entry):
        data = {
            "id": entry["id"], "name": entry["name"], "mimeType": entry["mimeType"],
            "parents": entry["parents"], "trashed": entry["trashed"], "modifiedTime": entry["modifiedTime"],
        }
        if entry["mimeType"] != FOLDER:
            data["md5Checksum"] = hashlib.md5(entry["content"]).hexdigest()
            data["size"] = str(len(entry["content"]))
        return data

    def store_content(self, file_id, content):
        with self.lock:
            entry = self.files[file_id]
            entry["content"] = content
            entry["modifiedTime"] = _now()
            return self.meta(entry)

    def create_file(self, name, mime, parents, content):
        with self.lock:
            file_id = self.add_entry(uuid.uuid4().hex[:16], name, mime, parents, content)
            return self.meta(self.files[file_id])

    def query(self, q):
        clauses = [c.strip() for c in q.split(" and ")]
        results = []
        for entry in self.files.values():
            if entry["id"] == "root":
                continue
            if not self._matches(entry, clauses):
                continue
            results.append(entry)
        return sorted(results, key=lambda e: e["name"])

    @staticmethod
    def _unquote(value):
        return value.replace("\\'", "'").replace("\\\\", "\\")

    def _matches(self, entry, clauses):
        for clause in clauses:
            if m := re.fullmatch(r"'((?:\\.|[^'\\])*)' in parents", clause):
                if self._unquote(m.group(1)) not in entry["parents"]:
                    return False
            elif m := re.fullmatch(r"name = '((?:\\.|[^'\\])*)'", clause):
                if entry["name"] != self._unquote(m.group(1)):
                    return False
            elif m := re.fullmatch(r"mimeType (=|!=) '([^']*)'", clause):
                equal = entry["mimeType"] == m.group(2)
                if (m.group(1) == "=") != equal:
                    return False
            elif m := re.fullmatch(r"trashed = (true|false)", clause):
                if entry["trashed"] != (m.group(1) == "true"):
                    return False
            else:
                raise ValueError(f"unsupported query clause: {clause}")
        return True


def _parse_multipart(body, content_type):
    boundary = re.search(r"boundary=([^;]+)", content_type).group(1).strip('"').encode()
    parts = []
    for section in body.split(b"--" + boundary)[1:]:
        if section.startswith(b"--"):
            break
        if section.startswith(b"\r\n"):
            section = section[2:]
        header_end = section.find(b"\r\n\r\n")
        content = section[header_end + 4:]
        if content.endswith(b"\r\n"):
            content = content[:-2]
        parts.append(content)
    return json.loads(parts[0].decode()), parts[1]


def make_handler(drive):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            return

        def _send(self, status, body=b"", headers=None, content_type="application/json"):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            for key, value in (headers or {}).items():
                self.send_header(key, value)
            self.end_headers()
            if body:
                self.wfile.write(body)

        def _json(self, status, payload, headers=None):
            self._send(status, json.dumps(payload).encode(), headers)

        def _body(self):
            length = int(self.headers.get("Content-Length", "0") or 0)
            return self.rfile.read(length) if length else b""

        def _auth_ok(self):
            if drive.expire_token_once:
                drive.expire_token_once = False
                return False
            return self.headers.get("Authorization", "").startswith("Bearer ")

        def do_POST(self):
            url = urlparse(self.path)
            body = self._body()
            if url.path == "/token":
                if drive.revoked:
                    return self._json(400, {"error": "invalid_grant", "error_description": "Token has been expired or revoked."})
                return self._json(200, {"access_token": "e2e-access-token", "expires_in": 3600, "token_type": "Bearer"})
            if not self._auth_ok():
                return self._json(401, {"error": {"message": "missing bearer token"}})
            if url.path == "/drive/v3/files":
                payload = json.loads(body.decode() or "{}")
                created = drive.create_folder(payload["parents"][0], payload["name"])
                return self._json(200, drive.meta(drive.files[created]))
            if url.path == "/upload/drive/v3/files":
                query = parse_qs(url.query)
                upload_type = query.get("uploadType", ["multipart"])[0]
                if upload_type == "multipart":
                    meta, media = _parse_multipart(body, self.headers.get("Content-Type", ""))
                    created = drive.create_file(meta["name"], meta["mimeType"], meta["parents"], media)
                    return self._json(200, created)
                return self._start_session(body, file_id=None)
            return self._json(404, {"error": {"message": f"no route {url.path}"}})

        def do_PATCH(self):
            url = urlparse(self.path)
            body = self._body()
            if not self._auth_ok():
                return self._json(401, {"error": {"message": "missing bearer token"}})
            query = parse_qs(url.query)
            if url.path.startswith("/upload/drive/v3/files/"):
                file_id = url.path.rsplit("/", 1)[1]
                if query.get("uploadType", [""])[0] == "media":
                    return self._json(200, drive.store_content(file_id, body))
                return self._start_session(body, file_id=file_id)
            if url.path.startswith("/drive/v3/files/"):
                file_id = url.path.rsplit("/", 1)[1]
                payload = json.loads(body.decode() or "{}")
                with drive.lock:
                    entry = drive.files[file_id]
                    if "name" in payload:
                        entry["name"] = payload["name"]
                    if "trashed" in payload:
                        entry["trashed"] = bool(payload["trashed"])
                    return self._json(200, {"id": file_id})
            return self._json(404, {"error": {"message": f"no route {url.path}"}})

        def do_PUT(self):
            url = urlparse(self.path)
            body = self._body()
            if not url.path.startswith("/upload/session/"):
                return self._json(404, {"error": {"message": "no session"}})
            session_id = url.path.rsplit("/", 1)[1]
            with drive.lock:
                session = drive.sessions[session_id]
                content_range = self.headers.get("Content-Range", "")
                if content_range == "bytes */0":
                    session["buf"] = b""
                    total = 0
                elif content_range.startswith("bytes */"):
                    # Status query (no data): report how many bytes Drive already stored.
                    total = int(content_range.split("/")[-1])
                else:
                    match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", content_range)
                    start, _, total = int(match.group(1)), int(match.group(2)), int(match.group(3))
                    if start != len(session["buf"]):
                        return self._json(400, {"error": {"message": "out of order chunk"}})
                    session["buf"] += body
                    if drive.fail_put_after_store:
                        drive.fail_put_after_store = False
                        return self._json(503, {"error": {"message": "transient failure"}})
                received = len(session["buf"])
                if received < total:
                    headers = {"Range": f"bytes=0-{received - 1}"} if received else {}
                    return self._send(308, b"", headers)
                content = session["buf"]
                if session["file_id"]:
                    meta = drive.store_content(session["file_id"], content)
                else:
                    meta = drive.create_file(session["name"], session["mime"], session["parents"], content)
                del drive.sessions[session_id]
            return self._json(200, meta)

        def do_GET(self):
            url = urlparse(self.path)
            if not self._auth_ok():
                return self._json(401, {"error": {"message": "missing bearer token"}})
            query = parse_qs(url.query)
            if url.path == "/drive/v3/files":
                with drive.lock:
                    matches = drive.query(query.get("q", ["trashed = false"])[0])
                    files = [drive.meta(e) for e in matches]
                return self._json(200, {"files": files})
            if url.path.startswith("/drive/v3/files/"):
                file_id = url.path.rsplit("/", 1)[1]
                with drive.lock:
                    entry = drive.files.get(file_id)
                    if entry is None:
                        return self._json(404, {"error": {"message": "not found"}})
                    if query.get("alt", [""])[0] == "media":
                        return self._send(200, entry["content"], content_type="application/octet-stream")
                    return self._json(200, drive.meta(entry))
            return self._json(404, {"error": {"message": f"no route {url.path}"}})

        def _start_session(self, body, file_id):
            session_id = uuid.uuid4().hex
            payload = json.loads(body.decode() or "{}")
            with drive.lock:
                drive.sessions[session_id] = {
                    "buf": b"", "file_id": file_id,
                    "name": payload.get("name"), "parents": payload.get("parents", []),
                    "mime": self.headers.get("X-Upload-Content-Type", payload.get("mimeType", "application/octet-stream")),
                }
            location = f"http://{self.headers.get('Host')}/upload/session/{session_id}"
            self._send(200, b"", {"Location": location})

    return Handler


def serve(drive, host, port):
    server = ThreadingHTTPServer((host, port), make_handler(drive))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server
