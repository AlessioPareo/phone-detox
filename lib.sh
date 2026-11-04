# Funzioni comuni a tutti gli script. Non si lancia da solo: gli altri script lo caricano.
#
# Ogni script accetta, come primo argomento facoltativo, il telefono a cui collegarsi:
#   (niente)             l'unico telefono collegato via USB
#   R58N123ABC           il seriale mostrato da "adb devices"
#   192.168.1.20:41234   l'indirizzo mostrato in Debug wireless
#   192.168.1.20         come sopra, sulla porta classica 5555

# shellcheck disable=SC2034  # le variabili servono agli script che caricano questo file

need_adb() {
  command -v adb >/dev/null 2>&1 && return 0
  echo "Manca adb. Installa i platform-tools di Android:" >&2
  echo "  Mac:     brew install android-platform-tools" >&2
  echo "  Linux:   sudo apt install adb   (o il pacchetto della tua distribuzione)" >&2
  echo "  Windows: https://developer.android.com/tools/releases/platform-tools" >&2
  exit 2
}

# È un indirizzo o un seriale? Un seriale non contiene mai tre punti.
is_target() {
  case "$1" in ""|-*|android) return 1 ;; esac
  # Un indirizzo IP, con o senza porta.
  printf '%s\n' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?$' && return 0
  # Un seriale (USB, emulatore o mDNS): un nome di pacchetto ha sempre un punto e niente trattini.
  case "$1" in *.*) printf '%s\n' "$1" | grep -q '_adb-tls-connect' ; return ;; esac
  [ "${#1}" -ge 6 ]
}

# Imposta PHONE (il seriale per adb -s) e controlla che il telefono risponda.
connect() {
  need_adb
  # Per il soccorso: aspetta il telefono anche se si sta ancora avviando (o si riavvia in loop).
  if [ "$WAIT" = 1 ]; then
    echo "Aspetto il telefono... (collega il cavo; Ctrl+C per smettere)" >&2
    case "$1" in
      "") adb wait-for-device ;;
      *.*.*.*:*) adb connect "$1" >/dev/null 2>&1 || true; adb -s "$1" wait-for-device ;;
      *.*.*.*) adb connect "$1:5555" >/dev/null 2>&1 || true; adb -s "$1:5555" wait-for-device ;;
      *) adb -s "$1" wait-for-device ;;
    esac
  fi
  case "$1" in
    *.*.*.*:*) PHONE=$1 ;;
    *.*.*.*)   PHONE=$1:5555 ;;
    "")
      list=$(adb devices 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2!="" {print $1 " " $2}')
      n=$(printf '%s\n' "$list" | grep -c . || true)
      if [ "$n" = 0 ]; then
        echo "Nessun telefono collegato. Collega il cavo USB con il Debug USB attivo," >&2
        echo "oppure passa l'indirizzo del Debug wireless (es. 192.168.1.20:41234)." >&2
        exit 2
      fi
      if [ "$n" -gt 1 ]; then
        echo "Ci sono più dispositivi collegati. Scegli quale usare come primo argomento:" >&2
        printf '  %s\n' "$list" >&2
        exit 2
      fi
      PHONE=${list%% *} ;;
    *) PHONE=$1 ;;
  esac
  case "$PHONE" in *.*.*.*:*) adb connect "$PHONE" >/dev/null 2>&1 || true ;; esac
  state=$(adb -s "$PHONE" get-state 2>&1 || true)
  case "$state" in
    device) ;;
    *unauthorized*)
      echo "Il telefono chiede \"Consentire il debug USB?\". Tocca Consenti (spunta \"Consenti sempre\") e riprova." >&2
      exit 2 ;;
    *)
      echo "Non riesco a raggiungere $PHONE. È acceso, sbloccato e con il debug attivo?" >&2
      exit 2 ;;
  esac
}

# Lancia un comando sul telefono. Toglie i \r di Windows e non legge lo stdin dello script.
sh_dev() { _rc=0; _out=$(adb -s "$PHONE" shell "$@" </dev/null 2>/dev/null) || _rc=$?; printf '%s\n' "$_out" | tr -d '\r'; return $_rc; }

prop() { sh_dev getprop "$1"; }

# Un nome stabile per questo telefono, per il file locale delle modifiche.
device_id() {
  _maker=$(prop ro.product.manufacturer)
  _model=$(prop ro.product.model)
  _serial=$(prop ro.serialno)
  [ -n "$_serial" ] || _serial=$(adb -s "$PHONE" get-serialno 2>/dev/null | tr -d '\r')
  printf '%s-%s-%s\n' "$_maker" "$_model" "$_serial" | tr -c 'A-Za-z0-9._\n-' '_'
}

# Dove si tiene la lista delle modifiche: sul computer (changes/) e una copia sul telefono.
LOG_DIR=${LOG_DIR:-$(cd "$(dirname "$0")" && pwd)/changes}
PHONE_LOG=/data/local/tmp/phone-detox.txt

log_file() { mkdir -p "$LOG_DIR"; printf '%s/%s.txt\n' "$LOG_DIR" "$(device_id)"; }

# 0 se il pacchetto è installato per l'utente 0, 1 se no.
installed() { sh_dev pm list packages "$1" | grep -Fqx "package:$1"; }
# 0 se è disattivato.
is_off() { sh_dev pm list packages -d "$1" | grep -Fqx "package:$1"; }
# 0 se c'è ancora nel sistema ma è stato tolto per l'utente 0 (pm uninstall --user 0).
is_removed() {
  sh_dev pm list packages -u "$1" | grep -Fqx "package:$1" && ! installed "$1"
}

lost() { echo "Ho perso il collegamento con il telefono mentre leggevo le app. Non ho cambiato niente. Riprova." >&2; exit 2; }

# ---------------------------------------------------------------------------------------------
# Classificazione. Scrive in $1 una riga per app:  verdetto <TAB> stato <TAB> pacchetto <TAB> nome
#
#   mai     serve al telefono per avviarsi, chiamare, ricevere SMS, connettersi o
#           restare sicuro; oppure Android lo tiene sempre acceso. Non toccarla.
#   serve   porta una funzione che potresti usare. Via solo se non la usi.
#   via     di solito si può disattivare: pubblicità, doppioni, app del produttore.
#   dubbio  non so cos'è. Nel dubbio resta accesa.
#   tua     installata da te: si disinstalla normalmente dalle impostazioni.
#
# Stato: on, off (disattivata) o tolta (rimossa per l'utente con pm uninstall --user 0).
# ---------------------------------------------------------------------------------------------

# Ciò che il telefono usa per avviarsi, telefonare, mandare SMS, connettersi e restare sicuro.
NEVER="android com.android.systemui com.android.settings com.android.shell
com.google.android.gms com.google.android.gsf com.android.vending
com.android.phone com.android.server.telecom com.android.providers.telephony com.android.mms.service
com.android.stk com.android.carrierconfig com.android.carrierdefaultapp com.android.ims com.android.ons
com.android.cellbroadcastreceiver com.android.cellbroadcastreceiver.module com.android.cellbroadcastservice
com.google.android.cellbroadcastreceiver com.google.android.cellbroadcastservice com.android.emergency
com.android.providers.settings com.android.providers.contacts com.android.providers.calendar
com.android.providers.media com.android.providers.media.module com.google.android.providers.media.module
com.android.providers.downloads com.android.providers.downloads.ui com.android.providers.blockednumber
com.android.providers.userdictionary com.android.externalstorage com.android.documentsui com.google.android.documentsui
com.android.packageinstaller com.google.android.packageinstaller
com.android.permissioncontroller com.google.android.permissioncontroller
com.android.ext.services com.google.android.ext.services com.android.extservices com.google.android.ext.shared
com.android.bluetooth com.android.nfc com.android.se com.android.keychain com.android.inputdevices
com.android.location.fused com.android.networkstack com.google.android.networkstack
com.android.networkstack.inprocess com.android.networkstack.permissionconfig
com.google.android.networkstack.permissionconfig com.android.networkstack.tethering
com.android.certinstaller com.android.companiondevicemanager com.android.statementservice
com.android.vpndialogs com.android.captiveportallogin com.google.android.captiveportallogin
com.android.wifi.resources com.google.android.wifi.resources com.android.wifi.dialog
com.android.backupconfirm com.android.sharedstoragebackup com.android.localtransport
com.android.proxyhandler com.android.pacprocessor com.android.wallpaperbackup
com.google.android.webview com.android.webview com.google.android.trichromelibrary
com.google.android.setupwizard com.android.provision com.android.managedprovisioning
com.google.android.onetimeinitializer com.google.android.partnersetup
com.google.android.apps.restore com.google.android.modulemetadata com.android.modulemetadata
com.google.android.inputmethod.latin com.android.inputmethod.latin
com.android.launcher3 com.google.android.apps.nexuslauncher com.android.dialer com.android.mms com.android.contacts
com.sec.android.app.launcher com.samsung.android.honeyboard com.sec.android.inputmethod
com.sec.android.app.SecSetupWizard com.samsung.android.app.telephonyui com.samsung.android.incallui
com.samsung.android.dialer com.samsung.android.messaging com.samsung.android.contacts
com.samsung.android.providers.contacts com.sec.imsservice com.sec.ims com.sec.phone com.sec.epdg
com.samsung.android.kgclient com.samsung.android.biometrics.app.setting com.samsung.android.MtpApplication
com.samsung.android.secsoundpicker
com.samsung.android.providers.media com.samsung.android.lool
com.samsung.android.timezone.updater com.sec.android.app.servicemodeapp
com.miui.home com.miui.securitycenter com.miui.securitycore com.miui.securityadd com.lbe.security.miui
com.miui.powerkeeper com.miui.system com.miui.rom com.miui.core com.miui.guardprovider
com.xiaomi.xmsf com.xiaomi.finddevice com.xiaomi.account com.android.thememanager com.miui.miwallpaper
com.miui.securityinputmethod com.android.incallui
com.oplus.safecenter com.coloros.safecenter com.oplus.securitypermission com.coloros.securitypermission
com.oplus.battery com.coloros.oppoguardelf com.android.launcher com.oplus.wirelesssettings
net.oneplus.launcher com.oneplus.security com.oplus.appplatform com.oplus.exsystemservice
com.motorola.launcher3 com.motorola.setup com.motorola.motosignature.app
com.huawei.android.launcher com.huawei.systemmanager com.huawei.hwid"
# Prefissi dei pezzi radio e di sistema del chip: telefonate, rete, sensori.
NEVER_PREFIX="com.qualcomm.qti. com.qti. vendor.qti. org.codeaurora. com.quicinc. com.mediatek. com.unisoc. com.sprd. com.android.cts."

# Portano una funzione. Via solo se non la usi.
KEEP="com.google.android.googlequicksearchbox com.google.android.as com.google.android.as.oss
com.google.android.apps.messaging com.google.android.dialer com.google.android.contacts
com.google.android.calendar com.google.android.deskclock com.google.android.GoogleCamera
com.google.android.apps.photos com.google.android.gm com.google.android.apps.maps
com.google.android.youtube com.android.chrome com.google.android.apps.docs
com.google.android.apps.nbu.files com.google.android.apps.walletnfcrel com.google.android.apps.wellbeing
com.google.android.ims com.google.android.projection.gearhead com.google.android.apps.turbo
com.google.android.apps.safetyhub com.google.android.marvin.talkback com.google.android.tts
com.google.android.apps.accessibility.voiceaccess com.google.android.accessibility.soundamplifier
com.google.android.gms.supervision com.google.android.apps.kids.familylink
com.google.android.syncadapters.contacts com.google.android.syncadapters.calendar
com.google.android.apps.photos.scanner com.google.android.apps.recorder
com.google.android.apps.authenticator2 com.google.android.keep com.google.android.apps.translate
com.google.android.printservice.recommendation com.android.printspooler com.android.bips
com.samsung.android.fmm com.samsung.android.spay com.samsung.android.samsungpass
com.samsung.android.scloud com.samsung.android.mobileservice com.osp.app.signin
com.samsung.android.oneconnect com.samsung.android.app.sharelive com.samsung.android.forest
com.samsung.android.app.routines com.sec.android.gallery3d com.samsung.android.app.notes
com.samsung.android.calendar com.samsung.android.app.reminder com.samsung.android.myfiles
com.sec.android.app.myfiles com.sec.android.app.sbrowser com.samsung.android.knox.containercore
com.samsung.android.app.galaxyfinder com.samsung.android.smartswitchassistant com.sec.android.easyMover
com.samsung.android.app.watchmanager com.samsung.android.wearable.sysui
com.miui.gallery com.miui.notes com.android.calendar com.miui.weather2 com.miui.cleaner
com.miui.screenrecorder com.android.soundrecorder com.miui.compass com.mi.healthglobal
com.coloros.gallery3d com.oneplus.gallery com.coloros.filemanager com.oplus.screenshot
com.motorola.camera3 com.motorola.moto
com.android.camera com.android.camera2 com.sec.android.app.camera com.android.deskclock
com.sec.android.app.clockpackage com.samsung.android.app.smartcapture"

# Di solito si possono disattivare. Elenco prudente, ricavato dalle liste di
# Universal Android Debloater Next Generation (livello "consigliato").
SAFE="com.facebook.appmanager com.facebook.services com.facebook.system
com.netflix.partner.activation com.amazon.appmanager
com.google.android.feedback com.google.android.apps.tachyon com.google.android.videos
com.google.android.apps.podcasts com.google.android.apps.magazines com.google.android.apps.books
com.google.android.music com.google.android.play.games com.google.android.apps.subscriptions.red
com.google.android.apps.youtube.music com.google.android.apps.googleassistant
com.google.android.apps.youtube.kids com.google.android.apps.chromecast.app
com.android.egg com.android.dreams.basic com.android.dreams.phototable com.android.htmlviewer
com.android.wallpaper.livepicker com.android.bookmarkprovider com.android.providers.partnerbookmarks
com.android.printservice.recommendation com.android.hotwordenrollment.okgoogle com.android.hotwordenrollment.xgoogle
com.samsung.android.bixby.agent com.samsung.android.bixby.wakeup com.samsung.android.bixbyvision.framework
com.samsung.android.visionintelligence com.samsung.android.app.spage com.samsung.android.app.settings.bixby
com.samsung.android.app.tips com.samsung.android.game.gamehome com.samsung.android.game.gametools
com.samsung.android.game.gos com.samsung.android.arzone com.samsung.android.aremoji com.samsung.android.aremojieditor
com.samsung.android.ardrawing com.samsung.android.stickercenter com.samsung.android.livestickers
com.samsung.android.tvplus com.samsung.android.voc com.samsung.android.app.watchmanagerstub
com.samsung.android.kidsinstaller com.samsung.android.service.peoplestripe com.sec.android.app.chromecustomizations
com.samsung.android.mateagent com.samsung.android.dkey com.samsung.android.mdx.kit com.samsung.android.smartmirroring
com.samsung.android.app.dressroom com.sec.android.app.kidshome com.samsung.android.ipsgeofence
com.miui.analytics com.miui.msa.global com.miui.daemon com.miui.bugreport com.miui.miservice
com.xiaomi.mipicks com.miui.videoplayer com.miui.player com.mi.globalbrowser com.miui.hybrid
com.xiaomi.glgm com.miui.yellowpage com.mi.android.globalminusscreen com.miui.android.fashiongallery
com.facemoji.lite.xiaomi com.miui.global.packageinstaller.stub com.xiaomi.mipicks.stub
com.heytap.pictorial com.heytap.browser com.oplus.games com.coloros.gamespaceui com.heytap.market
com.oppo.market com.coloros.video com.heytap.music com.oplus.member com.coloros.childrenspace
com.oneplus.brickmode com.oneplus.backuprestore.remoteservice
com.motorola.demo com.motorola.help com.motorola.genie com.motorola.moto.notification
com.huawei.himovie.overseas com.huawei.music com.huawei.android.tips"

# Nomi in italiano semplice, così la lista si legge come una lista di app.
NAMES='android	Sistema Android
com.android.systemui	Interfaccia di sistema (barra, notifiche)
com.android.settings	Impostazioni
com.google.android.gms	Google Play Services
com.google.android.gsf	Servizi Google di base
com.android.vending	Play Store
com.android.phone	Telefono e rete mobile
com.android.server.telecom	Gestione delle chiamate
com.android.providers.telephony	Archivio SMS e rete mobile
com.android.mms.service	Invio MMS
com.android.stk	Menu della SIM
com.android.cellbroadcastreceiver	Allerte di emergenza (IT-alert)
com.android.cellbroadcastreceiver.module	Allerte di emergenza (IT-alert)
com.google.android.cellbroadcastreceiver	Allerte di emergenza (IT-alert)
com.google.android.cellbroadcastservice	Allerte di emergenza (IT-alert)
com.android.cellbroadcastservice	Allerte di emergenza (IT-alert)
com.android.emergency	Informazioni di emergenza
com.android.providers.contacts	Archivio contatti
com.android.providers.media.module	Archivio foto e file
com.google.android.providers.media.module	Archivio foto e file
com.android.bluetooth	Bluetooth
com.android.nfc	NFC e pagamenti contactless
com.google.android.webview	WebView (pagine web dentro le app)
com.google.android.trichromelibrary	Libreria di Chrome e WebView
com.google.android.setupwizard	Configurazione iniziale
com.google.android.inputmethod.latin	Tastiera Gboard
com.samsung.android.honeyboard	Tastiera Samsung
com.sec.android.app.launcher	Schermata Home Samsung
com.samsung.android.dialer	Telefono Samsung
com.samsung.android.messaging	Messaggi Samsung
com.samsung.android.incallui	Schermata di chiamata Samsung
com.google.android.apps.nexuslauncher	Schermata Home Pixel
com.miui.home	Schermata Home Xiaomi
com.samsung.android.kgclient	Knox Guard (blocco finanziamento)
com.miui.securitycenter	Sicurezza Xiaomi (spegnerla può bloccare il telefono al riavvio)
com.xiaomi.xmsf	Notifiche push Xiaomi
com.xiaomi.finddevice	Trova dispositivo Xiaomi
com.samsung.android.fmm	Trova dispositivo Samsung
com.google.android.googlequicksearchbox	App Google e Assistente
com.google.android.as	Android System Intelligence
com.google.android.apps.messaging	Google Messaggi
com.google.android.dialer	Telefono di Google
com.google.android.apps.walletnfcrel	Google Wallet (pagamenti)
com.samsung.android.spay	Samsung Wallet (pagamenti)
com.google.android.ims	Servizi operatore (RCS, VoLTE)
com.google.android.projection.gearhead	Android Auto
com.google.android.apps.turbo	Ottimizzazione batteria
com.google.android.apps.wellbeing	Benessere digitale
com.google.android.marvin.talkback	TalkBack (lettore schermo)
com.google.android.deskclock	Orologio e sveglie
com.sec.android.app.clockpackage	Orologio e sveglie Samsung
com.facebook.appmanager	Installer nascosto di Facebook
com.facebook.services	Servizi nascosti di Facebook
com.facebook.system	Installer nascosto di Facebook
com.netflix.partner.activation	Attivazione Netflix preinstallata
com.google.android.feedback	Feedback Google
com.google.android.apps.tachyon	Google Meet (ex Duo)
com.google.android.videos	Google TV (film)
com.google.android.apps.podcasts	Google Podcast
com.google.android.apps.magazines	Google News
com.google.android.apps.subscriptions.red	Google One
com.google.android.apps.youtube.music	YouTube Music
com.google.android.play.games	Play Giochi
com.android.egg	Easter egg di Android
com.samsung.android.bixby.agent	Bixby
com.samsung.android.bixby.wakeup	Attivazione vocale Bixby
com.samsung.android.visionintelligence	Bixby Vision
com.samsung.android.app.spage	Samsung Free (pagina a sinistra)
com.samsung.android.app.tips	Suggerimenti Samsung
com.samsung.android.game.gamehome	Game Launcher
com.samsung.android.game.gos	Game Optimizing Service
com.samsung.android.arzone	AR Zone
com.samsung.android.aremoji	AR Emoji
com.samsung.android.tvplus	Samsung TV Plus
com.samsung.android.voc	Samsung Members
com.miui.analytics	Statistiche Xiaomi
com.miui.msa.global	Pubblicità di sistema Xiaomi (MSA)
com.miui.daemon	Raccolta dati Xiaomi
com.xiaomi.mipicks	GetApps (store Xiaomi)
com.miui.videoplayer	Mi Video
com.miui.player	Mi Music
com.mi.globalbrowser	Mi Browser
com.mi.android.globalminusscreen	App Vault (pagina a sinistra)
com.miui.android.fashiongallery	Carosello sfondi con pubblicità
com.heytap.pictorial	Magazine della schermata di blocco
com.heytap.browser	Browser Oppo/Realme
com.oplus.games	Games (Oppo/OnePlus)'

# Ruoli di Android: l'app che fa da Home, Telefono, SMS e così via in questo momento.
ROLES="HOME DIALER SMS BROWSER ASSISTANT EMERGENCY WALLET CALL_SCREENING"

classify() {
  _table=$1
  _tmp=$(mktemp -d 2>/dev/null || mktemp -d -t phonedetox)
  dump=$(sh_dev dumpsys package packages) || lost
  printf '%s\n' "$dump" | grep -q 'Package \[' || { dump=$(sh_dev dumpsys package) || lost; }
  printf '%s\n' "$dump" | grep -q 'Package \[' || lost
  sh_dev pm list packages -u > "$_tmp/allraw" || lost
  grep -q '^package:' "$_tmp/allraw" || lost
  sed -n 's/^package://p' "$_tmp/allraw" | sort -u > "$_tmp/all"
  sh_dev pm list packages | sed -n 's/^package://p' | sort -u > "$_tmp/on_user"
  sh_dev pm list packages -d | sed -n 's/^package://p' | sort -u > "$_tmp/off"
  sh_dev pm list packages -3 | sed -n 's/^package://p' | sort -u > "$_tmp/third"

  # Flag di ogni pacchetto in una sola lettura, così resta veloce anche su telefoni lenti.
  printf '%s\n' "$dump" | awk '
    /^[[:space:]]*Package \[/ { n=$0; sub(/.*\[/,"",n); sub(/\].*/,"",n); cur=n; seen=0; next }
    cur!="" && !seen && /pkgFlags=\[/ { l=$0; sub(/.*pkgFlags=\[/,"",l); sub(/\].*/,"",l); print cur "\t" l; seen=1 }
  ' | sort -u > "$_tmp/flags"

  # Protetti per come è configurato questo telefono, non per nome.
  : > "$_tmp/why"
  for r in $ROLES; do
    sh_dev cmd role get-role-holders --user 0 "android.app.role.$r" 2>/dev/null \
      | tr ';' '\n' | grep -E '^[A-Za-z0-9_.]+$' | while read -r p; do
        printf '%s\tmai\tapp predefinita: %s\n' "$p" "$r"
      done >> "$_tmp/why"
  done
  ime=$(sh_dev settings get secure default_input_method 2>/dev/null)
  [ -z "$ime" ] || [ "$ime" = null ] || printf '%s\tmai\ttastiera in uso\n' "${ime%%/*}" >> "$_tmp/why"
  # Amministratori del dispositivo e proprietari: trova dispositivo, lavoro, finanziamenti.
  sh_dev dumpsys device_policy 2>/dev/null | grep -oE 'ComponentInfo\{[A-Za-z0-9_.]+/' \
    | sed 's/ComponentInfo{//; s|/$||' | sort -u | while read -r p; do
      printf '%s\tmai\tamministratore del dispositivo\n' "$p"
    done >> "$_tmp/why"
  # Android cancella le reti Wi-Fi salvate da un'app quando la si disattiva.
  sh_dev "dumpsys wifi | grep -o -E 'cname=[^ ]*'" 2>/dev/null | sed -n 's/^cname=//p' | sort -u \
    | grep -E '^[A-Za-z0-9_.]+$' | while read -r p; do
      printf '%s\tmai\tha salvato una rete Wi-Fi: spegnerla la cancella\n' "$p"
    done >> "$_tmp/why"
  # Servizi di accessibilità accesi: qualcuno li usa.
  acc=$(sh_dev settings get secure enabled_accessibility_services 2>/dev/null)
  printf '%s\n' "$acc" | tr ':' '\n' | grep / | sed 's|/.*||' | sort -u | while read -r p; do
    printf '%s\tserve\tservizio di accessibilità acceso\n' "$p"
  done >> "$_tmp/why"

  printf '%s\n' "$NAMES" > "$_tmp/names"
  _nv=$(printf '%s' "$NEVER" | tr '\n' ' '); _kp=$(printf '%s' "$KEEP" | tr '\n' ' ')
  _sf=$(printf '%s' "$SAFE" | tr '\n' ' ')
  # Una riga sola per lista: l'awk di macOS non accetta a capo dentro -v.
  awk -F'\t' -v never="$_nv" -v keep="$_kp" -v safe="$_sf" -v pre="$NEVER_PREFIX" -v tmp="$_tmp" '
    BEGIN {
      n=split(never,x," "); for (i=1;i<=n;i++) if (x[i]!="") NV[x[i]]=1
      n=split(keep,x," ");  for (i=1;i<=n;i++) if (x[i]!="") KP[x[i]]=1
      n=split(safe,x," ");  for (i=1;i<=n;i++) if (x[i]!="") SF[x[i]]=1
      np=split(pre,PR," ")
      while ((getline l < (tmp "/flags")) > 0)   { split(l,y,"\t"); FL[y[1]]=y[2] }
      while ((getline l < (tmp "/on_user")) > 0) ON[l]=1
      while ((getline l < (tmp "/off")) > 0)     OF[l]=1
      while ((getline l < (tmp "/third")) > 0)   TP[l]=1
      while ((getline l < (tmp "/names")) > 0)   { split(l,y,"\t"); NM[y[1]]=y[2] }
      # Il motivo più forte vince: mai prima di serve.
      while ((getline l < (tmp "/why")) > 0) {
        split(l,y,"\t")
        if (!(y[1] in WV) || y[2]=="mai") { WV[y[1]]=y[2]; WY[y[1]]=y[3] }
      }
      ORD["mai"]=0; ORD["serve"]=1; ORD["via"]=2; ORD["dubbio"]=3; ORD["tua"]=4
      while ((getline p < (tmp "/all")) > 0) {
        st=(p in OF) ? "off" : ((p in ON) ? "on" : "tolta")
        why=""
        pfx=0; for (i=1;i<=np;i++) if (PR[i]!="" && index(p,PR[i])==1) pfx=1
        if (FL[p] ~ /PERSISTENT/)      { v="mai"; why="Android la tiene sempre accesa" }
        else if (p in WV && WV[p]=="mai") { v="mai"; why=WY[p] }
        else if (p in NV || pfx)       v="mai"
        else if (p in WV)              { v=WV[p]; why=WY[p] }
        else if (p in TP)              v="tua"
        else if (p in KP)              v="serve"
        else if (p in SF)              v="via"
        else                           v="dubbio"
        name=(p in NM) ? NM[p] : ""
        if (pfx && name=="") name="Componente del chip: rete, chiamate, sensori"
        if (why!="") name=(name=="" ? "(" why ")" : name " (" why ")")
        printf "%d\t%s\t%s\t%s\t%s\n", ORD[v], v, st, p, name
      }
      exit
    }
  ' | sort -k1,1n -k4,4 | cut -f2- > "$_table"
  rm -rf "$_tmp"
  [ -s "$_table" ] || { echo "Non sono riuscito a ordinare la lista delle app. Non ho cambiato niente." >&2; exit 2; }
}
