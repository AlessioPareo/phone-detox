#!/bin/sh
# Turns off the apps you list, one by one, and keeps a list so they can be turned back on.
#
#   sh disable.sh [phone] <package> [<package> ...]
#   sh disable.sh [phone] -f list.txt          one package per line (# comments)
#
# Refuses apps with verdict "never" (see candidates.sh). Without an interactive terminal it
# only shows what it would do: to apply for real use YES=1.
#
#   YES=1        no confirmation (for Claude Code, after you said yes in the chat)
#   UNINSTALL=1  if the phone doesn't allow turning off a system app, remove it for the user
#                (pm uninstall -k --user 0). It stays in the system and undo.sh brings it
#                back with "cmd package install-existing", without a reset.
#
# Each app gets one line starting with a label: off, removed, ERROR, NO (refused), skip.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
PKGS=
while [ $# -gt 0 ]; do
  case "$1" in
    -f) [ -r "$2" ] || { say "Non riesco a leggere $2." "Can't read $2." >&2; exit 2; }
        PKGS="$PKGS $(grep -v '^[[:space:]]*#' "$2" | awk '{print $NF}' | tr '\n' ' ')"; shift 2 ;;
    -*) say "Opzione sconosciuta: $1" "Unknown option: $1" >&2; exit 2 ;;
    *)  PKGS="$PKGS $1"; shift ;;
  esac
done
[ -n "$(echo "$PKGS" | tr -d ' ')" ] || {
  say "Uso: sh disable.sh [telefono] <pacchetto> [<pacchetto> ...]   oppure   -f lista.txt" \
      "Usage: sh disable.sh [phone] <package> [<package> ...]   or   -f list.txt" >&2; exit 2; }

connect "$TARGET"
table=$(mktemp 2>/dev/null || mktemp -t phonedetox)
trap 'rm -f "$table"' EXIT
classify "$table"

todo=
for p in $PKGS; do
  case "$p" in *[!A-Za-z0-9_.]*) echo "  skip     $p ($(L 'non è un nome di pacchetto' 'not a package name'))"; continue ;; esac
  row=$(awk -F'\t' -v p="$p" '$3==p' "$table")
  if [ -z "$row" ]; then echo "  skip     $p ($(L 'non è su questo telefono' 'not on this phone'))"; continue; fi
  verdict=$(printf '%s\n' "$row" | cut -f1)
  state=$(printf '%s\n' "$row" | cut -f2)
  name=$(row_name "$row")
  case "$state" in
    off)     echo "  skip     $p ($(L 'è già spenta' 'already off'))"; continue ;;
    removed) echo "  skip     $p ($(L 'è già stata tolta' 'already removed'))"; continue ;;
  esac
  case "$todo" in *" $p "*) continue ;; esac
  case "$verdict" in
    never)   echo "  NO       $p ${name:+- $name} ($(L 'verdetto "never": non la tocco' 'verdict "never": not touching it'))"; continue ;;
    yours)   echo "  ok       $p ${name:+- $name} ($(L "l'hai installata tu: potresti anche disinstallarla" 'you installed it: you could also uninstall it'))" ;;
    unknown) echo "  ok       $p ($(L "sconosciuta: controlla di sapere cos'è" 'unknown: make sure you know what it is'))" ;;
    *)       echo "  ok       $p ${name:+- $name} [$verdict]" ;;
  esac
  todo="$todo $p "
done

n=$(echo "$todo" | wc -w | tr -d ' ')
if [ "$n" = 0 ]; then say "Niente da fare." "Nothing to do."; exit 0; fi
[ "$n" -le 10 ] || say "Sono $n app. Meglio gruppi di 5-10, così se qualcosa si rompe sai quale gruppo annullare." \
  "That's $n apps. Groups of 5-10 are better: if something breaks you know which group to undo."

if [ "$YES" != 1 ]; then
  if [ -t 0 ]; then
    printf '%s ' "$(L "Spengo queste $n app? [s/N]" "Turn off these $n apps? [y/N]")"
    read -r answer
    case "$answer" in s|S|si|SI|sì|y|Y|yes|YES) ;; *) say "Non ho cambiato niente." "Nothing changed."; exit 0 ;; esac
  else
    say "Prova a vuoto: non ho cambiato niente. Per applicare: YES=1 sh disable.sh ..." \
        "Dry run: nothing changed. To apply: YES=1 sh disable.sh ..."
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
  if is_off "$p"; then record off "$p"; echo "  off      $p"; continue; fi
  if [ "$UNINSTALL" = 1 ]; then
    sh_dev pm uninstall -k --user 0 "$p" >/dev/null 2>&1 || true
    if is_removed "$p"; then record removed "$p"; echo "  removed  $p ($(L 'si rimette con undo.sh' 'undo.sh brings it back'))"; continue; fi
  fi
  echo "  ERROR    $p: $(L "il telefono non l'ha spenta." "the phone didn't turn it off.")" >&2
  [ "$UNINSTALL" = 1 ] || echo "           $(L "Alcuni telefoni lo vietano per le app di sistema: riprova con UNINSTALL=1." "Some phones forbid it for system apps: try again with UNINSTALL=1.")" >&2
  failed=$((failed + 1))
done

echo
say "Lista delle modifiche: $LOG" "Change list: $LOG"
say "Ora riavvia il telefono e prova chiamate, SMS, dati, Wi-Fi, notifiche, fotocamera," \
    "Now restart the phone and test calls, SMS, data, Wi-Fi, notifications, camera,"
say "sveglia e pagamenti. Se qualcosa non va: sh undo.sh $TARGET" \
    "alarms and payments. If something's wrong: sh undo.sh $TARGET"
[ "$failed" = 0 ] || exit 1
