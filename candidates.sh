#!/bin/sh
# Elenca tutte le app del telefono con un verdetto. Non cambia niente.
#
#   sh candidates.sh [telefono]
#
#   VERDETTO  STATO  PACCHETTO                          COS'È
#
#   mai     serve al telefono (avvio, chiamate, SMS, rete, sicurezza) o Android la tiene
#           sempre accesa. Non toccarla.
#   serve   porta una funzione che potresti usare. Via solo se non la usi.
#   via     di solito si può disattivare: pubblicità, doppioni, app del produttore.
#   dubbio  non so cos'è. Nel dubbio resta accesa.
#   tua     installata da te: si disinstalla normalmente dalle Impostazioni.
#
# Stato: on, off (disattivata) o tolta (rimossa per l'utente, si rimette con undo.sh).
# docs/pulizia.md spiega cosa fare con la lista.
set -e
. "$(dirname "$0")/lib.sh"

connect "$1"
out=$(mktemp 2>/dev/null || mktemp -t phonedetox)
trap 'rm -f "$out"' EXIT
classify "$out"
awk -F'\t' '{ printf "%-7s %-6s %-48s %s\n", $1, $2, $3, $4 }' "$out"

count() { awk -F'\t' -v v="$1" '$1==v' "$out" | grep -c . || true; }
echo
echo "mai $(count mai) | serve $(count serve) | via $(count via) | dubbio $(count dubbio) | tua $(count tua)"
echo
echo "via = di solito si può disattivare. dubbio = sconosciuta: lasciala accesa se non sai cos'è."
echo "Prima di disattivare leggi docs/pulizia.md, e vai a gruppi di 5-10 app alla volta:"
echo "  sh disable.sh $1 <pacchetto> <pacchetto> ..."
