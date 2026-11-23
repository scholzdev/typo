"""Typo license activation server.

Exchanges a signed license key for a short-lived token bound to one device.
It only ever holds the license *public* key, so a compromise here cannot mint licenses.

Admin: python server.py revoke|unrevoke <license id or key> | list
"""
import base64
import json
import os
import re
import sqlite3
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import load_pem_private_key

DATA = os.environ.get("DATA_DIR", "/data")
ISSUER = Ed25519PublicKey.from_public_bytes(base64.b64decode(os.environ["LICENSE_PUBLIC_KEY"]))
DEVICE_LIMIT = 3
CHURN_LIMIT = 6  # distinct devices per license per token lifetime, so deactivate/activate cycling stays bounded
TOKEN_SECONDS = 30 * 86400
MAX_BODY = 4096
DEVICE = re.compile(r"[0-9a-f]{64}")

lock = threading.Lock()
db = sqlite3.connect(os.path.join(DATA, "licenses.db"), check_same_thread=False)
db.executescript("""
create table if not exists activations(
    license text not null, device text not null, created integer not null,
    last_seen integer not null, active integer not null, primary key(license, device));
create table if not exists revoked(license text primary key);
""")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def license_id(key) -> str | None:
    """The license id if `key` carries a valid issuer signature, else None."""
    try:
        payload, signature = (base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)) for p in "".join(key.split()).split("."))
        ISSUER.verify(signature, payload)
        lid = json.loads(payload)["id"]
        return lid if isinstance(lid, str) else None
    except (InvalidSignature, ValueError, KeyError, TypeError, AttributeError):
        return None


def activate(lid: str, device: str, now: int) -> str | None:
    """Claims a device slot; returns an error code or None."""
    with lock, db:
        if db.execute("select 1 from revoked where license=?", (lid,)).fetchone():
            return "revoked"
        row = db.execute("select active from activations where license=? and device=?", (lid, device)).fetchone()
        if not (row and row[0]):
            if db.execute("select count(*) from activations where license=? and active=1", (lid,)).fetchone()[0] >= DEVICE_LIMIT:
                return "device_limit"
            recent = db.execute("select count(*) from activations where license=? and created>?", (lid, now - TOKEN_SECONDS)).fetchone()[0]
            if not row and recent >= CHURN_LIMIT:
                return "device_limit"
        db.execute(
            "insert into activations values(?,?,?,?,1) on conflict(license, device) do update set active=1, last_seen=excluded.last_seen",
            (lid, device, now, now))
    return None


def deactivate(lid: str, device: str) -> None:
    with lock, db:
        db.execute("update activations set active=0 where license=? and device=?", (lid, device))


def token(signer, lid: str, device: str, now: int) -> str:
    payload = json.dumps({"license": lid, "device": device, "expires": now + TOKEN_SECONDS}, separators=(",", ":")).encode()
    return b64url(payload) + "." + b64url(signer.sign(payload))


def handle(signer, path: str, body: bytes) -> tuple[int, dict]:
    try:
        request = json.loads(body)
        key, device = request["key"], request["device"]
    except (ValueError, KeyError, TypeError):
        return 403, {"error": "invalid"}
    lid = license_id(key)
    if lid is None or not isinstance(device, str) or not DEVICE.fullmatch(device):
        return 403, {"error": "invalid"}
    if path == "/v1/deactivate":
        deactivate(lid, device)
        return 200, {}
    now = int(time.time())
    error = activate(lid, device, now)
    return (403, {"error": error}) if error else (200, {"token": token(signer, lid, device, now)})


def make_handler(signer):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status: int, body: dict):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self.reply(200, {"ok": True}) if self.path == "/healthz" else self.reply(404, {})

        def do_POST(self):
            if self.path not in ("/v1/activate", "/v1/deactivate"):
                return self.reply(404, {})
            length = int(self.headers.get("Content-Length") or 0)
            if not 0 < length <= MAX_BODY:
                return self.reply(403, {"error": "invalid"})
            self.reply(*handle(signer, self.path, self.rfile.read(length)))

        def log_message(self, *args):  # no request log: it would hold client IPs
            pass

    return Handler


def load_signer():
    with open(os.path.join(DATA, "activation.pem"), "rb") as f:
        return load_pem_private_key(f.read(), None)


def admin(command: str, args: list[str]) -> None:
    if command == "list" and not args:
        for row in db.execute("select license, count(*) filter (where active=1), max(last_seen) from activations group by license"):
            print(f"{row[0]}  active={row[1]}  last_seen={time.strftime('%Y-%m-%d', time.gmtime(row[2]))}")
        for (lid,) in db.execute("select license from revoked"):
            print(f"{lid}  REVOKED")
    elif command in ("revoke", "unrevoke") and len(args) == 1:
        lid = license_id(args[0]) if "." in args[0] else args[0]
        if lid is None:
            sys.exit("That key has no valid signature.")
        with lock, db:
            db.execute("insert or ignore into revoked values(?)" if command == "revoke" else "delete from revoked where license=?", (lid,))
        print(f"{command}d {lid}")
    else:
        sys.exit("usage: server.py [revoke|unrevoke <license id or key> | list]")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        admin(sys.argv[1], sys.argv[2:])
    else:
        ThreadingHTTPServer(("0.0.0.0", 8080), make_handler(load_signer())).serve_forever()
