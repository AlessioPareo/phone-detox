#!/bin/sh
# Guided wizard: connects the phone, identifies it, and turns apps off in small groups,
# asking you at every step. Made for people who don't want to use an AI agent.
#
#   sh guide.sh                   in your computer's language (Italian or English)
#   PD_LANG=it sh guide.sh        in Italian;   PD_LANG=en: in English
#
# You can stop anytime (Ctrl+C): every change is already saved in the list, and running it
# again picks up from there. To undo everything: sh undo.sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

# Answers come from the terminal. GUIDE_STDIN=1 reads them from stdin (for the tests).
if [ "$GUIDE_STDIN" = 1 ]; then IN=/dev/stdin
elif (: < /dev/tty) 2>/dev/null; then IN=/dev/tty
else
  say "Questa procedura fa domande, quindi va lanciata da un terminale." \
      "This wizard asks questions, so it must run in a terminal." >&2
  say "Se sei Claude Code o un altro agente, segui CLAUDE.md invece." \
      "If you're Claude Code or another agent, follow CLAUDE.md instead." >&2
  exit 2
fi
ask() { printf '%s' "$1"; answer=; read -r answer < "$IN" || answer=; }
yes_no() {
  while :; do
    ask "$1 $(L '[s/n]' '[y/n]') "
    case "$answer" in s|S|si|SI|sì|Sì|y|Y|yes|YES) return 0 ;; n|N|no|NO) return 1 ;; esac
    say "Rispondi s oppure n." "Answer y or n."
  done
}
pause() { ask "$(L 'Premi Invio per continuare ' 'Press Enter to continue ')"; }
step() { echo; echo "== $1"; echo; }
avail_mb() { sh_dev cat /proc/meminfo | sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\) kB/\1/p' | awk '{print int($1/1024)}'; }
# Prints a numbered list of table rows: name in the chosen language, package in brackets.
numbered() {
  awk -F'\t' -v it="$([ "$PD_LANG" = it ] && echo 1)" '{
    n = it ? $4 : $5; if (n == "") n = $4
    printf "  %2d) %s%s\n", NR, (n == "" ? $3 : n), (n == "" ? "" : "  [" $3 "]") }' "$1"
}

# --- 1 ---------------------------------------------------------------------------------------
step "$(L '1. Prima di cominciare' '1. Before you start')"
if [ "$PD_LANG" = it ]; then cat <<'EOF'
Questa procedura spegne app di sistema che di solito non servono: pubblicità del produttore,
doppioni, app preinstallate. Non cancella niente e tutto si annulla con: sh undo.sh

Spegnere app di sistema ha comunque dei rischi: qualche funzione può smettere di andare e,
nel caso peggiore, il telefono può non ripartire. Per questo si va a gruppi piccoli, si
riavvia e si prova il telefono dopo ogni gruppo.

Prima di continuare fai un backup di foto, chat e contatti.
EOF
else cat <<'EOF'
This wizard turns off system apps you usually don't need: manufacturer ads, duplicates,
preinstalled apps. It deletes nothing, and everything can be undone with: sh undo.sh

Turning off system apps still has risks: some feature may stop working and, in the worst
case, the phone may not start. That's why we go in small groups, restarting and testing the
phone after each group.

Before continuing, back up your photos, chats and contacts.
EOF
fi
yes_no "$(L 'Hai fatto il backup e vuoi continuare?' 'Did you back up, and do you want to continue?')" \
  || { say "Va bene, a un'altra volta." "OK, another time."; exit 0; }

# --- 2 ---------------------------------------------------------------------------------------
step "$(L '2. Collegamento' '2. Connection')"
need_adb
TARGET=
while [ -z "$TARGET" ]; do
  list=$(adb devices -l 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2!="" {m=""; for (i=3;i<=NF;i++) if ($i ~ /^model:/) m=substr($i,7); print $1 " " $2 " " m}')
  ready=$(printf '%s\n' "$list" | awk '$2=="device"')
  n=$(printf '%s\n' "$ready" | grep -c . || true)
  if printf '%s\n' "$list" | awk '$2=="unauthorized"' | grep -q .; then
    say "Il telefono chiede \"Consentire il debug USB?\". Sbloccalo, spunta \"Consenti sempre\" e tocca Consenti." \
        "The phone asks \"Allow USB debugging?\". Unlock it, tick \"Always allow\" and tap Allow."
    pause; continue
  fi
  if [ "$n" = 1 ]; then TARGET=$(printf '%s\n' "$ready" | awk '{print $1}'); break; fi
  if [ "$n" -gt 1 ]; then
    say "Vedo più dispositivi:" "I see more than one device:"
    printf '%s\n' "$ready" | awk '{printf "  %d) %s %s\n", NR, $3, $1}'
    ask "$(L 'Quale uso? (numero) ' 'Which one? (number) ')"
    TARGET=$(printf '%s\n' "$ready" | awk -v n="$answer" 'NR==n {print $1}')
    [ -n "$TARGET" ] || say "Numero non valido." "Invalid number."
    continue
  fi
  if [ "$PD_LANG" = it ]; then cat <<'EOF'
Non vedo nessun telefono. Controlla:
  - Opzioni sviluppatore > Debug USB è attivo (su Xiaomi anche "impostazioni di sicurezza")
  - il cavo passa i dati: quelli solo di ricarica non funzionano, provane un altro
  - quando colleghi, scegli "Trasferimento file" nella notifica USB
  - su Windows può servire il driver USB del produttore
EOF
  else cat <<'EOF'
I can't see any phone. Check that:
  - Developer options > USB debugging is on (on Xiaomi also "Security settings")
  - the cable carries data: charge-only cables don't work, try another one
  - when you plug in, you choose "File transfer" in the USB notification
  - on Windows you may need the manufacturer's USB driver
EOF
  fi
  ask "$(L 'Invio per riprovare, w per collegarti in Wi-Fi, q per uscire: ' 'Enter to retry, w to connect over Wi-Fi, q to quit: ')"
  case "$answer" in
    q|Q) exit 0 ;;
    w|W)
      say "Sul telefono: Opzioni sviluppatore > Debug wireless > Associa dispositivo con codice." \
          "On the phone: Developer options > Wireless debugging > Pair device with pairing code."
      ask "$(L 'Indirizzo e porta mostrati sotto il codice (es. 192.168.1.20:37099): ' 'Address and port shown under the code (e.g. 192.168.1.20:37099): ')"; pair=$answer
      ask "$(L 'Codice di associazione (6 cifre): ' 'Pairing code (6 digits): ')"; code=$answer
      adb pair "$pair" "$code" || say "Associazione non riuscita: ricontrolla indirizzo e codice." "Pairing failed: check address and code."
      ask "$(L "Ora l'indirizzo e porta nella schermata Debug wireless (porta diversa): " 'Now the address and port on the Wireless debugging screen (a different port): ')"
      adb connect "$answer" || true ;;
  esac
done
connect "$TARGET"
case "$PHONE" in *:*) WIRELESS=1 ;; *) WIRELESS= ;; esac
say "Collegato." "Connected."

# --- 3 ---------------------------------------------------------------------------------------
step "$(L '3. Che telefono è' '3. Which phone it is')"
sh "$DIR/identify.sh" "$PHONE" >/dev/null
kv=$(identify)
v() { printf '%s\n' "$kv" | sed -n "s/^$1=//p"; }
MODEL=$(v MODEL); MARKET=$(v MARKET); MAKER=$(v MAKER)
say "Codice modello: $MODEL   Nome in codice: $(v DEVICE)   Android $(v ANDROID)${MARKET:+   Nome: $MARKET}" \
    "Model number: $MODEL   Codename: $(v DEVICE)   Android $(v ANDROID)${MARKET:+   Name: $MARKET}"
case "$(v CONFIDENCE)" in
  confirmed) say "È il $MAKER $MARKET che hai già confermato." "It's the $MAKER $MARKET you already confirmed." ;;
  *)
    say "Sul telefono apri Impostazioni > Info telefono e guarda il numero di modello." \
        "On the phone open Settings > About phone and look at the model number."
    if ! yes_no "$(L "Leggi $MODEL?" "Does it say $MODEL?")"; then
      say "Allora sto parlando con un altro dispositivo. Scollega gli altri e rilancia la guida." \
          "Then I'm talking to another device. Unplug the others and run the guide again."
      exit 1
    fi
    if [ -n "$MARKET" ] && yes_no "$(L "Il nome del telefono è $MARKET?" "Is the phone's name $MARKET?")"; then :; else
      ask "$(L 'Scrivi il nome che leggi (es. Galaxy A54 5G): ' 'Type the name you read (e.g. Galaxy A54 5G): ')"; MARKET=$answer
    fi
    [ -z "$MARKET" ] || sh "$DIR/identify.sh" "$PHONE" --confirm "$MARKET" ;;
esac
say "Se vuoi approfondire il tuo modello, cerca online: \"${MARKET:+$MARKET }$MODEL debloat\"" \
    "To learn more about your model, search online for: \"${MARKET:+$MARKET }$MODEL debloat\""

# --- 4 ---------------------------------------------------------------------------------------
BEFORE=$(avail_mb)
round=0
while :; do
  round=$((round + 1))
  step "$(L "4. Scelta delle app (gruppo $round)" "4. Choosing apps (group $round)")"
  table=$(mktemp 2>/dev/null || mktemp -t phonedetox)
  classify "$table"
  awk -F'\t' '$1=="bloat" && $2=="on"' "$table" > "$table.bloat"
  awk -F'\t' '$1=="useful" && $2=="on"' "$table" > "$table.useful"
  if [ ! -s "$table.bloat" ]; then
    say "Non trovo altre app da spegnere senza pensieri. Le altre servono al telefono o non so cosa sono." \
        "No more apps that are safe to turn off. The others are needed by the phone or unknown."
    rm -f "$table" "$table.bloat" "$table.useful"; break
  fi
  say "Queste di solito si possono spegnere:" "These are usually safe to turn off:"
  numbered "$table.bloat"
  echo
  say "Scrivi i numeri da spegnere (es. 1 3 4), t per tutte, s per vedere anche le app che" \
      "Type the numbers to turn off (e.g. 1 3 4), a for all, u to also see the apps that"
  say "portano una funzione, Invio per finire. Al massimo 10 per gruppo." \
      "provide a feature, Enter to finish. At most 10 per group."
  ask "> "
  pick=
  case "$answer" in
    "") rm -f "$table" "$table.bloat" "$table.useful"; break ;;
    t|T|a|A) pick=$(awk -F'\t' 'NR<=10 {print $3}' "$table.bloat") ;;
    s|S|u|U)
      say "Queste portano una funzione: spegnile solo se sei sicuro di non usarla." \
          "These provide a feature: turn them off only if you're sure you don't use it."
      numbered "$table.useful"
      ask "$(L 'Numeri da spegnere (Invio per nessuna): ' 'Numbers to turn off (Enter for none): ')"
      for i in $(printf '%s' "$answer" | tr ',' ' '); do
        pick="$pick $(awk -F'\t' -v n="$i" 'NR==n {print $3}' "$table.useful")"
      done ;;
    *)
      for i in $(printf '%s' "$answer" | tr ',' ' '); do
        pick="$pick $(awk -F'\t' -v n="$i" 'NR==n {print $3}' "$table.bloat")"
      done ;;
  esac
  rm -f "$table" "$table.bloat" "$table.useful"
  pick=$(printf '%s\n' $pick | grep . | head -10 | tr '\n' ' ')
  [ -n "$pick" ] || { say "Nessuna app scelta." "No app chosen."; continue; }

  # --- 5 -------------------------------------------------------------------------------------
  step "$(L '5. Spegnimento' '5. Turning off')"
  say "Spengo:" "Turning off:"; printf '  %s\n' $pick
  yes_no "$(L 'Procedo?' 'Go ahead?')" || continue
  out=$(YES=1 sh "$DIR/disable.sh" "$PHONE" $pick 2>&1) || true
  printf '%s\n' "$out" | grep -E '^ +(off|removed|ERROR|NO) ' || true
  stuck=$(printf '%s\n' "$out" | sed -n 's/^ *ERROR *\([A-Za-z0-9_.]*\):.*/\1/p' | tr '\n' ' ')
  if [ -n "$stuck" ]; then
    say "Il telefono non lascia spegnere: $stuck" "The phone doesn't allow turning off: $stuck"
    say "Posso toglierle per il tuo utente: restano nel sistema e undo.sh le rimette senza reset." \
        "I can remove them for your user: they stay in the system and undo.sh brings them back without a reset."
    if yes_no "$(L 'Le tolgo?' 'Remove them?')"; then
      YES=1 UNINSTALL=1 sh "$DIR/disable.sh" "$PHONE" $stuck 2>&1 | grep -E '^ +(off|removed|ERROR) ' || true
    fi
  fi

  # --- 6 -------------------------------------------------------------------------------------
  step "$(L '6. Riavvio e prova' '6. Restart and test')"
  if [ -n "$WIRELESS" ]; then
    say "Sei collegato in Wi-Fi: dopo il riavvio la porta cambia. Riavvia il telefono a mano," \
        "You're connected over Wi-Fi: the port changes after a restart. Restart the phone by hand,"
    say "prova le funzioni qui sotto, poi rilancia la guida per il gruppo successivo." \
        "test the features below, then run the guide again for the next group."
  elif yes_no "$(L 'Riavvio il telefono adesso?' 'Restart the phone now?')"; then
    adb -s "$PHONE" reboot >/dev/null 2>&1 || true
    say "Riavvio in corso..." "Restarting..."
    sleep 5
    adb -s "$PHONE" wait-for-device >/dev/null 2>&1 || true
    i=0
    while [ "$(sh_dev getprop sys.boot_completed)" != 1 ] && [ $i -lt 90 ]; do sleep 2; i=$((i + 1)); done
    if [ "$(sh_dev getprop sys.boot_completed)" = 1 ]; then say "Il telefono è ripartito." "The phone is back up."
    else say "Il telefono non ha finito di avviarsi in 3 minuti." "The phone didn't finish starting within 3 minutes."; fi
  else
    say "Riavvialo appena puoi: il telefono è davvero provato solo dopo un riavvio." \
        "Restart it as soon as you can: the phone is only really tested after a restart."
  fi
  echo
  if [ "$PD_LANG" = it ]; then cat <<'EOF'
Sblocca il telefono e prova:
  - una chiamata e un SMS
  - dati mobili, Wi-Fi e Bluetooth
  - una notifica (es. un messaggio su WhatsApp)
  - fotocamera e una sveglia
  - se lo usi, il pagamento contactless o l'app della banca
EOF
  else cat <<'EOF'
Unlock the phone and test:
  - a call and an SMS
  - mobile data, Wi-Fi and Bluetooth
  - a notification (e.g. a WhatsApp message)
  - the camera and an alarm
  - if you use them, contactless payment or your banking app
EOF
  fi
  if yes_no "$(L 'Funziona tutto?' 'Does everything work?')"; then
    say "Bene." "Good."
  else
    say "Riaccendo le app di questo gruppo." "Turning this group back on."
    sh "$DIR/undo.sh" "$PHONE" $pick || true
    say "Riavvia il telefono e ricontrolla. Se non basta: sh undo.sh --all" \
        "Restart the phone and check again. If that's not enough: sh undo.sh --all"
  fi
  [ -z "$WIRELESS" ] || break
  yes_no "$(L 'Passiamo a un altro gruppo?' 'Move on to another group?')" || break
done

# --- 7 ---------------------------------------------------------------------------------------
step "$(L '7. Fine' '7. Done')"
AFTER=$(avail_mb)
[ -z "$BEFORE" ] || [ -z "$AFTER" ] || say "Memoria libera: prima $BEFORE MB, adesso $AFTER MB (conta anche il riavvio)." \
  "Free memory: before $BEFORE MB, now $AFTER MB (the restart counts too)."
LOG=$(log_file)
[ ! -s "$LOG" ] || say "Le modifiche sono in $LOG (e una copia sul telefono)." "The changes are in $LOG (and a copy on the phone)."
if [ "$PD_LANG" = it ]; then cat <<'EOF'
Per annullare:              sh undo.sh
Dopo un aggiornamento:      sh check.sh --fix

Ultima cosa: in Opzioni sviluppatore spegni Debug USB e Debug wireless (o tutte le Opzioni
sviluppatore). Riaccendili solo quando devi usare undo.sh o check.sh.
EOF
else cat <<'EOF'
To undo:                    sh undo.sh
After a system update:      sh check.sh --fix

One last thing: in Developer options turn off USB debugging and Wireless debugging (or all of
Developer options). Turn them back on only when you need undo.sh or check.sh.
EOF
fi
