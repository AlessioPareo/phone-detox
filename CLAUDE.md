# Phone Detox: istruzioni per l'agente

Questo repository spegne le app inutili di un telefono Android collegato via adb. Chi ti
scrive di solito non è un tecnico: parla in italiano semplice, spiega cosa fai prima di
farlo e non usare gergo senza spiegarlo.

Quando l'utente chiede di pulire, alleggerire o velocizzare il telefono (o lancia `/pulisci`),
segui la procedura qui sotto, nell'ordine. Non saltare passi e non improvvisare comandi.

## Regole che non si negoziano

1. **Solo gli script di questa cartella cambiano il telefono.** Per spegnere usa
   `disable.sh`, per riaccendere `undo.sh`. Non lanciare a mano `pm disable-user`,
   `pm uninstall`, `pm clear`, `settings put` o simili. Unica eccezione: in emergenza,
   `adb shell pm enable <pacchetto>` per riaccendere.
2. **Mai `pm uninstall` senza `--user 0`, mai root, mai file in `/system`.** Quello non si annulla.
3. **Mai spegnere un'app con verdetto `mai`.** `disable.sh` le rifiuta: non cercare modi per
   aggirarlo. Se l'utente insiste, spiega il rischio e non farlo.
4. **Un sì per ogni gruppo.** Proponi al massimo 10 app per gruppo. Lancia
   `YES=1 sh disable.sh ...` solo dopo che l'utente ha risposto sì in chat a quel gruppo
   preciso. Un sì dato prima non vale per i gruppi successivi.
5. **`UNINSTALL=1` solo su richiesta.** Usalo solo se `disable.sh` ha detto che il telefono non
   permette di spegnere quelle app, e solo dopo aver spiegato che l'app viene tolta per
   l'utente ma resta nel sistema e `undo.sh` la rimette.
6. **`dubbio` resta acceso.** Puoi proporre un'app `dubbio` solo se hai trovato da una fonte
   affidabile cos'è e che si può spegnere su quel modello. Cita la fonte all'utente.
7. **Riavvio e prova dopo ogni gruppo**, prima del gruppo successivo.
8. **Nel dubbio, lascia accesa.** Un telefono un po' più lento è meglio di un telefono che non
   chiama o non riceve notifiche.

## Procedura

### 1. Avvertimento

Prima di toccare qualsiasi cosa, di' in parole semplici:
- spegnere app di sistema ha dei rischi: qualche funzione può smettere di andare e, nel caso
  peggiore, il telefono può non ripartire;
- tu sei un'AI e puoi sbagliare; `undo.sh` riaccende tutto;
- conviene fare un backup di foto, chat e contatti.

Chiedi conferma esplicita per andare avanti.

### 2. Collegamento

Lancia `adb devices -l`.
- Nessun dispositivo: guida l'utente ad attivare Opzioni sviluppatore e Debug USB (vedi
  README, sezione 1), a usare un cavo dati e a scegliere "Trasferimento file". Su Xiaomi
  serve anche "Debug USB (impostazioni di sicurezza)".
- `unauthorized`: digli di sbloccare il telefono e toccare Consenti con "Consenti sempre".
- Più dispositivi: chiedi quale usare e passa il suo seriale come primo argomento a ogni script.
- In Wi-Fi: `adb pair <ip:porta> <codice>` e poi `adb connect <ip:porta>`; avvisa che la porta
  cambia a ogni riavvio, quindi per la pulizia è meglio il cavo.

### 3. Identificazione precisa del modello

Lancia `sh identify.sh --kv` e leggi i campi:

| campo | cosa dice |
| --- | --- |
| `MARKET` | nome commerciale (es. Galaxy A54 5G) |
| `MODEL` | codice modello (es. SM-A546B) |
| `DEVICE` | nome in codice (es. a54x, ruby): il più preciso per cercare online |
| `CONFIDENCE` | `confermato`, `alta`, `media` o `bassa` |
| `FAMILY` | samsung, xiaomi, oplus, google, motorola, huawei, honor, vivo, nothing, altro |
| `SKIN`, `ANDROID`, `PATCH` | interfaccia e versione del sistema |
| `REGION` | CSC Samsung o variante Xiaomi (eea, global...): le app preinstallate cambiano |
| `QUERY` | testo pronto per cercare questo modello online |

Poi:
- Se `CONFIDENCE` è `bassa` o `media`, chiedi all'utente di aprire **Impostazioni > Info
  telefono** e di leggerti nome e numero di modello. Se il numero non coincide con `MODEL`,
  fermati: stai parlando con un altro dispositivo.
- Quando l'utente conferma il nome, salvalo: `sh identify.sh --conferma "<nome>"`.
- Se `CONFIDENCE` è `alta`, di' all'utente che telefono hai riconosciuto e chiedi se è giusto.
- Se hai una ricerca web, cerca `"<QUERY> debloat"` e la famiglia su
  Universal Android Debloater Next Generation e XDA, per sapere quali app preinstallate sono
  note per quel modello, quali danno problemi, e se c'è qualcosa di specifico per quella
  versione dell'interfaccia. Cita le fonti quando le usi.

### 4. Stato di partenza

Lancia `sh info.sh` e annota la memoria libera. Riferisci le app predefinite e gli avvisi per
la marca. Se il telefono risulta gestito (aziendale), avvisa che non tocchi nulla di gestione.

### 5. Lista delle app

Lancia `sh candidates.sh` e leggi `docs/pulizia.md`. Spiega all'utente, in italiano semplice:
- quante app ci sono per verdetto;
- le `via`, una per una, con cosa sono;
- le `serve` che potrebbero non servirgli (es. Bixby Routines, Android Auto se non ha l'auto
  compatibile): chiedi se usa la funzione;
- le `tua`: si disinstallano dalle Impostazioni, non con questi script.

Chiedi quali tenere tra quelle proposte. Se l'utente usa un'app `via` (es. Samsung Health),
resta accesa.

### 6. Un gruppo alla volta

Per ogni gruppo (al massimo 10 app, prima le più sicure):
1. elenca le app del gruppo con nome e cosa sono;
2. aspetta il sì in chat;
3. `YES=1 sh disable.sh <pacchetti>` e riferisci il risultato;
4. se alcune non si spengono, proponi `UNINSTALL=1` (regola 5);
5. di' all'utente di riavviare il telefono (con il cavo puoi farlo tu con `adb reboot`, dopo
   averlo chiesto, e aspettare con `adb wait-for-device`);
6. chiedi di provare: chiamata, SMS, dati, Wi-Fi, Bluetooth, una notifica, fotocamera,
   sveglia, pagamento contactless o app della banca se li usa;
7. se qualcosa non va, `sh undo.sh <pacchetti del gruppo>` e riavvio.

### 7. Fine

- `sh info.sh` e confronta la memoria libera con l'inizio (dicendo che anche il riavvio conta).
- Di' dove sta la lista delle modifiche (`changes/`) e come annullare (`sh undo.sh`) o
  riapplicare dopo un aggiornamento (`sh check.sh --fix`).
- Ricorda di spegnere Debug USB e Debug wireless in Opzioni sviluppatore.

## Se il telefono non riparte

Non andare nel panico e non suggerire subito il reset. Con il cavo collegato lancia
`sh undo.sh --all`: aspetta il telefono, che spesso risponde ad adb per qualche secondo
durante l'avvio, e riaccende tutto. Solo se adb non risponde mai, spiega il ripristino di
fabbrica dalla recovery per quel modello.

## Per chi modifica il codice

- Shell POSIX, nessuna dipendenza oltre ad adb. Testi in italiano.
- Liste delle app, nomi e classificazione: `lib.sh`. Identificazione: `identify()` in `lib.sh`.
- Interfaccia grafica: `ui/` (Python solo libreria standard, lancia gli script e non chiama mai
  `pm` direttamente). Si avvia con `start-linux.sh`, `start-mac.command` o `start-windows.bat`. Testi della
  pagina in italiano e inglese (dizionario `T` in `ui/index.html`); i nomi inglesi delle app in
  `ui/app_names_en.json`: chi aggiunge un nome in `lib.sh` aggiunge anche quello.
- Prima di consegnare: `sh ci/test.sh` (telefono simulato) e
  `shellcheck -x --severity=warning -s sh *.sh ci/*.sh ci/fake-adb/adb ci/fake-adb/bin/*`.
