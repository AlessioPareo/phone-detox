# Phone Detox

### Togli il superfluo da un telefono Android, senza root e senza cancellare niente.

Un fork di [tv-detox](https://github.com/Ansub/tv-detox) di Ansub Khan, rifatto solo per i
telefoni. Niente home screen: qui c'è solo la pulizia, con regole e protezioni pensate per un
telefono (chiamate, SMS, notifiche, pagamenti, allerte di emergenza).

| **🧹 Spegne il superfluo**<br>Bloatware del produttore, pubblicità di sistema, doppioni. | **🛡️ Protegge l'essenziale**<br>Rifiuta di spegnere quello che serve al telefono e le app predefinite. | **↩️ Si annulla sempre**<br>Le app vengono spente, non cancellate. Un comando le riaccende. |
| --- | --- | --- |

> [!WARNING]
> **A tuo rischio.** Spegnere app di sistema può rompere funzioni o, nel caso peggiore,
> bloccare il telefono all'avvio. Gli script rifiutano le app pericolose note e chiedono
> conferma, ma non conoscono ogni telefono. Fai un backup prima di cominciare e vai a piccoli
> gruppi. `undo.sh` riaccende tutto.

## Cosa serve

- Un computer (Mac, Linux o Windows) con `adb`:
  - Mac: `brew install android-platform-tools`
  - Linux: `sudo apt install adb` (o il pacchetto della tua distribuzione)
  - Windows: scarica gli [SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)
    e lancia gli script da Git Bash
- Un cavo USB, oppure telefono e computer sulla stessa rete Wi-Fi
- Facoltativo: [Claude Code](https://claude.com/claude-code) o un altro agente che gira sul
  tuo computer, se vuoi che sia lui a guidarti

## 1. Attiva il debug sul telefono

1. **Impostazioni → Info telefono** e tocca 7 volte **Numero build** finché compare "Ora sei
   uno sviluppatore".
   - Samsung: Info telefono → Informazioni software → Numero build
   - Xiaomi, Redmi, POCO: Info telefono → Versione MIUI / Versione HyperOS
   - OnePlus, Oppo, Realme: Info dispositivo → Versione → Numero build
2. Torna indietro, apri **Opzioni sviluppatore** e attiva **Debug USB**.
   - Xiaomi: attiva anche **Debug USB (impostazioni di sicurezza)**.
3. Collega il cavo. Sul telefono compare "Consentire il debug USB?": spunta **Consenti
   sempre** e tocca **Consenti**.

**Senza cavo (Android 11+):** in Opzioni sviluppatore apri **Debug wireless → Associa
dispositivo con codice di associazione**, poi sul computer:

```
adb pair <IP>:<porta di associazione>     # e inserisci il codice
adb connect <IP>:<porta>                  # la porta mostrata nella schermata Debug wireless
```

Usa quell'indirizzo come primo argomento di ogni script. La porta cambia a ogni riavvio: per
la pulizia il cavo è più comodo, perché dopo ogni gruppo si riavvia.

## 2a. Con Claude Code

Scarica questo repository, apri Claude Code nella sua cartella e incolla:

```
Aiutami a pulire il mio telefono Android dalle app inutili usando gli script
di questa cartella. Il telefono è un <marca e modello>.

1. Prima di tutto dimmi in parole semplici che spegnere app di sistema ha dei
   rischi (funzioni rotte, nel caso peggiore un telefono che non riparte) e
   che tu puoi sbagliare. undo.sh riaccende tutto. Chiedimi conferma e
   ricordami di fare un backup.
2. Collegati al telefono e lancia info.sh. Guidami in quello che devo toccare.
3. Lancia candidates.sh e spiegami la lista in italiano semplice: cosa si può
   spegnere, cosa serve al telefono e cosa sono le app che uso. Leggi
   docs/pulizia.md e seguine le regole.
4. Proponimi gruppi di 5-10 app. Per ogni gruppo aspetta il mio sì, poi usa
   YES=1 sh disable.sh. Non spegnere mai un'app con verdetto "mai" e, nel
   dubbio, lasciala accesa. Usa UNINSTALL=1 solo se disable.sh dice che il
   telefono non permette di spegnerla, e chiedimelo prima.
5. Dopo ogni gruppo dimmi di riavviare e di provare chiamate, SMS, dati,
   Wi-Fi, Bluetooth, notifiche, fotocamera, sveglia e pagamenti. Se qualcosa
   non va, annulla quel gruppo con undo.sh.
6. Alla fine lancia di nuovo info.sh e mostrami la memoria libera prima e
   dopo.
7. Ricordami di spegnere Debug USB e Debug wireless (o tutte le Opzioni
   sviluppatore). Li riaccendo solo per undo.sh o check.sh.
```

La chat di Claude nell'app o su claude.ai non può farlo: gira sui server di Anthropic e non
vede il tuo telefono. Serve qualcosa che giri sul tuo computer.

## 2b. A mano

```
sh info.sh                     # cos'è il telefono, memoria libera, app predefinite
sh candidates.sh               # ogni app con un verdetto (non cambia niente)
sh disable.sh <app> <app> ...  # spegne, chiedendo conferma
sh undo.sh                     # riaccende tutto quello che hai spento
sh check.sh --fix              # dopo un aggiornamento, rispegne ciò che è tornato
```

Con più dispositivi collegati, o in Wi-Fi, metti il telefono come primo argomento:
`sh candidates.sh 192.168.1.20:41234` oppure `sh candidates.sh R58N123ABC` (il seriale di
`adb devices`).

### I verdetti di `candidates.sh`

```
mai     on     com.google.android.gms              Google Play Services
mai     on     com.sec.android.app.launcher        Schermata Home Samsung (app predefinita: HOME)
via     on     com.samsung.android.bixby.agent     Bixby
via     on     com.facebook.appmanager             Installer nascosto di Facebook
dubbio  on     com.vendor.qualcosa
tua     on     com.whatsapp
```

| verdetto | significato |
| --- | --- |
| `mai` | serve al telefono, è un'app predefinita o la tastiera in uso, è un amministratore del dispositivo, ha salvato il Wi-Fi, o Android la tiene sempre accesa. `disable.sh` la rifiuta. |
| `serve` | porta una funzione: sveglie, pagamenti, Android Auto, accessibilità... Via solo se non la usi. |
| `via` | di solito si può spegnere. |
| `dubbio` | sconosciuta: lasciala accesa finché non sai cos'è. |
| `tua` | installata da te: disinstallala dalle Impostazioni se non ti serve. |

[docs/pulizia.md](docs/pulizia.md) spiega le regole dietro i verdetti e cosa provare dopo ogni
gruppo.

### `disable.sh`

```
sh disable.sh com.samsung.android.bixby.agent com.samsung.android.app.tips
sh disable.sh -f lista.txt         # un pacchetto per riga
YES=1 sh disable.sh ...            # senza conferma (per Claude Code, dopo il tuo sì in chat)
UNINSTALL=1 sh disable.sh ...      # per le app che il telefono non lascia spegnere
```

Senza terminale interattivo e senza `YES=1` fa solo una prova a vuoto. Ogni modifica finisce
in `changes/<telefono>.txt` sul computer e in una copia sul telefono
(`/data/local/tmp/phone-detox.txt`), così `undo.sh` funziona anche da un altro computer.

`UNINSTALL=1` usa `pm uninstall -k --user 0`: l'app sparisce per te ma resta nel sistema, e
`undo.sh` la rimette senza reset. Servirà soprattutto su Samsung, OnePlus, Oppo e Realme
recenti.

## Annullare

```
sh undo.sh                        # tutto quello fatto con disable.sh
sh undo.sh com.esempio.app        # solo questa
sh undo.sh --all                  # soccorso: ogni app spenta o tolta, da chiunque
```

**Il telefono si riavvia in continuazione?** Se il debug USB era autorizzato, adb spesso
risponde per qualche secondo durante l'avvio. Collega il cavo e lancia `sh undo.sh --all`:
aspetta il telefono e riaccende tutto. Se adb non risponde mai, resta il ripristino di
fabbrica dalla recovery.

## Domande

**Serve il root?** No. Tutto passa da adb e vale per l'utente principale. Il sistema non viene
toccato, e un ripristino di fabbrica riporta il telefono com'era.

**Il telefono va più veloce?** Su telefoni economici o vecchi con tanto bloatware, di solito
sì: meno app in background, più memoria libera e meno notifiche pubblicitarie. Su un Pixel
c'è poco da togliere. `info.sh` mostra la memoria libera prima e dopo.

**Perché non usare direttamente Universal Android Debloater?**
[UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation)
è ottimo, ha un'interfaccia grafica e liste molto più ampie: se preferisci un'app, usa quello.
Questo progetto è pensato per essere guidato da un agente AI o dal terminale, ha protezioni
legate al tuo telefono (app predefinite, tastiera in uso, amministratori, chi ha salvato il
Wi-Fi, app PERSISTENT) e tiene una lista per annullare e per riapplicare dopo gli
aggiornamenti.

**Un aggiornamento ha riacceso qualcosa.** `sh check.sh` controlla, `sh check.sh --fix`
rimette a posto.

**App bancarie e pagamenti.** Non spegnere Play Services, NFC, il wallet o i servizi
dell'operatore. Dopo ogni gruppo apri l'app della banca e, se lo usi, prova un pagamento.

**Telefono aziendale o in finanziamento.** Lascia stare le app di gestione e gli
amministratori del dispositivo. `info.sh` ti dice se il telefono è gestito.

**Spegni il debug quando hai finito.** Con il Debug USB o wireless acceso, un computer
autorizzato può controllare il telefono. Riaccendilo solo quando ti serve.

## Per chi sviluppa

Gli script sono shell POSIX, senza dipendenze oltre ad `adb`. Le liste di app (`mai`, `serve`,
`via`) e i nomi in italiano stanno in `lib.sh`.

```
sh ci/test.sh       # prova tutti gli script su un telefono simulato, senza telefono vero
shellcheck -x -s sh *.sh ci/*.sh
```

Il telefono simulato (`ci/fake-adb/`) è un finto `adb` che risponde ai comandi usati dagli
script. Per aggiungere un caso, modifica il telefono finto in `ci/test.sh`.

Pull request benvenute, soprattutto per le liste per marca: indica modello, versione di
Android e cosa hai provato dopo aver spento l'app.

## Crediti e licenza

Basato su [tv-detox](https://github.com/Ansub/tv-detox) di Ansub Khan (licenza MIT): l'idea,
la struttura degli script e le regole di base (spegnere invece di cancellare, PERSISTENT,
chi ha salvato il Wi-Fi) vengono da lì. Liste di app ricavate in parte da
[Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation).

Licenza MIT, vedi [LICENSE](LICENSE).
