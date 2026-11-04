# Phone Detox

[English](README.md) · **Italiano**

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

Se usi l'app (sezione [2a](#2a-con-lapp-la-più-semplice)) ti basta Python, e su Windows Git for
Windows: adb lo scarica l'app. Per le altre strade:

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

## 2. Scegli come procedere

Quattro strade, dalla più semplice alla più manuale. In tutte il primo passo è capire con
precisione che telefono è collegato (vedi [Identificare il telefono](#identificare-il-telefono)).

### 2a. Con l'app (la più semplice)

Un'app nel browser che fa tutta la procedura con i pulsanti, in italiano o in inglese.
Non servono conoscenze tecniche.

**1. Scarica Phone Detox.** In cima alla pagina GitHub clicca **Code → Download ZIP** e
scompatta lo zip (su Windows: tasto destro → Estrai tutto).

**2. Installa quello che manca** (una volta sola):

| | cosa serve |
| --- | --- |
| **Windows** | [Python](https://www.python.org/downloads/) (durante l'installazione spunta **"Add python.exe to PATH"**) e [Git for Windows](https://git-scm.com/download/win) (lascia le opzioni come sono) |
| **Mac** | niente: se manca Python, il Mac propone di installarlo la prima volta |
| **Linux** | niente sulla maggior parte delle distribuzioni (Python 3 c'è già) |

adb, il programma che parla con il telefono, non serve installarlo: lo scarica l'app dal sito
di Google.

**3. Apri l'app** dalla cartella di Phone Detox:

| | come |
| --- | --- |
| **Windows** | doppio clic su `start-windows.bat` |
| **Mac** | doppio clic su `start-mac.command` (la prima volta: tasto destro → **Apri**) |
| **Linux** | apri un terminale nella cartella e scrivi `sh start-linux.sh` |

Resta aperta una piccola finestra (non chiuderla) e l'app si apre nel browser.

**4. Segui i passi nella pagina:**

1. **Prima di iniziare**: cosa può andare storto e il promemoria del backup.
2. **Collega**: come attivare il Debug USB, con le istruzioni per Samsung, Xiaomi, OnePlus e
   altri. La pagina si accorge da sola del telefono e ti dice cosa fare se chiede il
   permesso. Funziona anche in Wi-Fi.
3. **Il tuo telefono**: il modello esatto, da confermare guardando Impostazioni → Info
   telefono.
4. **Le app**: tutte le app del telefono con un nome comprensibile, divise in *Consigliate*,
   *Forse ti servono*, *Tue*, *Sconosciute*, *Di sistema*. Spunta fino a 10 app, oppure premi
   **Scegli per me le più sicure**. Poi riavvia e prova il telefono con una lista di controllo.
   Se qualcosa non va, un pulsante riaccende il gruppo.
5. **Fine**: memoria libera prima e dopo, e il promemoria per spegnere il Debug USB.

Sotto usa gli stessi script, con le stesse protezioni: le app `never` restano rifiutate e le
`unknown` si possono scegliere solo con la modalità esperto. Se chiudi a metà, alla riapertura
riprende da dove eri.

### 2b. Con Claude Code

Scarica questo repository, apri [Claude Code](https://claude.com/claude-code) nella sua
cartella e scrivi:

```
/clean
```

Claude legge da solo [CLAUDE.md](CLAUDE.md), con la procedura e le regole: ti avvisa dei
rischi, identifica il modello, cerca online le app note per quel telefono, ti propone gruppi
di app e aspetta il tuo sì per ognuno. Ci sono anche `/identify` (che telefono è) e `/undo` (annulla). Scrivi pure in italiano:
Claude risponde in italiano.

Il prompt completo da incollare, utile anche con Codex, Gemini CLI o Cursor, è in
[PROMPT.md](PROMPT.md).

La chat di Claude nell'app o su claude.ai non può farlo: gira sui server di Anthropic e non
vede il tuo telefono. Serve qualcosa che giri sul tuo computer.

### 2c. Procedura guidata nel terminale, senza AI

```
sh guide.sh
```

Fa tutto a domande: controlla il collegamento (e ti aiuta se il telefono non si vede, anche
in Wi-Fi), identifica il modello e te lo fa confermare, ti mostra le app che si possono
spegnere con un numero accanto, spegne quelle che scegli, riavvia il telefono, ti dice cosa
provare e, se qualcosa non va, riaccende il gruppo. Alla fine mostra la memoria libera prima
e dopo. Puoi fermarti quando vuoi e riprendere dopo.

### 2d. A mano

```
sh identify.sh                 # che telefono è, con quanta certezza
sh info.sh                     # memoria libera, app predefinite, avvisi per la marca
sh candidates.sh               # ogni app con un verdetto (non cambia niente)
sh disable.sh <app> <app> ...  # spegne, chiedendo conferma
sh undo.sh                     # riaccende tutto quello che hai spento
sh check.sh --fix              # dopo un aggiornamento, rispegne ciò che è tornato
```

Gli script parlano italiano se il computer è in italiano, altrimenti inglese. Per scegliere:
`PD_LANG=it sh guide.sh` (oppure `PD_LANG=en`). Le etichette (`never`, `bloat`, `off`…) sono
sempre in inglese.

Con più dispositivi collegati, o in Wi-Fi, metti il telefono come primo argomento:
`sh candidates.sh 192.168.1.20:41234` oppure `sh candidates.sh R58N123ABC` (il seriale di
`adb devices`).

## Identificare il telefono

Ogni produttore preinstalla app diverse, e cambiano anche tra varianti dello stesso modello
(europea, americana, operatore). Per questo si parte da `identify.sh`:

```
== Il tuo telefono
   samsung Galaxy A54 5G (SM-A546B)
   Certezza        confermato - confermato dall'utente
   Codice modello  SM-A546B
   Serie           Galaxy A, variante europea/internazionale
   Nome in codice  a54x
   Chip            Samsung s5e8835
   RAM             8027 MB
== Sistema
   Android         14 (SDK 34)
   Interfaccia     One UI 6.1
   Patch sicurezza 2026-09-01
   Regione/CSC     ITV
   Operatore SIM   TIM
== Per cercarlo online
   "Galaxy A54 5G SM-A546B" debloat
```

Android non scrive il nome commerciale sempre nello stesso posto. Lo script prova tutte le
proprietà note (Xiaomi, Oppo, OnePlus, Realme, vivo, Motorola, Asus...) e dice quanto è sicuro:

| certezza | da dove viene |
| --- | --- |
| `confirmed` | l'hai confermato tu, guardando Impostazioni > Info telefono |
| `high` | il produttore scrive il nome commerciale in una proprietà di sistema (o è un Pixel) |
| `medium` | dal nome del dispositivo, che però si può cambiare a mano |
| `low` | c'è solo il codice modello: va confermato |

Se non è `high` o `confirmed`, apri **Impostazioni > Info telefono**, controlla che il numero
di modello sia lo stesso e salva il nome:

```
sh identify.sh --confirm "Galaxy A54 5G"
```

Per i Samsung lo script ricava comunque la serie e la variante dal codice (SM-A = Galaxy A,
finale B = europea). `sh identify.sh --kv` dà le stesse informazioni come righe
`CHIAVE=valore`, ed è quello che usa Claude. La scheda resta salvata in
`changes/<telefono>.identity.txt`.

## I verdetti di `candidates.sh`

```
never    on       com.google.android.gms              Google Play Services
never    on       com.sec.android.app.launcher        Schermata Home Samsung (app predefinita: HOME)
bloat    on       com.samsung.android.bixby.agent     Bixby
bloat    on       com.facebook.appmanager             Installer nascosto di Facebook
unknown  on       com.vendor.qualcosa
yours    on       com.whatsapp
```

| verdetto | significato |
| --- | --- |
| `never` | serve al telefono, è un'app predefinita o la tastiera in uso, è un amministratore del dispositivo, ha salvato il Wi-Fi, o Android la tiene sempre accesa. `disable.sh` la rifiuta. |
| `useful` | porta una funzione: sveglie, pagamenti, Android Auto, accessibilità... Via solo se non la usi. |
| `bloat` | di solito si può spegnere. |
| `unknown` | sconosciuta: lasciala accesa finché non sai cos'è. |
| `yours` | installata da te: disinstallala dalle Impostazioni se non ti serve. |

[docs/pulizia.md](docs/pulizia.md) spiega le regole dietro i verdetti e cosa provare dopo ogni
gruppo.

## `disable.sh`

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

Gli script sono shell POSIX, senza dipendenze oltre ad `adb`. Le liste di app (`never`, `useful`,
`bloat`) e i nomi delle app in italiano e inglese stanno in `lib.sh`. Codice, nomi, commenti
ed etichette sono in inglese; i messaggi per l'utente in italiano e inglese (`say` in `lib.sh`).

```
sh ci/test.sh       # prova tutti gli script su un telefono simulato, senza telefono vero
shellcheck -x -s sh *.sh ci/*.sh
```

L'app sta in `ui/`: `phone_detox_ui.py` è un piccolo server locale (solo libreria standard di
Python, ascolta solo su 127.0.0.1 e vuole un token) che lancia gli script; `index.html` è la
pagina, con tutti i testi in italiano e inglese nel dizionario `T`. `ci/test_ui.py` la prova sul telefono simulato ed è lanciato da
`ci/test.sh`.

Il telefono simulato (`ci/fake-adb/`) è un finto `adb` che risponde ai comandi usati dagli
script. Per aggiungere un caso, modifica il telefono finto in `ci/test.sh`.

Le istruzioni per gli agenti sono in `CLAUDE.md` (Codex e altri le trovano tramite
`AGENTS.md`); i comandi `/clean`, `/identify` e `/undo` in `.claude/commands/`.
`.claude/settings.json` lascia lanciare senza conferma solo gli script che non cambiano niente
e blocca i comandi adb distruttivi.

Pull request benvenute, soprattutto per le liste per marca: indica modello, versione di
Android e cosa hai provato dopo aver spento l'app.

## Crediti e licenza

Basato su [tv-detox](https://github.com/Ansub/tv-detox) di Ansub Khan (licenza MIT): l'idea,
la struttura degli script e le regole di base (spegnere invece di cancellare, PERSISTENT,
chi ha salvato il Wi-Fi) vengono da lì. Liste di app ricavate in parte da
[Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation).

Licenza MIT, vedi [LICENSE](LICENSE).
