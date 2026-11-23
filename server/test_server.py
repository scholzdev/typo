"""Self-check: uv run --with cryptography python server/test_server.py"""
import base64
import json
import os
import tempfile
import threading
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

issuer, activation = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()
data = tempfile.mkdtemp()
with open(os.path.join(data, "activation.pem"), "wb") as f:
    f.write(activation.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
os.environ["DATA_DIR"] = data
os.environ["LICENSE_PUBLIC_KEY"] = base64.b64encode(
    issuer.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()

import server  # noqa: E402  (reads the environment at import)

httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.make_handler(server.load_signer()))
threading.Thread(target=httpd.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{httpd.server_port}"


def license_key(lid: str, signer=issuer) -> str:
    payload = json.dumps({"id": lid, "email": "a@example.com", "issued": 1795390000}).encode()
    return server.b64url(payload) + "." + server.b64url(signer.sign(payload))


def post(path: str, body) -> tuple[int, dict]:
    raw = body if isinstance(body, bytes) else json.dumps(body).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(base + path, raw)) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def device(n: int) -> str:
    return f"{n:064x}"


key = license_key("L1")

status, body = post("/v1/activate", {"key": key, "device": device(1)})
assert status == 200, (status, body)
payload, signature = (base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)) for p in body["token"].split("."))
activation.public_key().verify(signature, payload)
claims = json.loads(payload)
assert claims["license"] == "L1" and claims["device"] == device(1)
assert abs(claims["expires"] - time.time() - 30 * 86400) < 60

assert post("/v1/activate", {"key": key, "device": device(1)})[0] == 200, "refresh of an active device"
assert post("/v1/activate", {"key": " " + key[:30] + "\n" + key[30:], "device": device(1)})[0] == 200, "pasted whitespace"
assert post("/v1/activate", {"key": key, "device": device(2)})[0] == 200
assert post("/v1/activate", {"key": key, "device": device(3)})[0] == 200
assert post("/v1/activate", {"key": key, "device": device(4)}) == (403, {"error": "device_limit"})

assert post("/v1/deactivate", {"key": key, "device": device(1)}) == (200, {})
assert post("/v1/activate", {"key": key, "device": device(4)})[0] == 200, "deactivating frees a slot"
assert post("/v1/activate", {"key": key, "device": device(1)}) == (403, {"error": "device_limit"})

for bad in [
    {"key": license_key("L1", Ed25519PrivateKey.generate()), "device": device(9)},
    {"key": key[:-4] + "AAAA", "device": device(9)},
    {"key": "garbage", "device": device(9)},
    {"key": key, "device": "short"},
    {"key": key, "device": device(9).upper().replace("9", "G")},
    {"key": 5, "device": device(9)},
    {"key": key},
    [],
    b"not json",
    b"x" * 5000,
]:
    assert post("/v1/activate", bad) == (403, {"error": "invalid"}), bad
assert post("/v1/deactivate", {"key": "garbage", "device": device(1)}) == (403, {"error": "invalid"})

churn = license_key("L2")
for n in range(6):
    assert post("/v1/activate", {"key": churn, "device": device(n)})[0] == 200
    assert post("/v1/deactivate", {"key": churn, "device": device(n)})[0] == 200
assert post("/v1/activate", {"key": churn, "device": device(6)}) == (403, {"error": "device_limit"}), "seventh device in 30 days"
assert post("/v1/activate", {"key": churn, "device": device(0)})[0] == 200, "a known device may come back"

server.admin("revoke", [key])
assert post("/v1/activate", {"key": key, "device": device(2)}) == (403, {"error": "revoked"})
server.admin("unrevoke", ["L1"])
assert post("/v1/activate", {"key": key, "device": device(2)})[0] == 200

with urllib.request.urlopen(base + "/healthz") as r:
    assert r.status == 200
print("ok")
