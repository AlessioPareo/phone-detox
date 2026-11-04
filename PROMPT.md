# Il prompt da dare a Claude

Apri [Claude Code](https://claude.com/claude-code) **nella cartella di questo repository**, sul
computer a cui è collegato il telefono. Claude legge da solo [CLAUDE.md](CLAUDE.md), che
contiene tutte le regole e la procedura.

## Il modo più breve

Scrivi:

```
/pulisci
```

Puoi aggiungere dettagli dopo il comando, per esempio `/pulisci uso Samsung Health e Android Auto`.

Altri comandi:

- `/identifica`: dice che telefono è collegato, con nome commerciale e codice modello, senza
  cambiare niente
- `/annulla`: riaccende tutto, oppure `/annulla com.esempio.app` per una sola app

## Il prompt completo

Se preferisci scriverlo tu, o usi un altro agente (Codex, Gemini CLI, Cursor), incolla questo
riempiendo le parti tra `< >`:

```
Aiutami a pulire il mio telefono Android dalle app inutili, usando gli script
di questa cartella e seguendo CLAUDE.md.

Il mio telefono: <marca e modello, se lo sai, altrimenti scrivi "non lo so">
Le app e le funzioni che uso e che devono restare: <es. Samsung Health,
Android Auto, pagamenti con il telefono, sveglia, app della banca>
Come è collegato: <cavo USB / Wi-Fi>

1. Prima di tutto dimmi in parole semplici che spegnere app di sistema ha dei
   rischi e che tu puoi sbagliare, ricordami il backup e chiedimi conferma.
2. Collegati e identifica con precisione il telefono con identify.sh. Se non
   sei sicuro del modello, chiedimi di leggerti Impostazioni > Info telefono e
   salva il nome che ti dico.
3. Cerca online le app preinstallate note per il mio modello preciso e dimmi
   le fonti.
4. Mostrami la memoria libera con info.sh e la lista delle app con
   candidates.sh, spiegata in italiano semplice.
5. Proponimi gruppi di al massimo 10 app. Aspetta il mio sì per ogni gruppo.
   Non toccare mai le app "mai", e nel dubbio lasciale accese.
6. Dopo ogni gruppo fammi riavviare e provare chiamate, SMS, dati, Wi-Fi,
   Bluetooth, notifiche, fotocamera, sveglia e pagamenti. Se qualcosa non va,
   annulla quel gruppo.
7. Alla fine mostrami la memoria libera prima e dopo e ricordami di spegnere
   il debug USB e wireless.
```

## Se usi un agente senza questa cartella

La chat di Claude nell'app o su claude.ai non vede il tuo telefono: gira sui server di
Anthropic. Serve un agente che giri sul tuo computer, nella cartella di questo repository,
così ha gli script e le loro protezioni. Senza gli script l'agente userebbe adb a mano, senza
le liste `mai` e senza la lista per annullare: non farlo.
