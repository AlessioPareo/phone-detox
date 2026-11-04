#!/bin/sh
# Prova tutti gli script su un telefono simulato (ci/fake-adb), senza telefono vero.
#   sh ci/test.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t phonetest)
[ -n "$KEEP" ] || trap 'rm -rf "$WORK"' EXIT
export FAKE_PHONE="$WORK/phone" LOG_DIR="$WORK/changes"
export PATH="$ROOT/ci/fake-adb:$PATH"
mkdir -p "$FAKE_PHONE"
P=$FAKE_PHONE

# Un Samsung finto: un po' di sistema, un po' di bloatware, un'app dell'utente.
cat > "$P/all" <<'EOF'
android
com.android.systemui
com.android.phone
com.google.android.gms
com.android.vending
com.sec.android.app.launcher
com.samsung.android.honeyboard
com.samsung.android.dialer
com.google.android.apps.messaging
com.samsung.android.bixby.agent
com.facebook.appmanager
com.samsung.android.game.gamehome
com.samsung.android.app.tips
com.samsung.android.fmm
com.qualcomm.qti.telephonyservice
com.vendor.persistent
com.vendor.wifiowner
com.vendor.mystery
com.vendor.lockedapp
com.whatsapp
EOF
printf 'com.whatsapp\n' > "$P/third"
: > "$P/flags"
while read -r p; do
  case "$p" in
    com.vendor.persistent) printf '%s\tSYSTEM HAS_CODE PERSISTENT\n' "$p" ;;
    *)                     printf '%s\tSYSTEM HAS_CODE\n' "$p" ;;
  esac >> "$P/flags"
done < "$P/all"
printf 'com.samsung.android.app.tips\n' > "$P/off"
printf 'com.vendor.lockedapp\n' > "$P/refuse"
printf 'com.sec.android.app.launcher\n' > "$P/role_HOME"
printf 'com.samsung.android.dialer\n' > "$P/role_DIALER"
printf 'com.google.android.apps.messaging\n' > "$P/role_SMS"
printf 'com.samsung.android.honeyboard/.service.HoneyBoardService\n' > "$P/settings_secure_default_input_method"
printf 'cname=com.vendor.wifiowner\n' > "$P/wifi"
printf '  Admin: ComponentInfo{com.samsung.android.fmm/com.samsung.android.fmm.admin.Receiver}\n' > "$P/device_policy"
cat > "$P/props" <<'EOF'
ro.product.manufacturer=samsung
ro.product.model=SM-A546B
ro.serialno=FAKE123456
ro.build.version.release=14
ro.build.version.sdk=34
ro.build.version.oneui=60100
EOF

fails=0
ok() { echo "  ok   $1"; }
ko() { echo "  FAIL $1"; fails=$((fails + 1)); }
expect() { # descrizione, testo atteso, output
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then ok "$1"; else ko "$1"; printf '%s\n' "$3" | sed 's/^/       | /'; fi
}
off() { grep -qxF "$1" "$P/off"; }
removed() { grep -qxF "$1" "$P/removed" 2>/dev/null; }

echo "candidates.sh"
out=$(sh "$ROOT/candidates.sh" 2>&1)
expect "gms è mai"                  '^mai +on +com.google.android.gms '               "$out"
expect "Home attuale è mai"         '^mai .*com.sec.android.app.launcher .*predefinita: HOME' "$out"
expect "tastiera in uso è mai"      '^mai .*com.samsung.android.honeyboard .*tastiera in uso' "$out"
expect "Messaggi (SMS) è mai"       '^mai .*com.google.android.apps.messaging .*predefinita: SMS' "$out"
expect "prefisso qualcomm è mai"    '^mai .*com.qualcomm.qti.telephonyservice'          "$out"
expect "PERSISTENT è mai"           '^mai .*com.vendor.persistent .*sempre accesa'      "$out"
expect "chi ha salvato il Wi-Fi è mai" '^mai .*com.vendor.wifiowner .*Wi-Fi'             "$out"
expect "amministratore è mai"       '^mai .*com.samsung.android.fmm .*amministratore'   "$out"
expect "Bixby è via"                '^via +on +com.samsung.android.bixby.agent'         "$out"
expect "Tips già spenta"            '^via +off +com.samsung.android.app.tips'           "$out"
expect "sconosciuta è dubbio"       '^dubbio +on +com.vendor.mystery'                   "$out"
expect "WhatsApp è tua"             '^tua +on +com.whatsapp'                            "$out"
expect "riepilogo"                  '^mai [0-9]+ \| serve [0-9]+ \| via 4 \| dubbio 2 \| tua 1' "$out"

echo "info.sh"
out=$(sh "$ROOT/info.sh" 2>&1)
expect "modello"                    'samsung SM-A546B, Android 14'                      "$out"
expect "consiglio Samsung"          'UNINSTALL=1'                                       "$out"

echo "disable.sh"
out=$(sh "$ROOT/disable.sh" com.samsung.android.bixby.agent </dev/null 2>&1)
expect "senza YES è a vuoto"        'Prova a vuoto'                                     "$out"
if off com.samsung.android.bixby.agent; then ko "a vuoto non spegne"; else ok "a vuoto non spegne"; fi

out=$(YES=1 sh "$ROOT/disable.sh" com.google.android.gms com.samsung.android.dialer com.samsung.android.app.tips com.nope.app 2>&1)
expect "rifiuta gms"                'NO +com.google.android.gms'                         "$out"
expect "rifiuta il telefono predefinito" 'NO +com.samsung.android.dialer'                "$out"
expect "salta già spenta"           'salto +com.samsung.android.app.tips'               "$out"
expect "salta inesistente"          'salto +com.nope.app'                               "$out"
expect "niente da fare"             'Niente da fare'                                    "$out"
if off com.google.android.gms; then ko "gms resta accesa"; else ok "gms resta accesa"; fi

out=$(YES=1 sh "$ROOT/disable.sh" FAKE123456 com.samsung.android.bixby.agent com.facebook.appmanager 2>&1)
expect "spegne Bixby"               'spenta +com.samsung.android.bixby.agent'           "$out"
off com.samsung.android.bixby.agent && off com.facebook.appmanager && ok "sono spente" || ko "sono spente"
LOG=$(ls "$LOG_DIR"/*.txt)
grep -qx 'off com.facebook.appmanager' "$LOG" && ok "lista sul computer" || ko "lista sul computer"
grep -qx 'off com.facebook.appmanager' "$P/tmp/phone-detox.txt" && ok "lista sul telefono" || ko "lista sul telefono"

out=$(YES=1 sh "$ROOT/disable.sh" com.vendor.lockedapp 2>&1 || true)
expect "app che il telefono rifiuta" 'ERRORE +com.vendor.lockedapp'                     "$out"
expect "suggerisce UNINSTALL=1"     'UNINSTALL=1'                                       "$out"
out=$(YES=1 UNINSTALL=1 sh "$ROOT/disable.sh" com.vendor.lockedapp 2>&1)
expect "la toglie per l'utente"     'tolta +com.vendor.lockedapp'                       "$out"
removed com.vendor.lockedapp && ok "è tolta" || ko "è tolta"

printf 'com.samsung.android.game.gamehome\n# commento\n' > "$WORK/lista.txt"
YES=1 sh "$ROOT/disable.sh" -f "$WORK/lista.txt" >/dev/null 2>&1
off com.samsung.android.game.gamehome && ok "legge una lista con -f" || ko "legge una lista con -f"

echo "check.sh"
# Un aggiornamento riaccende Bixby.
grep -vx com.samsung.android.bixby.agent "$P/off" > "$P/off.t"; mv "$P/off.t" "$P/off"
out=$(sh "$ROOT/check.sh" 2>&1 || true)
expect "si accorge che Bixby è tornata" 'CAMBIATO +com.samsung.android.bixby.agent'    "$out"
out=$(sh "$ROOT/check.sh" --fix 2>&1)
expect "la rispegne"                'sistemato +com.samsung.android.bixby.agent'        "$out"
off com.samsung.android.bixby.agent && ok "Bixby di nuovo spenta" || ko "Bixby di nuovo spenta"

echo "undo.sh"
out=$(sh "$ROOT/undo.sh" com.facebook.appmanager 2>&1)
expect "una sola app"               'accesa +com.facebook.appmanager'                   "$out"
off com.samsung.android.bixby.agent && ok "le altre restano spente" || ko "le altre restano spente"
grep -q 'com.facebook.appmanager' "$LOG" && ko "tolta dalla lista" || ok "tolta dalla lista"

# Da un altro computer: niente lista locale, solo quella sul telefono.
rm -rf "$LOG_DIR"
out=$(sh "$ROOT/undo.sh" 2>&1)
expect "riaccende Bixby"            'accesa +com.samsung.android.bixby.agent'           "$out"
expect "rimette l'app tolta"        'accesa +com.vendor.lockedapp'                      "$out"
removed com.vendor.lockedapp && ko "lockedapp di nuovo installata" || ok "lockedapp di nuovo installata"
off com.samsung.android.game.gamehome && ko "gamehome accesa" || ok "gamehome accesa"
off com.samsung.android.app.tips && ok "non tocca ciò che era spento prima" || ko "non tocca ciò che era spento prima"

out=$(sh "$ROOT/undo.sh" --all 2>&1)
expect "soccorso riaccende tutto"   'accesa +com.samsung.android.app.tips'              "$out"
[ -s "$P/off" ] && ko "nessuna app spenta" || ok "nessuna app spenta"

echo
if [ "$fails" -gt 0 ]; then echo "$fails test falliti."; exit 1; fi
echo "Tutti i test passati."
