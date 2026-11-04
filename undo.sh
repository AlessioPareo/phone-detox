#!/bin/sh
# Turns back on the apps that disable.sh turned off or removed.
#
#   sh undo.sh [phone]                  everything in the change list
#   sh undo.sh [phone] <package> ...    only these
#   sh undo.sh [phone] --all            rescue: turns on EVERY app that's off or removed for
#                                       the user, including those done by hand or other tools
#
# Uses both the list on the computer (changes/) and the copy on the phone, so it works from
# another computer too. Each app gets one line starting with "on", or "ERROR".
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
ALL=; ONLY=
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    -*) say "Opzione sconosciuta: $a" "Unknown option: $a" >&2; exit 2 ;;
    *) ONLY="$ONLY $a" ;;
  esac
done
[ -z "$ALL" ] || WAIT=1
connect "$TARGET"
LOG=$(log_file)

failed=0
restored=
turn_on() { # kind package
  case "$1" in
    off)
      sh_dev pm enable "$2" >/dev/null 2>&1 || true
      if is_off "$2"; then echo "  ERROR    $2 $(L 'è ancora spenta' 'is still off')" >&2; failed=$((failed + 1)); return; fi ;;
    removed)
      sh_dev cmd package install-existing --user 0 "$2" >/dev/null 2>&1 \
        || sh_dev pm install-existing --user 0 "$2" >/dev/null 2>&1 || true
      # It can come back installed but disabled.
      is_off "$2" && sh_dev pm enable "$2" >/dev/null 2>&1 || true
      if ! installed "$2"; then echo "  ERROR    $2 $(L 'non è tornata' "didn't come back")" >&2; failed=$((failed + 1)); return; fi ;;
  esac
  echo "  on       $2"
  restored="$restored $2"
}

if [ -n "$ALL" ]; then
  say "Soccorso: riaccendo tutto quello che è spento o tolto per l'utente." \
      "Rescue: turning on everything that's off or removed for the user."
  for p in $(sh_dev pm list packages -d | sed -n 's/^package://p'); do turn_on off "$p"; done
  sh_dev pm list packages | sed -n 's/^package://p' | sort -u > "$LOG.on.$$"
  for p in $(sh_dev pm list packages -u | sed -n 's/^package://p' | sort -u | comm -23 - "$LOG.on.$$"); do
    turn_on removed "$p"
  done
  rm -f "$LOG.on.$$"
else
  # Both lists together, without duplicates. The last line per package wins.
  { [ -f "$LOG" ] && cat "$LOG"; sh_dev "cat $PHONE_LOG" 2>/dev/null || true; } \
    | grep -E '^(off|removed) [A-Za-z0-9_.]+$' | awk '{k[$2]=$1} END {for (p in k) print k[p], p}' | sort -k2 > "$LOG.todo.$$" || true
  if [ ! -s "$LOG.todo.$$" ]; then
    rm -f "$LOG.todo.$$"
    say "Non trovo modifiche fatte con disable.sh su questo telefono." \
        "No changes made with disable.sh found on this phone."
    say "Per riaccendere comunque tutto ciò che è spento: sh undo.sh $TARGET --all" \
        "To turn on everything that's off anyway: sh undo.sh $TARGET --all"
    exit 0
  fi
  while read -r kind p; do
    if [ -n "$ONLY" ]; then case " $ONLY " in *" $p "*) ;; *) continue ;; esac; fi
    turn_on "$kind" "$p"
  done < "$LOG.todo.$$"
  rm -f "$LOG.todo.$$"
fi

# Drop from the lists what's back on, so check.sh doesn't turn it off again.
if [ -n "$restored" ]; then
  for p in $restored; do
    if [ -f "$LOG" ]; then grep -v -E "^(off|removed) $p\$" "$LOG" > "$LOG.tmp" || true; mv "$LOG.tmp" "$LOG"; fi
    sh_dev "if [ -f $PHONE_LOG ]; then grep -v -E '^(off|removed) $p\$' $PHONE_LOG > $PHONE_LOG.tmp; mv $PHONE_LOG.tmp $PHONE_LOG; fi" >/dev/null 2>&1 || true
  done
fi

echo
if [ "$failed" -gt 0 ]; then
  say "$failed app non sono tornate. Riprova, oppure a mano: adb shell pm enable <pacchetto>" \
      "$failed apps didn't come back. Try again, or by hand: adb shell pm enable <package>" >&2
  exit 1
fi
say "Fatto. Riavvia il telefono per essere sicuro che tutto riparta come prima." \
    "Done. Restart the phone to be sure everything starts as before."
