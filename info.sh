#!/bin/sh
# What the phone is, how much memory is free, which apps are the defaults and how many are
# already off. Run it before and after the cleanup. Changes nothing.
#
#   sh info.sh [phone]
#
# The RAM line is always "RAM: <total> MB, free <available> MB"; a managed phone adds a line
# starting with "MANAGED:". Both are read by the app.
set -e
. "$(dirname "$0")/lib.sh"

connect "$1"

kv=$(identify)
v() { printf '%s\n' "$kv" | sed -n "s/^$1=//p"; }
SKIN=$(v SKIN); MARKET=$(v MARKET)
mem() { sh_dev cat /proc/meminfo | sed -n "s/^$1:[[:space:]]*\([0-9]*\) kB/\1/p"; }
TOTAL=$(mem MemTotal); AVAIL=$(mem MemAvailable)
ALL=$(sh_dev pm list packages | grep -c '^package:' || true)
OFF=$(sh_dev pm list packages -d | grep -c '^package:' || true)
U=$(sh_dev pm list packages -u | grep -c '^package:' || true)
MINE=$(sh_dev pm list packages -3 | grep -c '^package:' || true)

echo "== $(L Telefono Phone)"
echo "   $(v MAKER) ${MARKET:+$MARKET }($(v MODEL)), Android $(v ANDROID)${SKIN:+, $SKIN}"
case "$(v CONFIDENCE)" in high|confirmed) ;; *)
  say "   Nome non certo: lancia identify.sh per confermarlo." "   Name not certain: run identify.sh to confirm it." ;;
esac
[ -z "$TOTAL" ] || echo "   RAM: $((TOTAL / 1024)) MB, free $((AVAIL / 1024)) MB"
say "   $ALL app ($MINE installate da te), $OFF spente, $((U - ALL)) tolte per l'utente" \
    "   $ALL apps ($MINE installed by you), $OFF off, $((U - ALL)) removed for the user"

say "== App predefinite (non si spengono finché sono predefinite)" "== Default apps (can't be turned off while they're the default)"
for r in HOME DIALER SMS BROWSER ASSISTANT WALLET; do
  h=$(sh_dev cmd role get-role-holders --user 0 "android.app.role.$r" 2>/dev/null | tr -d ' ')
  printf '   %-9s %s\n' "$r" "${h:-$(L nessuna none)}"
done
ime=$(sh_dev settings get secure default_input_method 2>/dev/null)
printf '   %-9s %s\n' KEYBOARD "${ime%%/*}"

say "== Da sapere su questo telefono" "== Good to know about this phone"
case "$(v FAMILY)" in
  samsung)
    say "   Samsung: alcune app di sistema non si lasciano spegnere via adb; disable.sh" \
        "   Samsung: some system apps can't be turned off through adb; disable.sh"
    say "   te lo dice e puoi usare UNINSTALL=1 (reversibile con undo.sh)." \
        "   tells you and you can use UNINSTALL=1 (reversible with undo.sh)."
    say "   Lascia stare Knox Guard e Trova dispositivo se il telefono è in finanziamento o aziendale." \
        "   Leave Knox Guard and Find My Mobile alone if the phone is financed or a work phone." ;;
  xiaomi)
    say "   Xiaomi: attiva anche \"Debug USB (impostazioni di sicurezza)\" nelle Opzioni sviluppatore." \
        "   Xiaomi: also turn on \"USB debugging (Security settings)\" in Developer options."
    say "   Non toccare mai com.miui.securitycenter: su alcuni modelli il telefono non riparte." \
        "   Never touch com.miui.securitycenter: on some models the phone won't boot."
    say "   Le pubblicità di sistema stanno in com.miui.msa.global e com.miui.analytics." \
        "   System ads live in com.miui.msa.global and com.miui.analytics." ;;
  oplus)
    say "   OnePlus/Oppo/Realme: dalla ColorOS 12 molte app di sistema vanno tolte con UNINSTALL=1." \
        "   OnePlus/Oppo/Realme: since ColorOS 12 many system apps need UNINSTALL=1." ;;
  google)
    say "   Pixel: poco da pulire. Il guadagno vero è su app Google che non usi." \
        "   Pixel: little to clean. The real gain is Google apps you don't use." ;;
  huawei|honor)
    say "   Huawei/Honor: senza servizi Google, le liste di questo progetto valgono poco: vai piano." \
        "   Huawei/Honor: without Google services this project's lists are less reliable: go slowly." ;;
esac
if [ -n "$(sh_dev dumpsys device_policy 2>/dev/null | grep -m1 -E 'Device Owner|Profile Owner')" ]; then
  echo "MANAGED: $(L "questo telefono è gestito (aziendale o da un'app di gestione): non toccare le app di gestione." \
    'this phone is managed (by an employer or a management app): leave the management apps alone.')"
fi

say "== Avanti" "== Next"
say "   sh candidates.sh $1        cosa si può spegnere (non cambia niente)" "   sh candidates.sh $1        what can be turned off (changes nothing)"
say "   sh disable.sh $1 <app>...  spegne, chiedendo conferma" "   sh disable.sh $1 <app>...  turns off, asking for confirmation"
say "   sh undo.sh $1              riaccende tutto" "   sh undo.sh $1              turns everything back on"
