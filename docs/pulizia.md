# Pulire il telefono senza romperlo

[English](cleanup.md) · **Italiano**

Spegnere le app inutili è una scelta app per app, quindi non è automatica. Questa pagina
raccoglie le regole che la rendono sicura e reversibile.

Parti da `sh candidates.sh`. Elenca ogni app del telefono con un verdetto e non cambia niente:

| verdetto | significato |
| --- | --- |
| `mai` | serve al telefono (avvio, chiamate, SMS, rete, sicurezza) o Android la tiene sempre accesa. |
| `serve` | porta una funzione che potresti usare. Via solo se non la usi. |
| `via` | di solito si può spegnere: pubblicità, doppioni, app del produttore. |
| `dubbio` | sconosciuta. Resta accesa finché non sai cos'è. |
| `tua` | installata da te: si disinstalla normalmente dalle Impostazioni. |

Poi spegni a gruppi con `sh disable.sh <app> <app> ...`, riavvia e prova il telefono.

## Le regole

### 1. Spegni, non cancellare

`pm disable-user --user 0 <app>` spegne un'app e `pm enable <app>` la riaccende. È quello che
fa `disable.sh`.

Alcuni telefoni (molti Samsung recenti, ColorOS, OxygenOS) non lasciano spegnere certe app di
sistema da adb. In quel caso `UNINSTALL=1` usa `pm uninstall -k --user 0`: l'app sparisce per
te ma il file resta nel sistema, e `undo.sh` la rimette con `cmd package install-existing`,
senza reset. Non usare mai `pm uninstall` senza `--user 0`, né strumenti che cancellano file
da `/system`: quello non si annulla.

### 2. Non toccare quello che fa funzionare un telefono

Avvio, schermata Home, tastiera, Impostazioni, chiamate, SMS, rete mobile, Wi-Fi, Bluetooth,
NFC, installazione delle app, configurazione iniziale. Se ne spegni una puoi trovarti con un
telefono che non riparte o non chiama, e adb è l'unica via di ritorno. `candidates.sh` le
segna `mai`, compresi i componenti del chip (`com.qualcomm.qti.*`, `com.mediatek.*` e simili).

**Allerte di emergenza.** In Italia IT-alert arriva tramite cell broadcast
(`com.android.cellbroadcastreceiver` e simili). Sono tra le `mai`: non spegnerle.

### 3. Le app predefinite si cambiano prima di spegnerle

L'app che oggi fa da Home, Telefono, SMS, browser, assistente o wallet, e la tastiera in uso,
sono `mai` per questo telefono finché restano predefinite. Se vuoi spegnere, per esempio, i
Messaggi Samsung, prima scegli Google Messaggi come app SMS nelle Impostazioni, poi rilancia
`candidates.sh`.

Sui Pixel e su vari telefoni la schermata delle app recenti vive dentro il launcher di
sistema: non spegnerlo anche se usi un altro launcher.

### 4. Le app PERSISTENT non si spengono

Android le riaccende appena il sistema riparte. Il comando dice che ha funzionato, ma dopo
il riavvio sono di nuovo lì, e su alcuni telefoni spegnerle crea problemi:

```
adb shell dumpsys package com.esempio.app | grep -m1 pkgFlags
# pkgFlags=[ SYSTEM HAS_CODE PERSISTENT ... ]
```

`candidates.sh` le segna `mai`.

### 5. Non spegnere l'app che ha salvato il Wi-Fi

Android cancella le reti Wi-Fi salvate da un'app quando la spegni. Di solito le ha salvate il
sistema, ma a volte è un'app di configurazione o di backup:

```
adb shell "dumpsys wifi | grep -o 'cname=[^ ]*' | sort -u"
```

`candidates.sh` le segna `mai`.

### 6. Amministratori, telefoni aziendali e in finanziamento

Le app con permessi di amministratore (Trova dispositivo, gestione aziendale, Knox Guard sui
Samsung in finanziamento) sono `mai`. Su un telefono aziendale gestito, non toccare niente
che riguardi la gestione: lo segnala `info.sh`.

### 7. Notifiche, sveglie e pagamenti sono i primi a rompersi

- Le notifiche push passano da Google Play Services, e sugli Xiaomi anche da
  `com.xiaomi.xmsf`. Sono `mai`.
- Le sveglie stanno nell'app Orologio: è `serve`, ma se la spegni non suonano.
- I pagamenti contactless e molte app bancarie dipendono da Play Services, NFC e dal wallet.
  Dopo ogni gruppo prova un pagamento o almeno apri l'app della banca.

### 8. Un nome di pacchetto non sempre dice cos'è

Prima di spegnere qualcosa che non riconosci, guarda cosa contiene:

```
adb shell dumpsys package <app> | grep -E 'versionName|firstInstallTime'
adb shell cmd package resolve-activity --brief <app>
```

Se resta `dubbio`, lasciala accesa. Un telefono un po' più lento è meglio di un telefono che
non funziona.

## A gruppi, con un riavvio

Spegni 5-10 app, riavvia, e prova: una chiamata, un SMS, i dati mobili, il Wi-Fi, il
Bluetooth, una notifica, la fotocamera, una sveglia, un pagamento. Se va tutto bene passa al
gruppo dopo. Se qualcosa non va sai quale gruppo annullare, invece di indovinare su
quaranta modifiche.

Il riavvio serve: un'app spenta può lasciare processi attivi fino al riavvio, quindi il
telefono è davvero provato solo dopo.

## Se qualcosa va storto

- Riaccendi un'app: `sh undo.sh <app>`
- Riaccendi tutto quello fatto con `disable.sh`: `sh undo.sh`
- Riaccendi qualsiasi cosa spenta o tolta, anche a mano o da altri programmi:
  `sh undo.sh --all`
- **Il telefono si riavvia in continuazione.** Se il debug USB era autorizzato, adb spesso
  risponde per qualche secondo durante l'avvio. Tieni il cavo collegato e lancia
  `sh undo.sh --all`: il comando aspetta il telefono e riaccende tutto.
- Se adb non risponde mai, resta il ripristino di fabbrica dalla recovery. Per questo si va a
  piccoli gruppi e si fa un backup prima di cominciare.

## Dopo un aggiornamento di sistema

Gli aggiornamenti a volte riaccendono app spente. `sh check.sh` lo controlla e
`sh check.sh --fix` le rispegne.

## Elenchi di riferimento

Le liste dentro `lib.sh` sono prudenti e ricavate in buona parte dal livello "consigliato" di
[Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation),
che ha descrizioni e livelli di rischio per migliaia di pacchetti. Se un'app è `dubbio`,
cercala lì prima di decidere.

### Di solito via, se non le usi

| marca | app |
| --- | --- |
| tutte | installer nascosti di Facebook (`com.facebook.appmanager`, `.services`, `.system`), `com.netflix.partner.activation` |
| Google | Google TV, Podcast, News, One, YouTube Music, Play Giochi, Meet (`com.google.android.apps.tachyon`), Feedback |
| Samsung | Bixby (`com.samsung.android.bixby.*`, `visionintelligence`), Samsung Free (`app.spage`), Tips, Game Launcher, AR Zone/Emoji, Samsung TV Plus, Samsung Members |
| Xiaomi | pubblicità e statistiche (`com.miui.msa.global`, `com.miui.analytics`, `com.miui.daemon`), GetApps, Mi Video, Mi Music, Mi Browser, App Vault, carosello sfondi |
| Oppo, Realme, OnePlus | magazine della schermata di blocco (`com.heytap.pictorial`), browser e store HeyTap, Games |

### Mai

| marca | app |
| --- | --- |
| tutte | Play Services, Play Store, Impostazioni, interfaccia di sistema, telefono e telephony, allerte di emergenza, WebView, installatore di pacchetti, permessi, configurazione iniziale |
| Samsung | Knox Guard (`com.samsung.android.kgclient`), servizi IMS (`com.sec.imsservice`), Device care (`com.samsung.android.lool`), configurazione (`com.sec.android.app.SecSetupWizard`) |
| Xiaomi | Sicurezza (`com.miui.securitycenter`), permessi (`com.lbe.security.miui`), notifiche push (`com.xiaomi.xmsf`), Trova dispositivo, account Xiaomi |
| Oppo, Realme, OnePlus | centro sicurezza e permessi (`com.oplus.safecenter`, `com.oplus.securitypermission`), batteria (`com.oplus.battery`) |

I produttori cambiano i nomi a ogni versione. Prendi queste liste come indizi forti, non come
verità.
