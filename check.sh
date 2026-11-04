#!/bin/sh
# Checks that turned-off apps stay off. System updates sometimes turn them back on.
#
#   sh check.sh [phone]                  checks the change list
#   sh check.sh [phone] --fix            and turns off again what came back
#   sh check.sh [phone] --fix list.txt   uses another list
#
# One change per line (# comments):
#   off com.example.app                  the app stays off
#   removed com.example.app              the app stays removed for the user
#   global window_animation_scale 0.5    a setting (global, secure or system)
#
# Each change gets one line starting with: ok, fixed, CHANGED or gone.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
FIX=; LIST=
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    -*) say "Opzione sconosciuta: $a" "Unknown option: $a" >&2; exit 2 ;;
    *) LIST=$a ;;
  esac
done
[ -z "$LIST" ] || [ -r "$LIST" ] || { say "Non riesco a leggere $LIST." "Can't read $LIST." >&2; exit 2; }
connect "$TARGET"
[ -n "$LIST" ] || LIST=$(log_file)
if [ ! -s "$LIST" ]; then
  # On another computer the list is only on the phone.
  sh_dev "cat $PHONE_LOG" 2>/dev/null > "$LIST" || true
fi
[ -s "$LIST" ] || { say "Nessuna modifica da controllare per questo telefono." "No changes to check for this phone."; exit 0; }

bad=0
result() { # name, test, how to fix...
  _name=$1 _ok=$2; shift 2
  if "$_ok"; then echo "  ok       $_name"; return; fi
  if [ -n "$FIX" ] && "$@" >/dev/null 2>&1 && "$_ok"; then echo "  fixed    $_name"; return; fi
  echo "  CHANGED  $_name"; bad=$((bad + 1))
}
setting_is() { [ "$(sh_dev settings get "$1" "$2")" = "$3" ]; }

grep -v '^[[:space:]]*#' "$LIST" | grep -v '^[[:space:]]*$' > "$LIST.check.$$" || true
while read -r kind a b c; do
  case "$kind" in
    off)
      if ! sh_dev pm list packages -u "$a" | grep -Fqx "package:$a"; then
        echo "  gone     $a ($(L 'non c'"'"'è più' 'no longer installed'))"; continue
      fi
      t() { is_off "$a"; }; result "$a off" t sh_dev pm disable-user --user 0 "$a" ;;
    removed)
      t() { ! installed "$a"; }; result "$a removed" t sh_dev pm uninstall -k --user 0 "$a" ;;
    global|secure|system)
      t() { setting_is "$kind" "$a" "$b"; }; result "$kind $a = $b" t sh_dev settings put "$kind" "$a" "$b" ;;
    *) echo "  ?        $(L 'non capisco' "don't understand"): $kind $a $b $c" ;;
  esac
done < "$LIST.check.$$"
rm -f "$LIST.check.$$"

if [ "$bad" -gt 0 ]; then
  if [ -n "$FIX" ]; then say "$bad modifiche non si sono potute sistemare." "$bad changes couldn't be fixed."
  else say "$bad modifiche sono cambiate. Rilancia con --fix per rimetterle a posto." "$bad changes were undone. Run again with --fix to restore them."; fi
  exit 1
fi
say "Tutto a posto." "All good."
