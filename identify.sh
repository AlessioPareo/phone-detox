#!/bin/sh
# Identifica con precisione il telefono collegato: nome commerciale, codice modello, variante,
# versione del sistema, chip e regione. Non cambia niente sul telefono.
#
#   sh identify.sh [telefono]                      scheda leggibile
#   sh identify.sh [telefono] --kv                 righe CHIAVE=valore (per Claude o altri script)
#   sh identify.sh [telefono] --conferma "Nome"    salva il nome che leggi in Impostazioni > Info telefono
#
# Il nome commerciale non è scritto sempre nello stesso posto: lo script prova tutte le
# proprietà note e dice quanto è affidabile il risultato. Se non è "alta" o "confermato",
# confrontalo con Impostazioni > Info telefono e salvalo con --conferma.
set -e
. "$(dirname "$0")/lib.sh"

TARGET=
if is_target "$1"; then TARGET=$1; shift; fi
MODE=scheda; CONFIRM=
while [ $# -gt 0 ]; do
  case "$1" in
    --kv) MODE=kv; shift ;;
    --conferma) MODE=conferma; CONFIRM=$2; shift 2 || { echo "Manca il nome dopo --conferma." >&2; exit 2; } ;;
    *) echo "Opzione sconosciuta: $1" >&2; exit 2 ;;
  esac
done
connect "$TARGET"
IDF=$(identity_file)

if [ "$MODE" = conferma ]; then
  case "$CONFIRM" in ""|*'
'*) echo "Scrivi il nome tra virgolette, es. --conferma \"Galaxy A54 5G\"." >&2; exit 2 ;; esac
  { [ -f "$IDF" ] && grep -v '^NOME_CONFERMATO=' "$IDF"; printf 'NOME_CONFERMATO=%s\n' "$CONFIRM"; } > "$IDF.tmp" || true
  mv "$IDF.tmp" "$IDF"
  echo "Salvato: questo telefono è un $CONFIRM."
  exit 0
fi

kv=$(identify)
# La scheda resta anche sul computer: utile per confrontare prima e dopo un aggiornamento.
{ printf '%s\n' "$kv"; [ -f "$IDF" ] && grep '^NOME_CONFERMATO=' "$IDF"; } > "$IDF.tmp" || true
mv "$IDF.tmp" "$IDF"

if [ "$MODE" = kv ]; then printf '%s\n' "$kv"; exit 0; fi

v() { printf '%s\n' "$kv" | sed -n "s/^$1=//p"; }
line() { [ -z "$2" ] || printf '   %-15s %s\n' "$1" "$2"; }

echo "== Il tuo telefono"
if [ -n "$(v MARKET)" ]; then
  echo "   $(v MAKER) $(v MARKET) ($(v MODEL))"
else
  echo "   $(v MAKER) $(v MODEL)"
fi
line "Certezza" "$(v CONFIDENCE) - $(v SOURCE)"
line "Codice modello" "$(v MODEL)"
line "Serie" "$(v SERIES)"
line "Nome in codice" "$(v DEVICE)"
line "Marca" "$(v BRAND)"
line "Chip" "$(v SOC)"
r=$(v RAM_MB); [ -z "$r" ] || line "RAM" "$r MB"
line "Memoria" "$(v STORAGE)"

echo "== Sistema"
line "Android" "$(v ANDROID) (SDK $(v SDK))"
line "Interfaccia" "$(v SKIN)"
line "Patch sicurezza" "$(v PATCH)"
line "Build" "$(v BUILD)"
line "Regione/CSC" "$(v REGION)"
line "Operatore SIM" "$(v CARRIER)"

echo "== Per cercarlo online"
echo "   \"$(v QUERY)\" debloat"

case "$(v CONFIDENCE)" in
  alta|confermato) ;;
  *)
    echo "== Da confermare"
    echo "   Il nome commerciale non è certo. Sul telefono apri Impostazioni > Info telefono"
    echo "   (su Samsung: Info telefono, in alto) e controlla nome e numero di modello."
    echo "   Il numero di modello deve essere $(v MODEL). Poi salva il nome:"
    echo "     sh identify.sh $TARGET --conferma \"Nome che leggi\"" ;;
esac
