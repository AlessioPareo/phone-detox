#!/bin/sh
# Identifies the connected phone precisely: marketing name, model number, variant, system
# version, chip and region. Changes nothing on the phone.
#
#   sh identify.sh [phone]                     readable card
#   sh identify.sh [phone] --kv                KEY=value lines (for Claude and other programs)
#   sh identify.sh [phone] --confirm "Name"    saves the name you read in Settings > About phone
#
# The marketing name isn't always stored in the same place: the script tries every known
# property and says how reliable the result is. If it isn't "high" or "confirmed", compare it
# with Settings > About phone and save it with --confirm.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
MODE=card; CONFIRM=
while [ $# -gt 0 ]; do
  case "$1" in
    --kv) MODE=kv; shift ;;
    --confirm)
      MODE=confirm; CONFIRM=$2
      shift 2 || { say "Manca il nome dopo --confirm." "The name is missing after --confirm." >&2; exit 2; } ;;
    *) say "Opzione sconosciuta: $1" "Unknown option: $1" >&2; exit 2 ;;
  esac
done
connect "$TARGET"
IDF=$(identity_file)

if [ "$MODE" = confirm ]; then
  case "$CONFIRM" in ""|*'
'*) say "Scrivi il nome tra virgolette, es. --confirm \"Galaxy A54 5G\"." \
        "Write the name in quotes, e.g. --confirm \"Galaxy A54 5G\"." >&2; exit 2 ;; esac
  { [ -f "$IDF" ] && grep -v -e '^CONFIRMED_NAME=' -e '^NOME_CONFERMATO=' "$IDF"; printf 'CONFIRMED_NAME=%s\n' "$CONFIRM"; } > "$IDF.tmp" || true
  mv "$IDF.tmp" "$IDF"
  say "Salvato: questo telefono è un $CONFIRM." "Saved: this phone is a $CONFIRM."
  exit 0
fi

kv=$(identify)
# Keep the card on the computer too: useful to compare before and after an update.
{ printf '%s\n' "$kv"; [ -f "$IDF" ] && grep -e '^CONFIRMED_NAME=' -e '^NOME_CONFERMATO=' "$IDF"; } > "$IDF.tmp" || true
mv "$IDF.tmp" "$IDF"

if [ "$MODE" = kv ]; then printf '%s\n' "$kv"; exit 0; fi

v() { printf '%s\n' "$kv" | sed -n "s/^$1=//p"; }
line() { [ -z "$2" ] || printf '   %-17s %s\n' "$1" "$2"; }

say "== Il tuo telefono" "== Your phone"
if [ -n "$(v MARKET)" ]; then
  echo "   $(v MAKER) $(v MARKET) ($(v MODEL))"
else
  echo "   $(v MAKER) $(v MODEL)"
fi
line "$(L Certezza Confidence)" "$(v CONFIDENCE) - $(v SOURCE)"
line "$(L 'Codice modello' 'Model number')" "$(v MODEL)"
line "$(L Serie Series)" "$(v SERIES)"
line "$(L 'Nome in codice' Codename)" "$(v DEVICE)"
line "$(L Marca Brand)" "$(v BRAND)"
line "Chip" "$(v SOC)"
r=$(v RAM_MB); [ -z "$r" ] || line "RAM" "$r MB"
line "$(L Memoria Storage)" "$(v STORAGE)"

say "== Sistema" "== System"
line "Android" "$(v ANDROID) (SDK $(v SDK))"
line "$(L Interfaccia Skin)" "$(v SKIN)"
line "$(L 'Patch sicurezza' 'Security patch')" "$(v PATCH)"
line "Build" "$(v BUILD)"
line "$(L Regione/CSC Region/CSC)" "$(v REGION)"
line "$(L 'Operatore SIM' 'SIM carrier')" "$(v CARRIER)"

say "== Per cercarlo online" "== To look it up online"
echo "   \"$(v QUERY)\" debloat"

case "$(v CONFIDENCE)" in
  high|confirmed) ;;
  *)
    say "== Da confermare" "== To confirm"
    say "   Il nome commerciale non è certo. Sul telefono apri Impostazioni > Info telefono" \
        "   The marketing name isn't certain. On the phone open Settings > About phone"
    say "   (su Samsung: Info telefono, in alto) e controlla nome e numero di modello." \
        "   (on Samsung: About phone, at the top) and check the name and model number."
    say "   Il numero di modello deve essere $(v MODEL). Poi salva il nome:" \
        "   The model number must be $(v MODEL). Then save the name:"
    say "     sh identify.sh $TARGET --confirm \"Nome che leggi\"" \
        "     sh identify.sh $TARGET --confirm \"Name you read\"" ;;
esac
