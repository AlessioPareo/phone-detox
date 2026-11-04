#!/bin/sh
# Tests every script on a simulated phone (ci/fake-adb), without a real phone.
#   sh ci/test.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t phonetest)
[ -n "$KEEP" ] || trap 'rm -rf "$WORK"' EXIT
export FAKE_PHONE="$WORK/phone" LOG_DIR="$WORK/changes"
export PATH="$ROOT/ci/fake-adb:$PATH"
# Tests run in English; a few checks switch to Italian with PD_LANG=it.
export PD_LANG=en
mkdir -p "$FAKE_PHONE"
P=$FAKE_PHONE

# A fake Samsung: some system apps, some bloatware, one user app.
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
expect() { # description, expected pattern, output
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then ok "$1"; else ko "$1"; printf '%s\n' "$3" | sed 's/^/       | /'; fi
}
off() { grep -qxF "$1" "$P/off"; }
removed() { grep -qxF "$1" "$P/removed" 2>/dev/null; }

echo "candidates.sh"
out=$(sh "$ROOT/candidates.sh" 2>&1)
expect "gms is never"                  '^never +on +com.google.android.gms '              "$out"
expect "current home is never"         '^never .*com.sec.android.app.launcher .*default app: HOME' "$out"
expect "keyboard in use is never"      '^never .*com.samsung.android.honeyboard .*keyboard in use' "$out"
expect "Messages (SMS) is never"       '^never .*com.google.android.apps.messaging .*default app: SMS' "$out"
expect "qualcomm prefix is never"      '^never .*com.qualcomm.qti.telephonyservice .*Chip component' "$out"
expect "PERSISTENT is never"           '^never .*com.vendor.persistent .*always keeps it on' "$out"
expect "Wi-Fi owner is never"          '^never .*com.vendor.wifiowner .*Wi-Fi'            "$out"
expect "administrator is never"        '^never .*com.samsung.android.fmm .*administrator' "$out"
expect "Bixby is bloat"                '^bloat +on +com.samsung.android.bixby.agent'      "$out"
expect "Facebook name in English"      '^bloat +on +com.facebook.appmanager +Hidden Facebook installer' "$out"
expect "Tips already off"              '^bloat +off +com.samsung.android.app.tips'        "$out"
expect "unknown app is unknown"        '^unknown +on +com.vendor.mystery'                 "$out"
expect "WhatsApp is yours"             '^yours +on +com.whatsapp'                         "$out"
expect "summary"                       '^never [0-9]+ \| useful [0-9]+ \| bloat 4 \| unknown 2 \| yours 1' "$out"
out=$(PD_LANG=it sh "$ROOT/candidates.sh" 2>&1)
expect "Italian: names in Italian"     '^bloat +on +com.facebook.appmanager +Installer nascosto di Facebook' "$out"
expect "Italian: reasons in Italian"   '^never .*com.sec.android.app.launcher .*app predefinita: HOME' "$out"
out=$(sh "$ROOT/candidates.sh" --tsv 2>&1)
expect "tsv: both languages"           "$(printf '^bloat\ton\tcom.facebook.appmanager\tInstaller nascosto di Facebook\tHidden Facebook installer\t\t$')" "$out"

echo "identify.sh"
out=$(sh "$ROOT/identify.sh" 2>&1)
expect "model number only: low"        'Confidence +low'                                  "$out"
expect "Samsung series from the model" 'Galaxy A, European/international variant'         "$out"
expect "One UI skin"                   'One UI 6\.1'                                      "$out"
expect "asks to confirm"               'identify.sh +--confirm'                           "$out"
echo "Galaxy A54 5G" > "$P/settings_global_device_name"
out=$(sh "$ROOT/identify.sh" --kv 2>&1)
expect "name from the device"          '^MARKET=Galaxy A54 5G$'                           "$out"
expect "medium confidence"             '^CONFIDENCE=medium$'                              "$out"
expect "samsung family"                '^FAMILY=samsung$'                                 "$out"
expect "CSC region"                    '^REGION=ITV$'                                     "$out"
sh "$ROOT/identify.sh" --confirm "Galaxy A54 5G" >/dev/null
out=$(sh "$ROOT/identify.sh" --kv 2>&1)
expect "confirmed by the user"         '^CONFIDENCE=confirmed$'                           "$out"
out=$(PD_LANG=it sh "$ROOT/identify.sh" 2>&1)
expect "Italian: card in Italian"      'Certezza +confirmed - confermato dall'"'"'utente' "$out"
out=$(FAKE_PHONE="$WORK/xiaomi" sh -c 'mkdir -p "$FAKE_PHONE"; printf "android\n" > "$FAKE_PHONE/all"; printf "ro.product.manufacturer=Xiaomi\nro.product.brand=Redmi\nro.product.model=23090RA98G\nro.product.marketname=Redmi Note 13 Pro\nro.product.device=garnet\nro.mi.os.version.name=OS1.0\nro.product.mod_device=garnet_eea_global\nro.serialno=X2\n" > "$FAKE_PHONE/props"; sh "$1/identify.sh" --kv' _ "$ROOT" 2>&1)
expect "Xiaomi: name from the property" '^MARKET=Redmi Note 13 Pro$'                      "$out"
expect "Xiaomi: high confidence"       '^CONFIDENCE=high$'                                "$out"
expect "Xiaomi: HyperOS"               '^SKIN=HyperOS 1\.0$'                              "$out"
expect "Xiaomi: variant"               '^REGION=garnet_eea_global$'                       "$out"
expect "Xiaomi: search with codename"  '^QUERY=Redmi Note 13 Pro 23090RA98G garnet$'      "$out"
# A name confirmed before the translation (old file and key) is still read.
idf="$LOG_DIR/samsung-SM-A546B-FAKE123456.identity.txt"
sed 's/^CONFIRMED_NAME=/NOME_CONFERMATO=/' "$idf" > "${idf%.identity.txt}.identita.txt"; rm "$idf"
out=$(sh "$ROOT/identify.sh" --kv 2>&1)
expect "old Italian identity file"     '^CONFIDENCE=confirmed$'                           "$out"

echo "info.sh"
out=$(sh "$ROOT/info.sh" 2>&1)
expect "model"                         'samsung Galaxy A54 5G \(SM-A546B\), Android 14'   "$out"
expect "Samsung advice"                'UNINSTALL=1'                                      "$out"

echo "disable.sh"
out=$(sh "$ROOT/disable.sh" com.samsung.android.bixby.agent </dev/null 2>&1)
expect "without YES it's a dry run"    'Dry run'                                          "$out"
if off com.samsung.android.bixby.agent; then ko "dry run changes nothing"; else ok "dry run changes nothing"; fi

out=$(YES=1 sh "$ROOT/disable.sh" com.google.android.gms com.samsung.android.dialer com.samsung.android.app.tips com.nope.app 2>&1)
expect "refuses gms"                   'NO +com.google.android.gms'                        "$out"
expect "refuses the default dialer"    'NO +com.samsung.android.dialer'                    "$out"
expect "skips one already off"         'skip +com.samsung.android.app.tips'               "$out"
expect "skips a missing one"           'skip +com.nope.app'                               "$out"
expect "nothing to do"                 'Nothing to do'                                    "$out"
if off com.google.android.gms; then ko "gms stays on"; else ok "gms stays on"; fi

out=$(YES=1 sh "$ROOT/disable.sh" FAKE123456 com.samsung.android.bixby.agent com.facebook.appmanager 2>&1)
expect "turns Bixby off"               'off +com.samsung.android.bixby.agent'             "$out"
off com.samsung.android.bixby.agent && off com.facebook.appmanager && ok "they're off" || ko "they're off"
LOG="$LOG_DIR/samsung-SM-A546B-FAKE123456.txt"
grep -qx 'off com.facebook.appmanager' "$LOG" && ok "list on the computer" || ko "list on the computer"
grep -qx 'off com.facebook.appmanager' "$P/tmp/phone-detox.txt" && ok "list on the phone" || ko "list on the phone"

out=$(YES=1 sh "$ROOT/disable.sh" com.vendor.lockedapp 2>&1 || true)
expect "app the phone refuses"         'ERROR +com.vendor.lockedapp'                      "$out"
expect "suggests UNINSTALL=1"          'UNINSTALL=1'                                      "$out"
out=$(YES=1 UNINSTALL=1 sh "$ROOT/disable.sh" com.vendor.lockedapp 2>&1)
expect "removes it for the user"       'removed +com.vendor.lockedapp'                    "$out"
removed com.vendor.lockedapp && ok "it's removed" || ko "it's removed"

printf 'com.samsung.android.game.gamehome\n# comment\n' > "$WORK/list.txt"
YES=1 sh "$ROOT/disable.sh" -f "$WORK/list.txt" >/dev/null 2>&1
off com.samsung.android.game.gamehome && ok "reads a list with -f" || ko "reads a list with -f"

echo "check.sh"
# An update turns Bixby back on.
grep -vx com.samsung.android.bixby.agent "$P/off" > "$P/off.t"; mv "$P/off.t" "$P/off"
out=$(sh "$ROOT/check.sh" 2>&1 || true)
expect "notices Bixby came back"       'CHANGED +com.samsung.android.bixby.agent'         "$out"
out=$(sh "$ROOT/check.sh" --fix 2>&1)
expect "turns it off again"            'fixed +com.samsung.android.bixby.agent'           "$out"
off com.samsung.android.bixby.agent && ok "Bixby off again" || ko "Bixby off again"

echo "undo.sh"
out=$(sh "$ROOT/undo.sh" com.facebook.appmanager 2>&1)
expect "just one app"                  'on +com.facebook.appmanager'                      "$out"
off com.samsung.android.bixby.agent && ok "the others stay off" || ko "the others stay off"
grep -q 'com.facebook.appmanager' "$LOG" && ko "dropped from the list" || ok "dropped from the list"

# From another computer: no local list, only the one on the phone.
rm -rf "$LOG_DIR"
out=$(sh "$ROOT/undo.sh" 2>&1)
expect "turns Bixby on"                'on +com.samsung.android.bixby.agent'              "$out"
expect "brings back the removed app"   'on +com.vendor.lockedapp'                         "$out"
removed com.vendor.lockedapp && ko "lockedapp installed again" || ok "lockedapp installed again"
off com.samsung.android.game.gamehome && ko "gamehome on" || ok "gamehome on"
off com.samsung.android.app.tips && ok "leaves alone what was off before" || ko "leaves alone what was off before"

out=$(sh "$ROOT/undo.sh" --all 2>&1)
expect "rescue turns everything on"    'on +com.samsung.android.app.tips'                 "$out"
[ -s "$P/off" ] && ko "no app off" || ok "no app off"

echo "guide.sh"
# The confirmed name went away with changes/: the guide asks for it again.
# Answers: backup yes, model right, name right, app 1, go ahead, no restart,
# all works, another group yes, then Enter to finish.
out=$(printf 'y\ny\ny\n1\ny\nn\ny\ny\n\n' | GUIDE_STDIN=1 sh "$ROOT/guide.sh" 2>&1)
expect "asks for the model number"     'Does it say SM-A546B\?'                           "$out"
expect "saves the confirmed name"      'this phone is a Galaxy A54 5G'                    "$out"
expect "lists the apps to turn off"    ' 1\) Hidden Facebook installer'                   "$out"
expect "turns off the chosen one"      'off +com.facebook.appmanager'                     "$out"
expect "reaches the end"               '7\. Done'                                         "$out"
off com.facebook.appmanager && ok "Facebook off from the guide" || ko "Facebook off from the guide"
# If something's wrong, the guide turns the group back on. In Italian this time.
# Second run: the phone is already confirmed. Bixby is number 2; something's wrong.
out=$(printf 's\n2\ns\nn\nn\nn\n' | PD_LANG=it GUIDE_STDIN=1 sh "$ROOT/guide.sh" 2>&1)
expect "Italian: recognises the phone" 'Galaxy A54 5G che hai già confermato'             "$out"
expect "undoes the group if broken"    'on +com.samsung.android.bixby.agent'              "$out"
off com.samsung.android.bixby.agent && ko "Bixby back on" || ok "Bixby back on"

echo "app (ui)"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/ci/test_ui.py" || fails=$((fails + 1))
else
  echo "  skipped: python3 is missing"
fi

echo
if [ "$fails" -gt 0 ]; then echo "$fails tests failed."; exit 1; fi
echo "All tests passed."
