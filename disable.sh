#!/bin/sh
# Disattiva le app che indichi, una per una, e tiene la lista per poterle riattivare.
#
#   sh disable.sh [telefono] <pacchetto> [<pacchetto> ...]
#   sh disable.sh [telefono] -f lista.txt          un pacchetto per riga (# commenta)
#
# Rifiuta le app con verdetto "mai" (vedi candidates.sh). Senza terminale interattivo
# mostra solo cosa farebbe: per applicare davvero usa YES=1.
#
#   YES=1        non chiede conferma (per Claude Code, dopo che hai detto sì in chat)
#   UNINSTALL=1  se il telefono non permette di disattivare un'app di sistema, la toglie
#                per l'utente (pm uninstall -k --user 0). Resta nel sistema e undo.sh la
#                rimette con "cmd package install-existing", senza reset.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
PKGS=
while [ $# -gt 0 ]; do
  case "$1" in
    -f) [ -r "$2" ] || { echo "Non riesco a leggere $2." >&2; exit 2; }
        PKGS="$PKGS $(grep -v '^[[:space:]]*#' "$2" | awk '{print $NF}' | tr '\n' ' ')"; shift 2 ;;
    -*) echo "Opzione sconosciuta: $1" >&2; exit 2 ;;
    *)  PKGS="$PKGS $1"; shift ;;
  esac
done
[ -n "$(echo "$PKGS" | tr -d ' ')" ] || {
  echo "Uso: sh disable.sh [telefono] <pacchetto> [<pacchetto> ...]   oppure   -f lista.txt" >&2; exit 2; }

connect "$TARGET"
table=$(mktemp 2>/dev/null || mktemp -t phonedetox)
trap 'rm -f "$table"' EXIT
classify "$table"

todo=
for p in $PKGS; do
  case "$p" in *[!A-Za-z0-9_.]*) echo "  salto   $p (non è un nome di pacchetto)"; continue ;; esac
  row=$(awk -F'\t' -v p="$p" '$3==p' "$table")
  if [ -z "$row" ]; then echo "  salto   $p (non è su questo telefono)"; continue; fi
  verdict=$(printf '%s\n' "$row" | cut -f1)
  state=$(printf '%s\n' "$row" | cut -f2)
  name=$(printf '%s\n' "$row" | cut -f4)
  case "$state" in
    off)   echo "  salto   $p (è già disattivata)"; continue ;;
    tolta) echo "  salto   $p (è già stata tolta)"; continue ;;
  esac
  case "$todo" in *" $p "*) continue ;; esac
  case "$verdict" in
    mai)    echo "  NO      $p ${name:+- $name} (verdetto \"mai\": non la tocco)"; continue ;;
    tua)    echo "  ok      $p ${name:+- $name} (l'hai installata tu: potresti anche disinstallarla)" ;;
    dubbio) echo "  ok      $p (sconosciuta: controlla di sapere cos'è)" ;;
    *)      echo "  ok      $p ${name:+- $name} [$verdict]" ;;
  esac
  todo="$todo $p "
done

n=$(echo "$todo" | wc -w | tr -d ' ')
if [ "$n" = 0 ]; then echo "Niente da fare."; exit 0; fi
[ "$n" -le 10 ] || echo "Sono $n app. Meglio gruppi di 5-10, così se qualcosa si rompe sai quale gruppo annullare."

if [ "$YES" != 1 ]; then
  if [ -t 0 ]; then
    printf 'Disattivo queste %s app? [s/N] ' "$n"
    read -r answer
    case "$answer" in s|S|si|SI|sì|y|Y) ;; *) echo "Non ho cambiato niente."; exit 0 ;; esac
  else
    echo "Prova a vuoto: non ho cambiato niente. Per applicare: YES=1 sh disable.sh ..."
    exit 0
  fi
fi

LOG=$(log_file)
stamp=$(date '+%Y-%m-%d %H:%M')
printf '# %s\n' "$stamp" >> "$LOG"
sh_dev "echo '# $stamp' >> $PHONE_LOG" >/dev/null 2>&1 || true

record() { echo "$1 $2" >> "$LOG"; sh_dev "echo '$1 $2' >> $PHONE_LOG" >/dev/null 2>&1 || true; }

failed=0
for p in $todo; do
  sh_dev pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  if is_off "$p"; then record off "$p"; echo "  spenta  $p"; continue; fi
  if [ "$UNINSTALL" = 1 ]; then
    sh_dev pm uninstall -k --user 0 "$p" >/dev/null 2>&1 || true
    if is_removed "$p"; then record removed "$p"; echo "  tolta   $p (si rimette con undo.sh)"; continue; fi
  fi
  echo "  ERRORE  $p: il telefono non l'ha disattivata." >&2
  [ "$UNINSTALL" = 1 ] || echo "          Alcuni telefoni lo vietano per le app di sistema: riprova con UNINSTALL=1." >&2
  failed=$((failed + 1))
done

echo
echo "Lista delle modifiche: $LOG"
echo "Ora riavvia il telefono e prova chiamate, SMS, dati, Wi-Fi, notifiche, fotocamera,"
echo "sveglia e pagamenti. Se qualcosa non va: sh undo.sh $TARGET"
[ "$failed" = 0 ] || exit 1
