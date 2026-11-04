"""Prova l'interfaccia grafica sul telefono simulato. La lancia ci/test.sh, che prepara
FAKE_PHONE, LOG_DIR e l'adb finto nel PATH."""

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
check("la pagina ha il token", ui.Handler.token in html and "__TOKEN__" not in html)
check("senza token: vietato", call("env", token="sbagliato")[0] == 403)
check("da un altro host: vietato", call("env", host="evil.example:80")[0] == 403)

code, env = call("env")
check("trova adb e sh", code == 200 and env["adb"] and env["sh"], env)

code, d = call("devices")
check("vede il telefono finto", code == 200 and d["devices"][0]["serial"] == "FAKE123456"
      and d["devices"][0]["state"] == "device", d)
S = {"serial": "FAKE123456"}

code, kv = call("identify", S)
check("identifica il modello", code == 200 and kv.get("MODEL") == "SM-A546B", kv)
code, r = call("confirm", {**S, "name": "Galaxy A54 5G"})
check("salva il nome confermato", code == 200 and call("identify", S)[1].get("CONFIDENCE") == "confermato", r)

code, info = call("info", S)
# Il telefono finto legge /proc/meminfo del computer: su macOS non c'è.
check("legge la memoria libera", code == 200 and (isinstance(info["ram_free"], int) or not Path("/proc/meminfo").exists()), info)

code, a = call("apps", S)
apps = {x["package"]: x for x in a.get("apps", [])}
check("elenca le app con il verdetto", code == 200 and apps["com.google.android.gms"]["verdict"] == "mai"
      and apps["com.samsung.android.bixby.agent"]["verdict"] == "via", a)
check("nomi in italiano e inglese", apps["com.facebook.appmanager"]["name"] ==
      {"it": "Installer nascosto di Facebook", "en": "Hidden Facebook installer"}, apps["com.facebook.appmanager"])
check("motivo separato e tradotto", apps["com.sec.android.app.launcher"]["reason"] ==
      {"it": "app predefinita: HOME", "en": "default app: HOME"}, apps["com.sec.android.app.launcher"])
check("componente del chip in inglese", apps["com.qualcomm.qti.telephonyservice"]["name"]["en"].startswith("Chip component"),
      apps["com.qualcomm.qti.telephonyservice"])
check("senza nome: niente motivo finto", apps["com.vendor.mystery"]["reason"] is None, apps["com.vendor.mystery"])
names_it = set(re.findall(r"^([a-z][A-Za-z0-9_.]+)\t", (ROOT / "lib.sh").read_text(), re.M))
missing = sorted(names_it - set(json.loads((ROOT / "ui" / "app_names_en.json").read_text())))
check("ogni nome italiano ha l'inglese", not missing, missing)

code, r = call("disable", {**S, "packages": ["com.x.a%d" % i for i in range(11)]})
check("rifiuta più di 10 app", code == 400 and r["error"] == "too_many" and r["params"]["max"] == 10, r)
code, r = call("disable", {**S, "packages": ["com.x; rm -rf /"]})
check("rifiuta nomi strani", code == 400 and r["error"] == "bad_package", r)
code, r = call("disable", {"serial": "$(reboot)", "packages": ["com.facebook.appmanager"]})
check("rifiuta telefoni strani", code == 400 and r["error"] == "bad_target", r)

code, r = call("disable", {**S, "packages": ["com.google.android.gms", "com.samsung.android.bixby.agent"]})
check("disable.sh rifiuta le mai", "com.google.android.gms" in r.get("refused", []), r)
check("spegne Bixby", r.get("off") == ["com.samsung.android.bixby.agent"] and is_off("com.samsung.android.bixby.agent"), r)

code, r = call("disable", {**S, "packages": ["com.vendor.lockedapp"]})
check("segnala l'app che il telefono rifiuta", r.get("failed") == ["com.vendor.lockedapp"], r)
code, r = call("disable", {**S, "packages": ["com.vendor.lockedapp"], "uninstall": True})
check("la toglie per l'utente su richiesta", r.get("removed") == ["com.vendor.lockedapp"], r)

code, r = call("check", S)
check("check.sh: tutto a posto", code == 200 and r["rc"] == 0, r)

code, r = call("reboot", S)
check("riavvia e aspetta il telefono", code == 200 and r.get("ok"), r)

code, r = call("undo", {**S, "packages": ["com.samsung.android.bixby.agent", "com.vendor.lockedapp"]})
check("riaccende il gruppo", sorted(r.get("restored", [])) == ["com.samsung.android.bixby.agent", "com.vendor.lockedapp"]
      and not is_off("com.samsung.android.bixby.agent"), r)

check("errori del telefono hanno un codice", ui.phone_error("Nessun telefono collegato.").code == "disconnected"
      and ui.phone_error("Consentire il debug USB?").code == "unauthorized")
check("nome con parentesi non è un motivo", ui.split_name("Pagine gialle (nome delle aziende)") == ("Pagine gialle (nome delle aziende)", ""))

code, r = call("quit")
check("si chiude", code == 200)

print()
if fails:
    print(f"{fails} test dell'interfaccia falliti.")
    sys.exit(1)
print("Interfaccia: tutti i test passati.")
