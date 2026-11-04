"""Tests the app on the simulated phone. Run by ci/test.sh, which sets up FAKE_PHONE, LOG_DIR
and the fake adb in PATH."""

import json
import os
import re
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ui"))
import phone_detox_ui as ui  # noqa: E402

P = Path(os.environ["FAKE_PHONE"])
fails = 0


def check(desc, cond, extra=""):
    global fails
    print(("  ok   " if cond else "  FAIL ") + desc)
    if not cond:
        fails += 1
        if extra:
            print("       | " + str(extra).replace("\n", "\n       | "))


httpd = ui.make_server(0)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{ui.Handler.port}"


def call(name, data=None, token=None, host=None):
    req = urllib.request.Request(BASE + "/api/" + name, data=json.dumps(data or {}).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "X-Token": token or ui.Handler.token})
    if host:
        req.add_header("Host", host)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def is_off(p):
    f = P / "off"
    return f.exists() and p in f.read_text().split()


with urllib.request.urlopen(BASE + "/", timeout=10) as r:
    html = r.read().decode()
check("the page has the token", ui.Handler.token in html and "__TOKEN__" not in html)
check("no token: forbidden", call("env", token="wrong")[0] == 403)
check("from another host: forbidden", call("env", host="evil.example:80")[0] == 403)

code, env = call("env")
check("finds adb and sh", code == 200 and env["adb"] and env["sh"], env)

code, d = call("devices")
check("sees the fake phone", code == 200 and d["devices"][0]["serial"] == "FAKE123456"
      and d["devices"][0]["state"] == "device", d)
S = {"serial": "FAKE123456"}

code, kv = call("identify", S)
check("identifies the model", code == 200 and kv.get("MODEL") == "SM-A546B", kv)
code, r = call("confirm", {**S, "name": "Galaxy A54 5G"})
check("saves the confirmed name", code == 200 and call("identify", S)[1].get("CONFIDENCE") == "confirmed", r)

code, info = call("info", S)
# The fake phone reads the computer's /proc/meminfo: macOS doesn't have it.
check("reads free memory", code == 200 and (isinstance(info["ram_free"], int) or not Path("/proc/meminfo").exists()), info)
code, info_it = call("info", {**S, "lang": "it"})
check("Italian output when asked, still parsed", code == 200 and "== Telefono" in info_it["output"]
      and (isinstance(info_it["ram_free"], int) or not Path("/proc/meminfo").exists()), info_it)

code, a = call("apps", S)
apps = {x["package"]: x for x in a.get("apps", [])}
check("lists apps with verdicts", code == 200 and apps["com.google.android.gms"]["verdict"] == "never"
      and apps["com.samsung.android.bixby.agent"]["verdict"] == "bloat", a)
check("names in Italian and English", apps["com.facebook.appmanager"]["name"] ==
      {"it": "Installer nascosto di Facebook", "en": "Hidden Facebook installer"}, apps["com.facebook.appmanager"])
check("reason in both languages", apps["com.sec.android.app.launcher"]["reason"] ==
      {"it": "app predefinita: HOME", "en": "default app: HOME"}, apps["com.sec.android.app.launcher"])
check("chip component in English", apps["com.qualcomm.qti.telephonyservice"]["name"]["en"].startswith("Chip component"),
      apps["com.qualcomm.qti.telephonyservice"])
check("no name: no reason", apps["com.vendor.mystery"]["reason"] is None, apps["com.vendor.mystery"])
rows = re.findall(r"^([a-z][A-Za-z0-9_.]+)\t([^\t\n]*)\t?([^\t\n]*)$",
                  (ROOT / "lib.sh").read_text().split("NAMES='")[1].split("'")[0], re.M)
check("every app name has Italian and English", rows and all(it and en for _, it, en in rows),
      [r for r in rows if not (r[1] and r[2])])

code, r = call("disable", {**S, "packages": ["com.x.a%d" % i for i in range(11)]})
check("refuses more than 10 apps", code == 400 and r["error"] == "too_many" and r["params"]["max"] == 10, r)
code, r = call("disable", {**S, "packages": ["com.x; rm -rf /"]})
check("refuses odd names", code == 400 and r["error"] == "bad_package", r)
code, r = call("disable", {"serial": "$(reboot)", "packages": ["com.facebook.appmanager"]})
check("refuses odd phones", code == 400 and r["error"] == "bad_target", r)

code, r = call("disable", {**S, "packages": ["com.google.android.gms", "com.samsung.android.bixby.agent"]})
check("disable.sh refuses never apps", "com.google.android.gms" in r.get("refused", []), r)
check("turns Bixby off", r.get("off") == ["com.samsung.android.bixby.agent"] and is_off("com.samsung.android.bixby.agent"), r)

code, r = call("disable", {**S, "packages": ["com.vendor.lockedapp"], "lang": "it"})
check("reports the app the phone refuses (Italian)", r.get("failed") == ["com.vendor.lockedapp"], r)
code, r = call("disable", {**S, "packages": ["com.vendor.lockedapp"], "uninstall": True})
check("removes it for the user on request", r.get("removed") == ["com.vendor.lockedapp"], r)

code, r = call("check", S)
check("check.sh: all good", code == 200 and r["rc"] == 0 and not r["empty"], r)

code, r = call("reboot", S)
check("restarts and waits for the phone", code == 200 and r.get("ok"), r)

code, r = call("undo", {**S, "packages": ["com.samsung.android.bixby.agent", "com.vendor.lockedapp"]})
check("turns the group back on", sorted(r.get("restored", [])) == ["com.samsung.android.bixby.agent", "com.vendor.lockedapp"]
      and not is_off("com.samsung.android.bixby.agent"), r)

check("phone errors have a code", ui.phone_error("No phone connected.").code == "disconnected"
      and ui.phone_error("Nessun telefono collegato.").code == "disconnected"
      and ui.phone_error('The phone asks "Allow USB debugging?"').code == "unauthorized")

code, r = call("quit")
check("closes", code == 200)

print()
if fails:
    print(f"{fails} app tests failed.")
    sys.exit(1)
print("App: all tests passed.")
