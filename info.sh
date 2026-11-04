#!/bin/sh
# Cosa è il telefono, quanta memoria ha libera, quali app fanno da predefinite e quante sono già
# spente. Da lanciare prima e dopo la pulizia. Non cambia niente.
#
#   sh info.sh [telefono]
set -e
. "$(dirname "$0")/lib.sh"

connect "$1"

MAKER=$(prop ro.product.manufacturer)
MODEL=$(prop ro.product.model)
RELEASE=$(prop ro.build.version.release)
SDK=$(prop ro.build.version.sdk)
SKIN=
ONEUI=$(prop ro.build.version.oneui)
[ -z "$ONEUI" ] || SKIN="One UI $((ONEUI / 10000)).$((ONEUI / 100 % 100))"
[ -z "$(prop ro.miui.ui.version.name)" ] || SKIN="MIUI $(prop ro.miui.ui.version.name)"
[ -z "$(prop ro.mi.os.version.name)" ] || SKIN="HyperOS $(prop ro.mi.os.version.name)"
[ -z "$(prop ro.build.version.oplusrom)" ] || SKIN="ColorOS/OxygenOS $(prop ro.build.version.oplusrom)"
mem() { sh_dev cat /proc/meminfo | sed -n "s/^$1:[[:space:]]*\([0-9]*\) kB/\1/p"; }
TOTAL=$(mem MemTotal); AVAIL=$(mem MemAvailable)
ALL=$(sh_dev pm list packages | grep -c '^package:' || true)
OFF=$(sh_dev pm list packages -d | grep -c '^package:' || true)
U=$(sh_dev pm list packages -u | grep -c '^package:' || true)
MINE=$(sh_dev pm list packages -3 | grep -c '^package:' || true)

echo "== Telefono"
echo "   $MAKER $MODEL, Android $RELEASE (SDK $SDK)${SKIN:+, $SKIN}"
[ -z "$TOTAL" ] || echo "   RAM: $((TOTAL / 1024)) MB, libera ora $((AVAIL / 1024)) MB"
echo "   $ALL app ($MINE installate da te), $OFF spente, $((U - ALL)) tolte per l'utente"

echo "== App predefinite (non si spengono finché sono predefinite)"
for r in HOME DIALER SMS BROWSER ASSISTANT WALLET; do
  h=$(sh_dev cmd role get-role-holders --user 0 "android.app.role.$r" 2>/dev/null | tr -d ' ')
  printf '   %-9s %s\n' "$r" "${h:-nessuna}"
done
ime=$(sh_dev settings get secure default_input_method 2>/dev/null)
printf '   %-9s %s\n' TASTIERA "${ime%%/*}"

echo "== Da sapere su questo telefono"
case "$(echo "$MAKER" | tr 'A-Z' 'a-z')" in
  samsung)
    echo "   Samsung: alcune app di sistema non si lasciano disattivare via adb; disable.sh"
    echo "   te lo dice e puoi usare UNINSTALL=1 (reversibile con undo.sh)."
    echo "   Lascia stare Knox Guard e Trova dispositivo se il telefono è in finanziamento o aziendale." ;;
  xiaomi|redmi|poco)
    echo "   Xiaomi: attiva anche \"Debug USB (impostazioni di sicurezza)\" nelle Opzioni sviluppatore."
    echo "   Non toccare mai com.miui.securitycenter: su alcuni modelli il telefono non riparte."
    echo "   Le pubblicità di sistema stanno in com.miui.msa.global e com.miui.analytics." ;;
  oneplus|oppo|realme)
    echo "   OnePlus/Oppo/Realme: dalla ColorOS 12 molte app di sistema vanno tolte con UNINSTALL=1." ;;
  google)
    echo "   Pixel: poco da pulire. Il guadagno vero è su app Google che non usi." ;;
  huawei|honor)
    echo "   Huawei/Honor: senza servizi Google, le liste di questo progetto valgono poco: vai piano." ;;
esac
if [ -n "$(sh_dev dumpsys device_policy 2>/dev/null | grep -m1 -E 'Device Owner|Profile Owner')" ]; then
  echo "   Questo telefono è gestito (aziendale o da un'app di gestione): non toccare le app di gestione."
fi

echo "== Avanti"
echo "   sh candidates.sh $1        cosa si può spegnere (non cambia niente)"
echo "   sh disable.sh $1 <app>...  spegne, chiedendo conferma"
echo "   sh undo.sh $1              riaccende tutto"
