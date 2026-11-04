#!/usr/bin/env python3
"""Phone Detox app: a step-by-step cleanup wizard that runs in your browser.

The page talks to this small local server, which runs the project's own scripts
(identify.sh, info.sh, candidates.sh, disable.sh, undo.sh, check.sh). The safety rules live in
those scripts; this is only the friendly face.

    python3 ui/phone_detox_ui.py               opens the browser
    python3 ui/phone_detox_ui.py --no-browser --port 8765

Needs only Python 3.8+ (standard library), adb (the app can download it) and a POSIX sh
(on Windows, the one that comes with Git for Windows).
"""

import argparse
import io
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import webbrowser
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = Path(__file__).resolve().parent
PAGE = UI / "index.html"
LOCAL_TOOLS = ROOT / "platform-tools"
ADB_URL = "https://dl.google.com/android/repository/platform-tools-latest-{}.zip"

PKG_RE = re.compile(r"^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$")
TARGET_RE = re.compile(r"^[A-Za-z0-9._:\-]{1,128}$")
ADDR_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}:\d{1,5}$")
VERDICTS = ("mai", "serve", "via", "dubbio", "tua")
ROW_RE = re.compile(r"^(mai|serve|via|dubbio|tua)\s+(on|off|tolta)\s+(\S+)\s*(.*)$")
MAX_GROUP = 10

# Reasons that classify() in lib.sh appends in brackets: Italian pattern -> English.
REASONS = [
    (re.compile(r"^Android la tiene sempre accesa$"), "Android always keeps it on"),
    (re.compile(r"^app predefinita: (\w+)$"), r"default app: \1"),
    (re.compile(r"^tastiera in uso$"), "keyboard in use"),
    (re.compile(r"^amministratore del dispositivo$"), "device administrator"),
    (re.compile(r"^ha salvato una rete Wi-Fi: spegnerla la cancella$"), "it saved a Wi-Fi network: turning it off deletes it"),
    (re.compile(r"^servizio di accessibilità acceso$"), "accessibility service in use"),
]
CHIP_IT = "Componente del chip: rete, chiamate, sensori"

# One phone operation at a time.
PHONE_LOCK = threading.Lock()


class UserError(Exception):
    """An error the page shows in the user's language: a code plus optional details."""

    def __init__(self, code, detail="", **params):
        super().__init__(code)
        self.code, self.detail, self.params = code, detail, params


def load_names_en():
    try:
        return json.loads((UI / "app_names_en.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


NAMES_EN = load_names_en()


# --------------------------------------------------------------------------------------------
# Where sh and adb are

def tool_env():
    env = dict(os.environ)
    # adb downloaded by the app (or unzipped by hand) next to the project wins.
    if LOCAL_TOOLS.is_dir():
        env["PATH"] = str(LOCAL_TOOLS) + os.pathsep + env.get("PATH", "")
    return env


def find_sh():
    found = shutil.which("sh") or shutil.which("bash")
    if os.name != "nt":
        return found or "/bin/sh"
    if found and "system32" not in found.lower():  # WSL's bash.exe cannot see Windows adb
        return found
    for base in (os.environ.get("ProgramFiles", r"C:\Program Files"),
                 os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
                 os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs")):
        for rel in (r"Git\bin\sh.exe", r"Git\usr\bin\sh.exe", r"Git\bin\bash.exe"):
            p = os.path.join(base, rel)
            if os.path.isfile(p):
                return p
    return None


def find_adb():
    return shutil.which("adb", path=tool_env().get("PATH"))


def system_name():
    if sys.platform == "darwin":
        return "mac"
    if os.name == "nt":
        return "windows"
    return "linux"


# --------------------------------------------------------------------------------------------
# Running scripts and adb

def run_script(name, args=(), extra_env=None, timeout=600):
    sh = find_sh()
    if not sh:
        raise UserError("no_sh")
    if not find_adb():
        raise UserError("no_adb")
    env = tool_env()
    if extra_env:
        env.update(extra_env)
    try:
        p = subprocess.run([sh, (ROOT / name).as_posix(), *args], cwd=str(ROOT), env=env,
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout, encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        raise UserError("timeout")
    return p.returncode, p.stdout.replace("\r", "")


def run_adb(args, timeout=30):
    adb = find_adb()
    if not adb:
        raise UserError("no_adb")
    try:
        p = subprocess.run([adb, *args], env=tool_env(), stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
                           encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return 124, ""
    return p.returncode, p.stdout.replace("\r", "")


def phone_error(out):
    """Turns a script failure into an error code the page can explain."""
    if "unauthorized" in out or "Consentire il debug" in out:
        return UserError("unauthorized", out)
    if "Nessun telefono" in out or "Non riesco a raggiungere" in out or "perso il collegamento" in out:
        return UserError("disconnected", out)
    return UserError("read_failed", out)


def target_arg(data):
    t = str(data.get("serial") or "")
    if not TARGET_RE.match(t):
        raise UserError("bad_target")
    return t


def packages_arg(data, limit=MAX_GROUP):
    pkgs = data.get("packages") or []
    if not isinstance(pkgs, list) or not pkgs:
        raise UserError("no_apps")
    pkgs = list(dict.fromkeys(str(p) for p in pkgs))
    bad = [p for p in pkgs if not PKG_RE.match(p)]
    if bad:
        raise UserError("bad_package", package=bad[0])
    if limit and len(pkgs) > limit:
        raise UserError("too_many", max=limit)
    return pkgs


# --------------------------------------------------------------------------------------------
# Actions

def act_env(_):
    return {"adb": bool(find_adb()), "sh": bool(find_sh()), "os": system_name(), "root": str(ROOT),
            "changes": str(Path(os.environ.get("LOG_DIR") or ROOT / "changes"))}


def act_install_adb(_):
    """Downloads Google's official platform-tools into the project folder."""
    url = ADB_URL.format({"mac": "darwin"}.get(system_name(), system_name()))
    try:
        with urllib.request.urlopen(url, timeout=120) as r:
            data = r.read()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = z.namelist()
            if not all(n.startswith("platform-tools/") and ".." not in n for n in names):
                raise UserError("download_failed", "unexpected archive layout")
            with tempfile.TemporaryDirectory(dir=str(ROOT)) as tmp:
                z.extractall(tmp)
                if LOCAL_TOOLS.exists():
                    shutil.rmtree(LOCAL_TOOLS)
                shutil.move(os.path.join(tmp, "platform-tools"), str(LOCAL_TOOLS))
    except UserError:
        raise
    except Exception as e:
        raise UserError("download_failed", str(e))
    if os.name != "nt":  # zip files do not keep the executable bit
        for f in LOCAL_TOOLS.iterdir():
            if f.is_file() and "." not in f.name:
                f.chmod(f.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    if not find_adb():
        raise UserError("download_failed", "adb not found after download")
    return {"ok": True}


def act_devices(_):
    if not find_adb():
        return {"adb": False, "devices": []}
    run_adb(["start-server"], timeout=20)
    rc, out = run_adb(["devices", "-l"], timeout=15)
    devices = []
    for line in out.splitlines()[1:]:
        if not line.strip() or line.startswith("*"):
            continue
        # "no permissions (...)" is a state with spaces: keep it whole.
        m = re.match(r"^(\S+)\s+(no permissions.*?\))?\s*(\S+)?(.*)$", line)
        serial, state = m.group(1), "no-permissions" if m.group(2) else (m.group(3) or "")
        info = dict(x.split(":", 1) for x in line.split() if ":" in x and not x.startswith("(") and "=" not in x)
        devices.append({"serial": serial, "state": state, "model": info.get("model", "").replace("_", " ")})
    return {"adb": True, "devices": devices}


def act_pair(data):
    addr, code = str(data.get("address", "")), str(data.get("code", ""))
    if not ADDR_RE.match(addr) or not re.match(r"^\d{6}$", code):
        raise UserError("bad_pair")
    rc, out = run_adb(["pair", addr, code], timeout=30)
    return {"ok": rc == 0 and "Success" in out, "output": out}


def act_connect(data):
    addr = str(data.get("address", ""))
    if not ADDR_RE.match(addr):
        raise UserError("bad_addr")
    rc, out = run_adb(["connect", addr], timeout=30)
    return {"ok": "connected" in out and "cannot" not in out and "failed" not in out, "output": out}


def act_identify(data):
    rc, out = run_script("identify.sh", [target_arg(data), "--kv"], timeout=120)
    kv = dict(l.split("=", 1) for l in out.splitlines() if re.match(r"^[A-Z_]+=", l))
    if rc != 0 or not kv:
        raise phone_error(out)
    return kv


def act_confirm(data):
    name = str(data.get("name", "")).strip()
    if not name or len(name) > 80 or "\n" in name:
        raise UserError("bad_name")
    rc, out = run_script("identify.sh", [target_arg(data), "--conferma", name], timeout=60)
    if rc != 0:
        raise phone_error(out)
    return {"ok": True}


def act_info(data):
    rc, out = run_script("info.sh", [target_arg(data)], timeout=120)
    if rc != 0:
        raise phone_error(out)
    m = re.search(r"RAM: (\d+) MB, libera ora (\d+) MB", out)
    return {"ram_total": int(m.group(1)) if m else None, "ram_free": int(m.group(2)) if m else None,
            "managed": "è gestito" in out, "output": out}


def split_name(raw):
    """'Name (reason)' -> (name, reason) when the bracket is one of the known reasons."""
    m = re.match(r"^(.*?)\s*\(([^()]*)\)$", raw)
    if m and any(p.match(m.group(2)) for p, _ in REASONS):
        return m.group(1), m.group(2)
    return raw, ""


def reason_en(reason):
    for p, en in REASONS:
        if p.match(reason):
            return p.sub(en, reason)
    return reason


def act_apps(data):
    rc, out = run_script("candidates.sh", [target_arg(data)], timeout=300)
    apps = []
    for line in out.splitlines():
        m = ROW_RE.match(line)
        if not m:
            continue
        pkg = m.group(3)
        name, reason = split_name(m.group(4).strip())
        en = NAMES_EN.get(pkg) or (NAMES_EN.get("_chip") if name == CHIP_IT else "")
        apps.append({"verdict": m.group(1), "state": m.group(2), "package": pkg,
                     "name": {"it": name, "en": en or name},
                     "reason": {"it": reason, "en": reason_en(reason)} if reason else None})
    if rc != 0 or not apps:
        raise phone_error(out)
    return {"apps": apps}


def parse_changes(out):
    res = {"off": [], "removed": [], "restored": [], "failed": [], "refused": [], "skipped": []}
    keys = {"spenta": "off", "tolta": "removed", "accesa": "restored", "ERRORE": "failed",
            "NO": "refused", "salto": "skipped"}
    for line in out.splitlines():
        m = re.match(r"^\s+(spenta|tolta|accesa|ERRORE|NO|salto)\s+([A-Za-z0-9_.]+)", line)
        if m:
            res[keys[m.group(1)]].append(m.group(2).rstrip(":"))
    return res


def act_disable(data):
    pkgs = packages_arg(data)
    env = {"YES": "1"}
    if data.get("uninstall"):
        env["UNINSTALL"] = "1"
    rc, out = run_script("disable.sh", [target_arg(data), *pkgs], env, timeout=600)
    res = parse_changes(out)
    if rc != 0 and not any(res.values()):
        raise phone_error(out)
    return {"rc": rc, "output": out, **res}


def act_undo(data):
    args = [target_arg(data)]
    if data.get("all"):
        args.append("--all")
    elif data.get("packages"):
        args += packages_arg(data, limit=None)
    rc, out = run_script("undo.sh", args, timeout=900)
    res = parse_changes(out)
    if rc != 0 and not any(res.values()):
        raise phone_error(out)
    return {"rc": rc, "output": out, "nothing": "Non trovo modifiche" in out, **res}


def act_check(data):
    args = [target_arg(data)] + (["--fix"] if data.get("fix") else [])
    rc, out = run_script("check.sh", args, timeout=600)
    changed = len(re.findall(r"^\s+CAMBIATO", out, re.M))
    fixed = len(re.findall(r"^\s+sistemato", out, re.M))
    if rc != 0 and not changed and "Nessuna modifica" not in out:
        raise phone_error(out)
    return {"rc": rc, "output": out, "changed": changed, "fixed": fixed, "empty": "Nessuna modifica" in out}


def act_reboot(data):
    serial = target_arg(data)
    rc, _ = run_adb(["-s", serial, "reboot"], timeout=30)
    if rc != 0:
        raise UserError("reboot_refused")
    time.sleep(5)
    deadline = time.time() + 300
    while time.time() < deadline:
        if ADDR_RE.match(serial):
            run_adb(["connect", serial], timeout=10)
        rc, out = run_adb(["-s", serial, "shell", "getprop", "sys.boot_completed"], timeout=10)
        if rc == 0 and out.strip() == "1":
            time.sleep(3)
            return {"ok": True}
        time.sleep(3)
    return {"ok": False}


ACTIONS = {  # name: (function, needs the phone lock)
    "env": (act_env, False), "devices": (act_devices, False), "pair": (act_pair, False),
    "connect": (act_connect, False), "install_adb": (act_install_adb, True),
    "identify": (act_identify, True), "confirm": (act_confirm, True), "info": (act_info, True),
    "apps": (act_apps, True), "disable": (act_disable, True), "undo": (act_undo, True),
    "check": (act_check, True), "reboot": (act_reboot, True),
}


# --------------------------------------------------------------------------------------------
# Local server

class Handler(BaseHTTPRequestHandler):
    server_version = "PhoneDetox"
    token = ""
    port = 0

    def log_message(self, fmt, *args):  # keep the terminal quiet
        pass

    def _host_ok(self):
        # Only from this computer: blocks web pages that try to reach the server.
        return self.headers.get("Host", "") in (f"127.0.0.1:{self.port}", f"localhost:{self.port}")

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self._host_ok():
            return self._send(403, {"error": "forbidden"})
        if self.path.split("?")[0] in ("/", "/index.html"):
            html = PAGE.read_text(encoding="utf-8").replace("__TOKEN__", self.token)
            return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
        return self._send(404, {"error": "not_found"})

    def do_POST(self):
        if not self._host_ok() or self.headers.get("X-Token") != self.token:
            return self._send(403, {"error": "forbidden"})
        name = self.path[len("/api/"):] if self.path.startswith("/api/") else ""
        if name == "quit":
            self._send(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if name not in ACTIONS:
            return self._send(404, {"error": "not_found"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
            data = json.loads(self.rfile.read(length) or b"{}") if length < 100_000 else {}
            if not isinstance(data, dict):
                raise ValueError
        except ValueError:
            return self._send(400, {"error": "bad_request"})
        fn, locked = ACTIONS[name]
        try:
            if locked:
                if not PHONE_LOCK.acquire(timeout=1):
                    return self._send(409, {"error": "busy"})
                try:
                    result = fn(data)
                finally:
                    PHONE_LOCK.release()
            else:
                result = fn(data)
        except UserError as e:
            return self._send(400, {"error": e.code, "params": e.params, "detail": e.detail})
        except Exception as e:  # show the error instead of leaving the page hanging
            return self._send(500, {"error": "unexpected", "detail": repr(e)})
        return self._send(200, result)


def make_server(port=0):
    Handler.token = secrets.token_urlsafe(24)
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    Handler.port = httpd.server_address[1]
    return httpd


def main():
    ap = argparse.ArgumentParser(description="Phone Detox app")
    ap.add_argument("--port", type=int, default=0, help="port (default: a free one)")
    ap.add_argument("--no-browser", action="store_true", help="do not open the browser")
    a = ap.parse_args()
    httpd = make_server(a.port)
    url = f"http://127.0.0.1:{Handler.port}/"
    print("Phone Detox:", url)
    print("  EN  It opens in your browser. If it does not, copy the address above into it.")
    print("      Keep this window open while you use it. To quit: the Close button, or Ctrl+C here.")
    print("  IT  Si apre nel browser. Se non si apre, copia l'indirizzo qui sopra nel browser.")
    print("      Tieni aperta questa finestra mentre lo usi. Per chiudere: il pulsante Chiudi, o Ctrl+C qui.")
    if not a.no_browser:
        threading.Timer(0.5, webbrowser.open, (url,)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    print("Closed. Remember to turn off USB debugging on the phone. / Chiuso. Ricordati di spegnere il Debug USB.")


if __name__ == "__main__":
    main()
