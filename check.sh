#!/bin/sh
# Controlla che le app spente restino spente. Gli aggiornamenti di sistema a volte le riaccendono.
#
#   sh check.sh [telefono]                 controlla la lista delle modifiche
#   sh check.sh [telefono] --fix           e rispegne quello che si è riacceso
#   sh check.sh [telefono] --fix lista.txt usa un'altra lista
#
# Una modifica per riga (# commenta):
#   off com.esempio.app                  l'app resta spenta
#   removed com.esempio.app              l'app resta tolta per l'utente
#   global window_animation_scale 0.5    un'impostazione (global, secure o system)
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
FIX=; LIST=
for a in "$@"; do case "$a" in --fix) FIX=1 ;; -*) echo "Opzione sconosciuta: $a" >&2; exit 2 ;; *) LIST=$a ;; esac; done
[ -z "$LIST" ] || [ -r "$LIST" ] || { echo "Non riesco a leggere $LIST." >&2; exit 2; }
connect "$TARGET"
[ -n "$LIST" ] || LIST=$(log_file)
if [ ! -s "$LIST" ]; then
  # Su un altro computer la lista è solo sul telefono.
  sh_dev "cat $PHONE_LOG" 2>/dev/null > "$LIST" || true
fi
[ -s "$LIST" ] || { echo "Nessuna modifica da controllare per questo telefono."; exit 0; }

bad=0
result() { # nome, ok?, come sistemare...
  _name=$1 _ok=$2; shift 2
  if "$_ok"; then echo "  ok        $_name"; return; fi
  if [ -n "$FIX" ] && "$@" >/dev/null 2>&1 && "$_ok"; then echo "  sistemato $_name"; return; fi
  echo "  CAMBIATO  $_name"; bad=$((bad + 1))
}
setting_is() { [ "$(sh_dev settings get "$1" "$2")" = "$3" ]; }

grep -v '^[[:space:]]*#' "$LIST" | grep -v '^[[:space:]]*$' > "$LIST.check.$$" || true
while read -r kind a b c; do
  case "$kind" in
    off)
      if ! sh_dev pm list packages -u "$a" | grep -Fqx "package:$a"; then echo "  sparita   $a (non c'è più)"; continue; fi
      t() { is_off "$a"; }; result "$a spenta" t sh_dev pm disable-user --user 0 "$a" ;;
    removed)
      t() { ! installed "$a"; }; result "$a tolta" t sh_dev pm uninstall -k --user 0 "$a" ;;
    global|secure|system)
      t() { setting_is "$kind" "$a" "$b"; }; result "$kind $a = $b" t sh_dev settings put "$kind" "$a" "$b" ;;
    *) echo "  ?         non capisco: $kind $a $b $c" ;;
  esac
done < "$LIST.check.$$"
rm -f "$LIST.check.$$"

if [ "$bad" -gt 0 ]; then
  if [ -n "$FIX" ]; then echo "$bad cosa/e non si sono potute sistemare."
  else echo "$bad cosa/e sono cambiate. Rilancia con --fix per rimetterle a posto."; fi
  exit 1
fi
echo "Tutto a posto."
