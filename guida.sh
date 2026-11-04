#!/bin/sh
# Procedura guidata: collega il telefono, lo identifica, e spegne le app a piccoli gruppi
# chiedendoti ogni passo. Pensata per chi non vuole usare un agente AI.
#
#   sh guida.sh
#
# Puoi fermarti quando vuoi (Ctrl+C): ogni modifica è già salvata nella lista, e
# rilanciando riparti da dove eri. Per annullare tutto: sh undo.sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

# Le risposte arrivano dal terminale. GUIDA_STDIN=1 le legge dallo stdin (per i test).
if [ "$GUIDA_STDIN" = 1 ]; then IN=/dev/stdin
elif (: < /dev/tty) 2>/dev/null; then IN=/dev/tty
else
  echo "Questa procedura fa domande, quindi va lanciata da un terminale." >&2
  echo "Se sei Claude Code o un altro agente, segui CLAUDE.md invece." >&2
  exit 2
fi
ask() { printf '%s' "$1"; answer=; read -r answer < "$IN" || answer=; }
yes_no() {
  while :; do
    ask "$1 [s/n] "
    case "$answer" in s|S|si|SI|sì|Sì|y|Y) return 0 ;; n|N|no|NO) return 1 ;; esac
    echo "Rispondi s oppure n."
  done
}
pause() { ask "Premi Invio per continuare "; }
step() { echo; echo "== $1"; echo; }
avail_mb() { sh_dev cat /proc/meminfo | sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\) kB/\1/p' | awk '{print int($1/1024)}'; }

# --- 1 ---------------------------------------------------------------------------------------
step "1. Prima di cominciare"
cat <<'EOF'
Questa procedura spegne app di sistema che di solito non servono: pubblicità del produttore,
doppioni, app preinstallate. Non cancella niente e tutto si annulla con: sh undo.sh

Spegnere app di sistema ha comunque dei rischi: qualche funzione può smettere di andare e,
nel caso peggiore, il telefono può non ripartire. Per questo si va a gruppi piccoli, si
riavvia e si prova il telefono dopo ogni gruppo.

Prima di continuare fai un backup di foto, chat e contatti.
EOF
yes_no "Hai fatto il backup e vuoi continuare?" || { echo "Va bene, a un'altra volta."; exit 0; }

# --- 2 ---------------------------------------------------------------------------------------
step "2. Collegamento"
need_adb
TARGET=
while [ -z "$TARGET" ]; do
  list=$(adb devices -l 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2!="" {m=""; for (i=3;i<=NF;i++) if ($i ~ /^model:/) m=substr($i,7); print $1 " " $2 " " m}')
  ready=$(printf '%s\n' "$list" | awk '$2=="device"')
  n=$(printf '%s\n' "$ready" | grep -c . || true)
  if printf '%s\n' "$list" | awk '$2=="unauthorized"' | grep -q .; then
    echo "Il telefono chiede \"Consentire il debug USB?\". Sbloccalo, spunta \"Consenti sempre\" e tocca Consenti."
    pause; continue
  fi
  if [ "$n" = 1 ]; then TARGET=$(printf '%s\n' "$ready" | awk '{print $1}'); break; fi
  if [ "$n" -gt 1 ]; then
    echo "Vedo più dispositivi:"
    printf '%s\n' "$ready" | awk '{printf "  %d) %s %s\n", NR, $3, $1}'
    ask "Quale uso? (numero) "
    TARGET=$(printf '%s\n' "$ready" | awk -v n="$answer" 'NR==n {print $1}')
    [ -n "$TARGET" ] || echo "Numero non valido."
    continue
  fi
  cat <<'EOF'
Non vedo nessun telefono. Controlla:
  - Opzioni sviluppatore > Debug USB è attivo (su Xiaomi anche "impostazioni di sicurezza")
  - il cavo passa i dati: quelli solo di ricarica non funzionano, provane un altro
  - quando colleghi, scegli "Trasferimento file" nella notifica USB
  - su Windows può servire il driver USB del produttore
EOF
  ask "Invio per riprovare, w per collegarti in Wi-Fi, q per uscire: "
  case "$answer" in
    q|Q) exit 0 ;;
    w|W)
      echo "Sul telefono: Opzioni sviluppatore > Debug wireless > Associa dispositivo con codice."
      ask "Indirizzo e porta mostrati sotto il codice (es. 192.168.1.20:37099): "; pair=$answer
      ask "Codice di associazione (6 cifre): "; code=$answer
      adb pair "$pair" "$code" || echo "Associazione non riuscita: ricontrolla indirizzo e codice."
      ask "Ora l'indirizzo e porta nella schermata Debug wireless (porta diversa): "
      adb connect "$answer" || true ;;
  esac
done
connect "$TARGET"
case "$PHONE" in *:*) WIRELESS=1 ;; *) WIRELESS= ;; esac
echo "Collegato."

# --- 3 ---------------------------------------------------------------------------------------
step "3. Che telefono è"
sh "$DIR/identify.sh" "$PHONE" >/dev/null
kv=$(identify)
v() { printf '%s\n' "$kv" | sed -n "s/^$1=//p"; }
MODEL=$(v MODEL); MARKET=$(v MARKET); MAKER=$(v MAKER)
echo "Codice modello: $MODEL   Nome in codice: $(v DEVICE)   Android $(v ANDROID)${MARKET:+   Nome: $MARKET}"
case "$(v CONFIDENCE)" in
  confermato) echo "È il $MAKER $MARKET che hai già confermato." ;;
  *)
    echo "Sul telefono apri Impostazioni > Info telefono e guarda il numero di modello."
    if ! yes_no "Leggi $MODEL?"; then
      echo "Allora sto parlando con un altro dispositivo. Scollega gli altri e rilancia la guida."
      exit 1
    fi
    if [ -n "$MARKET" ] && yes_no "Il nome del telefono è $MARKET?"; then :; else
      ask "Scrivi il nome che leggi (es. Galaxy A54 5G): "; MARKET=$answer
    fi
    [ -z "$MARKET" ] || sh "$DIR/identify.sh" "$PHONE" --conferma "$MARKET" ;;
esac
echo "Se vuoi approfondire il tuo modello, cerca online: \"${MARKET:+$MARKET }$MODEL debloat\""

# --- 4 ---------------------------------------------------------------------------------------
BEFORE=$(avail_mb)
round=0
while :; do
  round=$((round + 1))
  step "4. Scelta delle app (gruppo $round)"
  table=$(mktemp 2>/dev/null || mktemp -t phonedetox)
  classify "$table"
  awk -F'\t' '$1=="via" && $2=="on"' "$table" > "$table.via"
  awk -F'\t' '$1=="serve" && $2=="on"' "$table" > "$table.serve"
  if [ ! -s "$table.via" ]; then
    echo "Non trovo altre app da spegnere senza pensieri. Le altre servono al telefono o non so cosa sono."
    rm -f "$table" "$table.via" "$table.serve"; break
  fi
  echo "Queste di solito si possono spegnere:"
  awk -F'\t' '{printf "  %2d) %s%s\n", NR, ($4=="" ? $3 : $4), ($4=="" ? "" : "  [" $3 "]")}' "$table.via"
  echo
  echo "Scrivi i numeri da spegnere (es. 1 3 4), t per tutte, s per vedere anche le app che"
  echo "portano una funzione, Invio per finire. Al massimo 10 per gruppo."
  ask "> "
  pick=
  case "$answer" in
    "") rm -f "$table" "$table.via" "$table.serve"; break ;;
    t|T) pick=$(awk -F'\t' 'NR<=10 {print $3}' "$table.via") ;;
    s|S)
      echo "Queste portano una funzione: spegnile solo se sei sicuro di non usarla."
      awk -F'\t' '{printf "  %2d) %s%s\n", NR, ($4=="" ? $3 : $4), ($4=="" ? "" : "  [" $3 "]")}' "$table.serve"
      ask "Numeri da spegnere (Invio per nessuna): "
      for i in $(printf '%s' "$answer" | tr ',' ' '); do
        pick="$pick $(awk -F'\t' -v n="$i" 'NR==n {print $3}' "$table.serve")"
      done ;;
    *)
      for i in $(printf '%s' "$answer" | tr ',' ' '); do
        pick="$pick $(awk -F'\t' -v n="$i" 'NR==n {print $3}' "$table.via")"
      done ;;
  esac
  rm -f "$table" "$table.via" "$table.serve"
  pick=$(printf '%s\n' $pick | grep . | head -10 | tr '\n' ' ')
  [ -n "$pick" ] || { echo "Nessuna app scelta."; continue; }

  # --- 5 -------------------------------------------------------------------------------------
  step "5. Spegnimento"
  echo "Spengo:"; printf '  %s\n' $pick
  yes_no "Procedo?" || continue
  out=$(YES=1 sh "$DIR/disable.sh" "$PHONE" $pick 2>&1) || true
  printf '%s\n' "$out" | grep -E '^ +(spenta|tolta|ERRORE|NO) ' || true
  stuck=$(printf '%s\n' "$out" | sed -n 's/^ *ERRORE *\([A-Za-z0-9_.]*\):.*/\1/p' | tr '\n' ' ')
  if [ -n "$stuck" ]; then
    echo "Il telefono non lascia spegnere: $stuck"
    echo "Posso toglierle per il tuo utente: restano nel sistema e undo.sh le rimette senza reset."
    if yes_no "Le tolgo?"; then
      YES=1 UNINSTALL=1 sh "$DIR/disable.sh" "$PHONE" $stuck 2>&1 | grep -E '^ +(spenta|tolta|ERRORE) ' || true
    fi
  fi

  # --- 6 -------------------------------------------------------------------------------------
  step "6. Riavvio e prova"
  if [ -n "$WIRELESS" ]; then
    echo "Sei collegato in Wi-Fi: dopo il riavvio la porta cambia. Riavvia il telefono a mano,"
    echo "prova le funzioni qui sotto, poi rilancia la guida per il gruppo successivo."
  elif yes_no "Riavvio il telefono adesso?"; then
    adb -s "$PHONE" reboot >/dev/null 2>&1 || true
    echo "Riavvio in corso..."
    sleep 5
    adb -s "$PHONE" wait-for-device >/dev/null 2>&1 || true
    i=0
    while [ "$(sh_dev getprop sys.boot_completed)" != 1 ] && [ $i -lt 90 ]; do sleep 2; i=$((i + 1)); done
    if [ "$(sh_dev getprop sys.boot_completed)" = 1 ]; then echo "Il telefono è ripartito."
    else echo "Il telefono non ha finito di avviarsi in 3 minuti."; fi
  else
    echo "Riavvialo appena puoi: il telefono è davvero provato solo dopo un riavvio."
  fi
  cat <<'EOF'

Sblocca il telefono e prova:
  - una chiamata e un SMS
  - dati mobili, Wi-Fi e Bluetooth
  - una notifica (es. un messaggio su WhatsApp)
  - fotocamera e una sveglia
  - se lo usi, il pagamento contactless o l'app della banca
EOF
  if yes_no "Funziona tutto?"; then
    echo "Bene."
  else
    echo "Riaccendo le app di questo gruppo."
    sh "$DIR/undo.sh" "$PHONE" $pick || true
    echo "Riavvia il telefono e ricontrolla. Se non basta: sh undo.sh --all"
  fi
  [ -z "$WIRELESS" ] || break
  yes_no "Passiamo a un altro gruppo?" || break
done

# --- 7 ---------------------------------------------------------------------------------------
step "7. Fine"
AFTER=$(avail_mb)
[ -z "$BEFORE" ] || [ -z "$AFTER" ] || echo "Memoria libera: prima $BEFORE MB, adesso $AFTER MB (conta anche il riavvio)."
LOG=$(log_file)
[ ! -s "$LOG" ] || echo "Le modifiche sono in $LOG (e una copia sul telefono)."
cat <<'EOF'
Per annullare:              sh undo.sh
Dopo un aggiornamento:      sh check.sh --fix

Ultima cosa: in Opzioni sviluppatore spegni Debug USB e Debug wireless (o tutte le Opzioni
sviluppatore). Riaccendili solo quando devi usare undo.sh o check.sh.
EOF
