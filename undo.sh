#!/bin/sh
# Riattiva le app che disable.sh ha spento o tolto.
#
#   sh undo.sh [telefono]                  tutte quelle della lista delle modifiche
#   sh undo.sh [telefono] <pacchetto> ...  solo queste
#   sh undo.sh [telefono] --all            soccorso: riattiva OGNI app spenta o tolta per
#                                          l'utente, anche quelle fatte a mano o da altri tool
#
# Usa sia la lista sul computer (changes/) sia la copia sul telefono, così funziona
# anche da un altro computer.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
ALL=; ONLY=
for a in "$@"; do case "$a" in --all) ALL=1 ;; -*) echo "Opzione sconosciuta: $a" >&2; exit 2 ;; *) ONLY="$ONLY $a" ;; esac; done
[ -z "$ALL" ] || WAIT=1
connect "$TARGET"
LOG=$(log_file)

failed=0
restored=
turn_on() { # tipo pacchetto
  case "$1" in
    off)
      sh_dev pm enable "$2" >/dev/null 2>&1 || true
      if is_off "$2"; then echo "  ERRORE  $2 è ancora spenta" >&2; failed=$((failed + 1)); return; fi ;;
    removed)
      sh_dev cmd package install-existing --user 0 "$2" >/dev/null 2>&1 \
        || sh_dev pm install-existing --user 0 "$2" >/dev/null 2>&1 || true
      # Può tornare installata ma spenta.
      is_off "$2" && sh_dev pm enable "$2" >/dev/null 2>&1 || true
      if ! installed "$2"; then echo "  ERRORE  $2 non è tornata" >&2; failed=$((failed + 1)); return; fi ;;
  esac
  echo "  accesa  $2"
  restored="$restored $2"
}

if [ -n "$ALL" ]; then
  echo "Soccorso: riattivo tutto quello che è spento o tolto per l'utente."
  for p in $(sh_dev pm list packages -d | sed -n 's/^package://p'); do turn_on off "$p"; done
  sh_dev pm list packages | sed -n 's/^package://p' | sort -u > "$LOG.on.$$"
  for p in $(sh_dev pm list packages -u | sed -n 's/^package://p' | sort -u | comm -23 - "$LOG.on.$$"); do
    turn_on removed "$p"
  done
  rm -f "$LOG.on.$$"
else
  # Le due liste insieme, senza doppioni. L'ultima riga per pacchetto vince.
  { [ -f "$LOG" ] && cat "$LOG"; sh_dev "cat $PHONE_LOG" 2>/dev/null || true; } \
    | grep -E '^(off|removed) [A-Za-z0-9_.]+$' | awk '{k[$2]=$1} END {for (p in k) print k[p], p}' | sort -k2 > "$LOG.todo.$$" || true
  if [ ! -s "$LOG.todo.$$" ]; then
    rm -f "$LOG.todo.$$"
    echo "Non trovo modifiche fatte con disable.sh su questo telefono."
    echo "Per riattivare comunque tutto ciò che è spento: sh undo.sh $TARGET --all"
    exit 0
  fi
  while read -r kind p; do
    if [ -n "$ONLY" ]; then case " $ONLY " in *" $p "*) ;; *) continue ;; esac; fi
    turn_on "$kind" "$p"
  done < "$LOG.todo.$$"
  rm -f "$LOG.todo.$$"
fi

# Toglie dalle liste ciò che è tornato acceso, così check.sh non lo rispegne.
if [ -n "$restored" ]; then
  for p in $restored; do
    if [ -f "$LOG" ]; then grep -v -E "^(off|removed) $p\$" "$LOG" > "$LOG.tmp" || true; mv "$LOG.tmp" "$LOG"; fi
    sh_dev "if [ -f $PHONE_LOG ]; then grep -v -E '^(off|removed) $p\$' $PHONE_LOG > $PHONE_LOG.tmp; mv $PHONE_LOG.tmp $PHONE_LOG; fi" >/dev/null 2>&1 || true
  done
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed app non sono tornate. Riprova, oppure a mano: adb shell pm enable <pacchetto>" >&2
  exit 1
fi
echo "Fatto. Riavvia il telefono per essere sicuro che tutto riparta come prima."
