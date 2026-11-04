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
ro.product.brand=samsung
ro.product.device=a54x
ro.csc.sales_code=ITV
sys.boot_completed=1
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

echo "identify.sh"
out=$(sh "$ROOT/identify.sh" 2>&1)
expect "solo codice: certezza bassa" 'Certezza +bassa'                                  "$out"
expect "serie Samsung dal codice"   'Galaxy A, variante europea'                        "$out"
expect "interfaccia One UI"         'One UI 6\.1'                                       "$out"
expect "chiede di confermare"       'identify.sh +--conferma'                           "$out"
echo "Galaxy A54 5G" > "$P/settings_global_device_name"
out=$(sh "$ROOT/identify.sh" --kv 2>&1)
expect "nome dal dispositivo"       '^MARKET=Galaxy A54 5G$'                            "$out"
expect "certezza media"             '^CONFIDENCE=media$'                                "$out"
expect "famiglia samsung"           '^FAMILY=samsung$'                                  "$out"
expect "regione CSC"                '^REGION=ITV$'                                      "$out"
sh "$ROOT/identify.sh" --conferma "Galaxy A54 5G" >/dev/null
out=$(sh "$ROOT/identify.sh" --kv 2>&1)
expect "confermato dall'utente"     '^CONFIDENCE=confermato$'                           "$out"
out=$(FAKE_PHONE="$WORK/xiaomi" sh -c 'mkdir -p "$FAKE_PHONE"; printf "android\n" > "$FAKE_PHONE/all"; printf "ro.product.manufacturer=Xiaomi\nro.product.brand=Redmi\nro.product.model=23090RA98G\nro.product.marketname=Redmi Note 13 Pro\nro.product.device=garnet\nro.mi.os.version.name=OS1.0\nro.product.mod_device=garnet_eea_global\nro.serialno=X2\n" > "$FAKE_PHONE/props"; sh "$1/identify.sh" --kv' _ "$ROOT" 2>&1)
expect "Xiaomi: nome dalla proprietà" '^MARKET=Redmi Note 13 Pro$'                       "$out"
expect "Xiaomi: certezza alta"      '^CONFIDENCE=alta$'                                 "$out"
expect "Xiaomi: HyperOS"            '^SKIN=HyperOS 1\.0$'                               "$out"
expect "Xiaomi: variante"           '^REGION=garnet_eea_global$'                        "$out"
expect "Xiaomi: ricerca con codename" '^QUERY=Redmi Note 13 Pro 23090RA98G garnet$'     "$out"

echo "info.sh"
out=$(sh "$ROOT/info.sh" 2>&1)
expect "modello"                    'samsung Galaxy A54 5G \(SM-A546B\), Android 14'    "$out"
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
LOG="$LOG_DIR/samsung-SM-A546B-FAKE123456.txt"
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

echo "guida.sh"
# Il nome confermato è andato via con changes/: la guida lo richiede.
# Risposte: backup sì, modello giusto, nome giusto, app 1, procedo, niente riavvio,
# funziona tutto, un altro gruppo sì, poi Invio per finire.
out=$(printf 's\ns\ns\n1\ns\nn\ns\ns\n\n' | GUIDA_STDIN=1 sh "$ROOT/guida.sh" 2>&1)
expect "chiede il numero di modello" 'Leggi SM-A546B\?'                                 "$out"
expect "salva il nome confermato"   'questo telefono è un Galaxy A54 5G'                "$out"
expect "elenca le app da spegnere"  ' 1\) Installer nascosto di Facebook'               "$out"
expect "spegne quella scelta"       'spenta +com.facebook.appmanager'                   "$out"
expect "arriva alla fine"           '7\. Fine'                                          "$out"
off com.facebook.appmanager && ok "Facebook spenta dalla guida" || ko "Facebook spenta dalla guida"
# Se qualcosa non va, la guida riaccende il gruppo.
# Seconda volta: il telefono è già confermato. Bixby è la numero 2; qualcosa non va.
out=$(printf 's\n2\ns\nn\nn\nn\n' | GUIDA_STDIN=1 sh "$ROOT/guida.sh" 2>&1)
expect "riconosce il telefono"      'Galaxy A54 5G che hai già confermato'              "$out"
expect "annulla il gruppo se non va" 'accesa +com.samsung.android.bixby.agent'         "$out"
off com.samsung.android.bixby.agent && ko "Bixby riaccesa" || ok "Bixby riaccesa"

echo "interfaccia grafica"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/ci/test_ui.py" || fails=$((fails + 1))
else
  echo "  salto: manca python3"
fi

echo
if [ "$fails" -gt 0 ]; then echo "$fails test falliti."; exit 1; fi
echo "Tutti i test passati."
