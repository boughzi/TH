#!/usr/bin/env python3
"""Revisa todos los canales y desactiva los caídos.

Variables de entorno: SUPABASE_URL, SUPABASE_SERVICE_KEY
Opcionales: FAIL_LIMIT (2), WORKERS (20), TIMEOUT (10), MAX_DEAD_RATIO (0.6)
"""
import base64
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from urllib.parse import urljoin

import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

try:
    URL = os.environ["SUPABASE_URL"].rstrip("/")
    KEY = os.environ["SUPABASE_SERVICE_KEY"]
except KeyError as e:
    sys.exit(f"Falta la variable de entorno {e}")

FAIL_LIMIT = int(os.getenv("FAIL_LIMIT", "2"))          # fallos seguidos antes de desactivar
WORKERS = int(os.getenv("WORKERS", "20"))
TIMEOUT = float(os.getenv("TIMEOUT", "10"))
MAX_DEAD_RATIO = float(os.getenv("MAX_DEAD_RATIO", "0.6"))  # protección ante fallo de red del runner
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"
REST = f"{URL}/rest/v1"
HDR = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}


# ---------- Supabase ----------
def fetch_all(path, params):
    out, offset = [], 0
    while True:
        r = requests.get(f"{REST}/{path}", headers=HDR,
                         params={**params, "limit": 1000, "offset": offset}, timeout=30)
        r.raise_for_status()
        rows = r.json()
        out += rows
        if len(rows) < 1000:
            return out
        offset += 1000


def patch(ids, payload):
    for i in range(0, len(ids), 100):
        part = ids[i:i + 100]
        r = requests.patch(f"{REST}/channels", headers={**HDR, "Prefer": "return=minimal"},
                           params={"id": f"in.({','.join(part)})"}, json=payload, timeout=30)
        r.raise_for_status()


# ---------- Comprobación ----------
def _get(url, headers=None):
    return requests.get(url, headers={"User-Agent": UA, **(headers or {})},
                        timeout=TIMEOUT, stream=True, allow_redirects=True)


def _read(resp, limit=512_000):
    buf = b""
    for chunk in resp.iter_content(8192):
        buf += chunk
        if len(buf) >= limit:
            break
    return buf


def probe(url, depth=0):
    with _get(url) as r:
        if r.status_code != 200:
            return False
        first = next(r.iter_content(4096), b"")
        if not first:
            return False
        if not first.lstrip().startswith(b"#EXTM3U"):
            # stream directo (no playlist): vale si devuelve datos y no es una web
            return "text/html" not in r.headers.get("content-type", "").lower()
        body = (first + _read(r)).decode("utf-8", "replace")
    lines = [l.strip() for l in body.splitlines() if l.strip()]
    uris = [l for l in lines if not l.startswith("#")]
    if not uris:
        return False
    target = urljoin(url, uris[0])
    if any(l.startswith("#EXT-X-STREAM-INF") for l in lines):   # playlist maestra
        return depth < 2 and probe(target, depth + 1)
    with _get(target, {"Range": "bytes=0-1023"}) as r2:           # primer segmento
        return r2.status_code in (200, 206)


def is_alive(url):
    for _ in range(2):
        try:
            if probe(url):
                return True
        except Exception:
            pass
    return False


# ---------- Main ----------
def main():
    kr = requests.get(f"{REST}/app_config", headers=HDR,
                      params={"key": "eq.aes_key", "select": "value"}, timeout=30)
    kr.raise_for_status()
    rows = kr.json()
    if not rows:
        sys.exit("No existe aes_key en app_config (¿ejecutaste schema.sql?)")
    aes = AESGCM(bytes.fromhex(rows[0]["value"].strip()))

    chans = fetch_all("channels", {"select": "id,name,stream_url_enc,is_active,fail_count", "order": "id"})
    print(f"Revisando {len(chans)} canales…")

    def work(c):
        try:
            raw = base64.b64decode(c["stream_url_enc"])
            url = aes.decrypt(raw[:12], raw[12:], None).decode()
        except Exception:
            return c, None  # no descifrable: se ignora
        return c, is_alive(url)

    with ThreadPoolExecutor(WORKERS) as ex:
        results = list(ex.map(work, chans))

    checked = [(c, ok) for c, ok in results if ok is not None]
    skipped = len(results) - len(checked)
    alive = [c for c, ok in checked if ok]
    dead = [c for c, ok in checked if not ok]
    ratio = len(dead) / max(len(checked), 1)
    print(f"OK: {len(alive)} · caídos: {len(dead)} · sin descifrar: {skipped}")

    if len(checked) >= 10 and ratio > MAX_DEAD_RATIO:
        sys.exit(f"Caídos {ratio:.0%} > {MAX_DEAD_RATIO:.0%}: probable fallo de red del runner. No se cambia nada.")

    now = datetime.now(timezone.utc).isoformat()
    recovered = [c["name"] for c in alive if not c["is_active"]]
    patch([c["id"] for c in alive], {"is_active": True, "fail_count": 0, "last_checked_at": now})

    by_count, disabled = {}, []
    for c in dead:
        n = c["fail_count"] + 1
        by_count.setdefault(n, []).append(c["id"])
        if n >= FAIL_LIMIT and c["is_active"]:
            disabled.append(c["name"])
    for n, ids in by_count.items():
        payload = {"fail_count": n, "last_checked_at": now}
        if n >= FAIL_LIMIT:
            payload["is_active"] = False
        patch(ids, payload)

    if disabled:
        print(f"Desactivados ({len(disabled)}): " + ", ".join(disabled[:50]))
    if recovered:
        print(f"Reactivados ({len(recovered)}): " + ", ".join(recovered[:50]))


if __name__ == "__main__":
    main()
