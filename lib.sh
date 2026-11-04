# Functions shared by all scripts. Not run on its own: the other scripts source it.
#
# Every script takes, as an optional first argument, the phone to connect to:
#   (nothing)            the only phone connected over USB
#   R58N123ABC           the serial shown by "adb devices"
#   192.168.1.20:41234   the address shown in Wireless debugging
#   192.168.1.20         same, on the classic port 5555

# shellcheck disable=SC2034  # the variables are used by the scripts that source this file

# Message language: PD_LANG=it or en. Without it, from the system: Italian if the computer's
# language is Italian, English otherwise.
if [ -z "$PD_LANG" ]; then
  case "${LC_ALL:-${LC_MESSAGES:-$LANG}}" in it*) PD_LANG=it ;; *) PD_LANG=en ;; esac
fi
[ "$PD_LANG" = it ] || PD_LANG=en
export PD_LANG
# L "italiano" "English": the text in the chosen language, no newline. say: with a newline.
L() { if [ "$PD_LANG" = it ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say() { L "$1" "$2"; echo; }

need_adb() {
  command -v adb >/dev/null 2>&1 && return 0
  say "Manca adb. Installa i platform-tools di Android:" "adb is missing. Install Android's platform-tools:" >&2
  echo "  Mac:     brew install android-platform-tools" >&2
  echo "  Linux:   sudo apt install adb   $(L '(o il pacchetto della tua distribuzione)' '(or your distribution'"'"'s package)')" >&2
  echo "  Windows: https://developer.android.com/tools/releases/platform-tools" >&2
  exit 2
}

# Is it an address or a serial? A serial never has three dots.
is_target() {
  case "$1" in ""|-*|android) return 1 ;; esac
  # An IP address, with or without port.
  printf '%s\n' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?$' && return 0
  # A serial (USB, emulator or mDNS): a package name always has a dot and no dashes.
  case "$1" in *.*) printf '%s\n' "$1" | grep -q '_adb-tls-connect' ; return ;; esac
  [ "${#1}" -ge 6 ]
}

# Sets PHONE (the serial for adb -s) and checks that the phone answers.
connect() {
  need_adb
  # For rescue: wait for the phone even while it's still booting (or boot-looping).
  if [ "$WAIT" = 1 ]; then
    say "Aspetto il telefono... (collega il cavo; Ctrl+C per smettere)" "Waiting for the phone... (plug in the cable; Ctrl+C to stop)" >&2
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
        say "Nessun telefono collegato. Collega il cavo USB con il Debug USB attivo," \
            "No phone connected. Plug in the USB cable with USB debugging on," >&2
        say "oppure passa l'indirizzo del Debug wireless (es. 192.168.1.20:41234)." \
            "or pass the Wireless debugging address (e.g. 192.168.1.20:41234)." >&2
        exit 2
      fi
      if [ "$n" -gt 1 ]; then
        say "Ci sono più dispositivi collegati. Scegli quale usare come primo argomento:" \
            "More than one device is connected. Pass the one to use as the first argument:" >&2
        adb devices -l 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2!="" {m=""; for (i=3;i<=NF;i++) if ($i ~ /^model:/) m=substr($i,7); print "  " $1 "  " $2 "  " m}' >&2
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
      say "Il telefono chiede \"Consentire il debug USB?\". Tocca Consenti (spunta \"Consenti sempre\") e riprova." \
          "The phone asks \"Allow USB debugging?\". Tap Allow (tick \"Always allow\") and try again." >&2
      exit 2 ;;
    *)
      say "Non riesco a raggiungere $PHONE. È acceso, sbloccato e con il debug attivo?" \
          "Can't reach $PHONE. Is it on, unlocked and with debugging enabled?" >&2
      exit 2 ;;
  esac
}

# Runs a command on the phone. Strips Windows \r and doesn't read the script's stdin.
sh_dev() { _rc=0; _out=$(adb -s "$PHONE" shell "$@" </dev/null 2>/dev/null) || _rc=$?; printf '%s\n' "$_out" | tr -d '\r'; return $_rc; }

prop() { sh_dev getprop "$1"; }

# A stable name for this phone, for the local change list.
device_id() {
  _maker=$(prop ro.product.manufacturer)
  _model=$(prop ro.product.model)
  _serial=$(prop ro.serialno)
  [ -n "$_serial" ] || _serial=$(adb -s "$PHONE" get-serialno 2>/dev/null | tr -d '\r')
  printf '%s-%s-%s\n' "$_maker" "$_model" "$_serial" | tr -c 'A-Za-z0-9._\n-' '_'
}

# Where the change list lives: on the computer (changes/) and a copy on the phone.
LOG_DIR=${LOG_DIR:-$(cd "$(dirname "$0")" && pwd)/changes}
PHONE_LOG=/data/local/tmp/phone-detox.txt

log_file() { mkdir -p "$LOG_DIR"; printf '%s/%s.txt\n' "$LOG_DIR" "$(device_id)"; }

# 0 if the package is installed for user 0, 1 otherwise.
installed() { sh_dev pm list packages "$1" | grep -Fqx "package:$1"; }
# 0 if it's disabled.
is_off() { sh_dev pm list packages -d "$1" | grep -Fqx "package:$1"; }
# 0 if it's still in the system but was removed for user 0 (pm uninstall --user 0).
is_removed() {
  sh_dev pm list packages -u "$1" | grep -Fqx "package:$1" && ! installed "$1"
}

# ---------------------------------------------------------------------------------------------
# Identification. Prints KEY=value lines describing the connected phone.
#
# Android has no single place for the marketing name ("Galaxy A54 5G", "Redmi Note 13 Pro"):
# each manufacturer puts it in a different property, or nowhere at all. This tries every
# known one and says how reliable the result is:
#   confirmed   the user confirmed the name (saved with identify.sh --confirm)
#   high        the manufacturer writes the marketing name in a system property
#   medium      taken from the device name, which the user may have changed
#   low         only the model number is known (e.g. SM-A546B): confirm it by hand
# ---------------------------------------------------------------------------------------------

# First non-empty property among the given ones, from the getprop dump already read.
_firstprop() { # file, chiavi...
  _f=$1; shift
  for _k in "$@"; do
    _ke=$(printf '%s' "$_k" | sed 's/\./\\./g')
    _v=$(sed -n "s/^\[$_ke\]: \[\(.*\)\]$/\1/p" "$_f" | head -1)
    case "$_v" in ""|unknown|null) ;; *) printf '%s\n' "$_v"; return 0 ;; esac
  done
  return 1
}

identity_file() {
  mkdir -p "$LOG_DIR"
  _id=$(device_id)
  # Rename the file from its old Italian name.
  [ ! -f "$LOG_DIR/$_id.identita.txt" ] || [ -f "$LOG_DIR/$_id.identity.txt" ] \
    || mv "$LOG_DIR/$_id.identita.txt" "$LOG_DIR/$_id.identity.txt"
  printf '%s/%s.identity.txt\n' "$LOG_DIR" "$_id"
}

identify() {
  _pf=$(mktemp 2>/dev/null || mktemp -t phonedetox)
  sh_dev getprop > "$_pf" || { rm -f "$_pf"; lost; }
  gp() { _firstprop "$_pf" "$@" || true; }

  MAKER=$(gp ro.product.manufacturer ro.product.vendor.manufacturer ro.product.system.manufacturer)
  BRAND=$(gp ro.product.brand ro.product.vendor.brand)
  MODEL=$(gp ro.product.model ro.product.vendor.model ro.product.odm.model ro.product.system.model)
  DEVICE=$(gp ro.product.device ro.product.vendor.device ro.build.product)
  NAME=$(gp ro.product.name ro.product.vendor.name)
  MARKET=$(gp ro.product.marketname ro.product.vendor.marketname ro.product.odm.marketname \
    ro.vendor.oplus.market.name ro.vendor.oplus.market.enname ro.oppo.market.name ro.display.series \
    ro.config.marketing_name ro.vivo.market.name ro.asus.product.mkt_name ro.product.odm.cert.model)
  maker_lc=$(printf '%s' "$MAKER" | tr 'A-Z' 'a-z')
  brand_lc=$(printf '%s' "$BRAND" | tr 'A-Z' 'a-z')

  CONFIDENCE=low; SOURCE=$(L "codice modello" "model number")
  if [ -n "$MARKET" ]; then CONFIDENCE=high; SOURCE=$(L "proprietà del produttore" "manufacturer property")
  elif [ "$maker_lc" = google ]; then MARKET=$MODEL; CONFIDENCE=high; SOURCE=$(L "modello Google" "Google model")
  else
    # The name shown in About phone and over Bluetooth, unless it was changed.
    devname=$(sh_dev settings get global device_name 2>/dev/null)
    case "$devname" in ""|null) ;; *)
      MARKET=$devname; CONFIDENCE=medium; SOURCE=$(L "nome del dispositivo (modificabile dall'utente)" "device name (the user can change it)") ;;
    esac
  fi

  # Family: which rules and advice apply.
  case "$maker_lc $brand_lc" in
    *samsung*) FAMILY=samsung ;;
    *xiaomi*|*redmi*|*poco*) FAMILY=xiaomi ;;
    *oneplus*|*oppo*|*realme*) FAMILY=oplus ;;
    *google*) FAMILY=google ;;
    *motorola*|*lenovo*) FAMILY=motorola ;;
    *huawei*) FAMILY=huawei ;;
    *honor*) FAMILY=honor ;;
    *vivo*|*iqoo*) FAMILY=vivo ;;
    *nothing*) FAMILY=nothing ;;
    *) FAMILY=other ;;
  esac

  # Samsung: the model number gives series and variant even without the name.
  SERIES=
  if [ "$FAMILY" = samsung ]; then
    case "$MODEL" in
      SM-S*) SERIES=$(L "Galaxy S (dal 2022)" "Galaxy S (2022 and later)") ;;
      SM-G*) SERIES=$(L "Galaxy S fino al 2021, o un altro Galaxy" "Galaxy S up to 2021, or another Galaxy") ;;
      SM-A*) SERIES="Galaxy A" ;;
      SM-M*) SERIES="Galaxy M" ;;
      SM-E*) SERIES="Galaxy F" ;;
      SM-F*) SERIES=$(L "Galaxy Z (Fold o Flip)" "Galaxy Z (Fold or Flip)") ;;
      SM-N*) SERIES="Galaxy Note" ;;
      SM-T*|SM-X*|SM-P*) SERIES="Galaxy Tab (tablet)" ;;
      SM-R*) SERIES=$(L "Galaxy Watch o Buds" "Galaxy Watch or Buds") ;;
    esac
    case "$MODEL" in
      *B|*B/DS) SERIES="${SERIES:+$SERIES, }$(L "variante europea/internazionale" "European/international variant")" ;;
      *U|*U1) SERIES="${SERIES:+$SERIES, }$(L "variante USA" "US variant")" ;;
      *F|*F/DS|*FN) SERIES="${SERIES:+$SERIES, }$(L "variante internazionale" "international variant")" ;;
      *N) SERIES="${SERIES:+$SERIES, }$(L "variante coreana" "Korean variant")" ;;
    esac
  fi

  SKIN=
  _oneui=$(gp ro.build.version.oneui)
  [ -z "$_oneui" ] || SKIN="One UI $((_oneui / 10000)).$((_oneui / 100 % 100))"
  _v=$(gp ro.mi.os.version.name); [ -z "$_v" ] || SKIN="HyperOS ${_v#OS}"
  if [ -z "$_v" ]; then _v=$(gp ro.miui.ui.version.name); [ -z "$_v" ] || SKIN="MIUI ${_v#V}"; fi
  _v=$(gp ro.build.version.oplusrom ro.build.version.opporom); [ -z "$_v" ] || SKIN="ColorOS/OxygenOS ${_v#V}"
  _v=$(gp ro.build.version.realmeui); [ -z "$_v" ] || SKIN="realme UI ${_v#V}"
  _v=$(gp ro.vivo.os.version); [ -z "$_v" ] || SKIN="Funtouch/OriginOS $_v"
  _v=$(gp ro.build.version.emui); [ -z "$_v" ] || SKIN="$_v"
  _v=$(gp ro.build.version.magic); [ -z "$_v" ] || SKIN="MagicOS $_v"

  ANDROID=$(gp ro.build.version.release)
  SDK=$(gp ro.build.version.sdk)
  PATCH=$(gp ro.build.version.security_patch)
  BUILD=$(gp ro.build.display.id)
  FINGERPRINT=$(gp ro.build.fingerprint ro.vendor.build.fingerprint)
  REGION=$(gp ro.csc.sales_code ro.product.mod_device ro.miui.region ro.oplus.regionmark ro.vendor.oplus.regionmark ro.product.locale.region)
  SOC=$(printf '%s %s' "$(gp ro.soc.manufacturer)" "$(gp ro.soc.model)" | sed 's/^ *//; s/ *$//')
  [ -n "$SOC" ] || SOC=$(gp ro.hardware.chipname ro.board.platform ro.hardware)
  CARRIER=$(gp gsm.sim.operator.alpha gsm.operator.alpha | tr ',' ' ' | sed 's/ *$//')
  SERIAL=$(gp ro.serialno ro.boot.serialno)
  rm -f "$_pf"
  RAM_MB=$(sh_dev cat /proc/meminfo | sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\) kB/\1/p')
  [ -z "$RAM_MB" ] || RAM_MB=$((RAM_MB / 1024))
  STORAGE=$(sh_dev df -h /data 2>/dev/null | awk -v t="$(L totali total)" -v f="$(L liberi free)" 'NR==2 {print $2 " " t ", " $4 " " f}')

  # A name confirmed by the user wins over everything.
  _idf=$(identity_file)
  if [ -f "$_idf" ]; then
    _conf=$(sed -n -e 's/^CONFIRMED_NAME=//p' -e 's/^NOME_CONFERMATO=//p' "$_idf" | tail -1)
    if [ -n "$_conf" ]; then MARKET=$_conf; CONFIDENCE=confirmed; SOURCE=$(L "confermato dall'utente" "confirmed by the user"); fi
  fi

  # A web search that finds this exact model.
  QUERY="${MARKET:+$MARKET }$MODEL"
  [ "$FAMILY" != xiaomi ] || [ -z "$DEVICE" ] || QUERY="$QUERY $DEVICE"

  for _k in MAKER BRAND MODEL MARKET CONFIDENCE SOURCE SERIES DEVICE NAME FAMILY SKIN ANDROID SDK \
            PATCH BUILD FINGERPRINT REGION SOC RAM_MB STORAGE CARRIER SERIAL QUERY; do
    eval "printf '%s=%s\n' \"\$_k\" \"\$$_k\""
  done
}

lost() { say "Ho perso il collegamento con il telefono mentre leggevo le app. Non ho cambiato niente. Riprova." \
  "Lost the connection to the phone while reading the apps. Nothing was changed. Try again." >&2; exit 2; }

# ---------------------------------------------------------------------------------------------
# Classification. Writes to $1 one tab-separated line per app:
#   verdict  state  package  name_it  name_en  reason_it  reason_en
#
#   never    the phone needs it to boot, call, receive SMS, connect or stay secure; or
#            Android always keeps it on. Don't touch it.
#   useful   provides a feature you might use. Off only if you don't use it.
#   bloat    usually safe to turn off: ads, duplicates, manufacturer apps.
#   unknown  unknown. When in doubt, it stays on.
#   yours    installed by the user: uninstall it normally from Settings.
#
# State: on, off (disabled) or removed (removed for the user with pm uninstall --user 0).
# ---------------------------------------------------------------------------------------------

# What the phone uses to boot, call, send SMS, connect and stay secure.
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
# Prefixes of the chip's radio and system parts: calls, network, sensors.
NEVER_PREFIX="com.qualcomm.qti. com.qti. vendor.qti. org.codeaurora. com.quicinc. com.mediatek. com.unisoc. com.sprd. com.android.cts."

# They provide a feature. Off only if you don't use it.
USEFUL="com.google.android.googlequicksearchbox com.google.android.as com.google.android.as.oss
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

# Usually safe to turn off. A cautious list, derived from the lists of
# Universal Android Debloater Next Generation ("recommended" level).
BLOAT="com.facebook.appmanager com.facebook.services com.facebook.system
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

# Names in plain words, so the list reads like a list of apps: package, Italian, English.
NAMES='android	Sistema Android	Android system
com.android.systemui	Interfaccia di sistema (barra, notifiche)	System interface (status bar, notifications)
com.android.settings	Impostazioni	Settings
com.google.android.gms	Google Play Services	Google Play Services
com.google.android.gsf	Servizi Google di base	Core Google services
com.android.vending	Play Store	Play Store
com.android.phone	Telefono e rete mobile	Phone and mobile network
com.android.server.telecom	Gestione delle chiamate	Call management
com.android.providers.telephony	Archivio SMS e rete mobile	SMS and mobile network storage
com.android.mms.service	Invio MMS	MMS sending
com.android.stk	Menu della SIM	SIM menu
com.android.cellbroadcastreceiver	Allerte di emergenza (IT-alert)	Emergency alerts
com.android.cellbroadcastreceiver.module	Allerte di emergenza (IT-alert)	Emergency alerts
com.google.android.cellbroadcastreceiver	Allerte di emergenza (IT-alert)	Emergency alerts
com.google.android.cellbroadcastservice	Allerte di emergenza (IT-alert)	Emergency alerts
com.android.cellbroadcastservice	Allerte di emergenza (IT-alert)	Emergency alerts
com.android.emergency	Informazioni di emergenza	Emergency information
com.android.providers.contacts	Archivio contatti	Contacts storage
com.android.providers.media.module	Archivio foto e file	Photos and files storage
com.google.android.providers.media.module	Archivio foto e file	Photos and files storage
com.android.bluetooth	Bluetooth	Bluetooth
com.android.nfc	NFC e pagamenti contactless	NFC and contactless payments
com.google.android.webview	WebView (pagine web dentro le app)	WebView (web pages inside apps)
com.google.android.trichromelibrary	Libreria di Chrome e WebView	Chrome and WebView library
com.google.android.setupwizard	Configurazione iniziale	Initial setup
com.google.android.inputmethod.latin	Tastiera Gboard	Gboard keyboard
com.samsung.android.honeyboard	Tastiera Samsung	Samsung keyboard
com.sec.android.app.launcher	Schermata Home Samsung	Samsung home screen
com.samsung.android.dialer	Telefono Samsung	Samsung Phone
com.samsung.android.messaging	Messaggi Samsung	Samsung Messages
com.samsung.android.incallui	Schermata di chiamata Samsung	Samsung call screen
com.google.android.apps.nexuslauncher	Schermata Home Pixel	Pixel home screen
com.miui.home	Schermata Home Xiaomi	Xiaomi home screen
com.samsung.android.kgclient	Knox Guard (blocco finanziamento)	Knox Guard (financing lock)
com.miui.securitycenter	Sicurezza Xiaomi (spegnerla può bloccare il telefono al riavvio)	Xiaomi Security (turning it off can stop the phone from booting)
com.xiaomi.xmsf	Notifiche push Xiaomi	Xiaomi push notifications
com.xiaomi.finddevice	Trova dispositivo Xiaomi	Xiaomi Find device
com.samsung.android.fmm	Trova dispositivo Samsung	Samsung Find My Mobile
com.google.android.googlequicksearchbox	App Google e Assistente	Google app and Assistant
com.google.android.as	Android System Intelligence	Android System Intelligence
com.google.android.apps.messaging	Google Messaggi	Google Messages
com.google.android.dialer	Telefono di Google	Google Phone
com.google.android.apps.walletnfcrel	Google Wallet (pagamenti)	Google Wallet (payments)
com.samsung.android.spay	Samsung Wallet (pagamenti)	Samsung Wallet (payments)
com.google.android.ims	Servizi operatore (RCS, VoLTE)	Carrier services (RCS, VoLTE)
com.google.android.projection.gearhead	Android Auto	Android Auto
com.google.android.apps.turbo	Ottimizzazione batteria	Battery optimisation
com.google.android.apps.wellbeing	Benessere digitale	Digital Wellbeing
com.google.android.marvin.talkback	TalkBack (lettore schermo)	TalkBack (screen reader)
com.google.android.deskclock	Orologio e sveglie	Clock and alarms
com.sec.android.app.clockpackage	Orologio e sveglie Samsung	Samsung Clock and alarms
com.facebook.appmanager	Installer nascosto di Facebook	Hidden Facebook installer
com.facebook.services	Servizi nascosti di Facebook	Hidden Facebook services
com.facebook.system	Installer nascosto di Facebook	Hidden Facebook installer
com.netflix.partner.activation	Attivazione Netflix preinstallata	Preinstalled Netflix activation
com.google.android.feedback	Feedback Google	Google Feedback
com.google.android.apps.tachyon	Google Meet (ex Duo)	Google Meet (formerly Duo)
com.google.android.videos	Google TV (film)	Google TV (movies)
com.google.android.apps.podcasts	Google Podcast	Google Podcasts
com.google.android.apps.magazines	Google News	Google News
com.google.android.apps.subscriptions.red	Google One	Google One
com.google.android.apps.youtube.music	YouTube Music	YouTube Music
com.google.android.play.games	Play Giochi	Play Games
com.android.egg	Easter egg di Android	Android easter egg
com.samsung.android.bixby.agent	Bixby	Bixby
com.samsung.android.bixby.wakeup	Attivazione vocale Bixby	Bixby voice wake-up
com.samsung.android.visionintelligence	Bixby Vision	Bixby Vision
com.samsung.android.app.spage	Samsung Free (pagina a sinistra)	Samsung Free (left page)
com.samsung.android.app.tips	Suggerimenti Samsung	Samsung Tips
com.samsung.android.game.gamehome	Game Launcher	Game Launcher
com.samsung.android.game.gos	Game Optimizing Service	Game Optimizing Service
com.samsung.android.arzone	AR Zone	AR Zone
com.samsung.android.aremoji	AR Emoji	AR Emoji
com.samsung.android.tvplus	Samsung TV Plus	Samsung TV Plus
com.samsung.android.voc	Samsung Members	Samsung Members
com.miui.analytics	Statistiche Xiaomi	Xiaomi analytics
com.miui.msa.global	Pubblicità di sistema Xiaomi (MSA)	Xiaomi system ads (MSA)
com.miui.daemon	Raccolta dati Xiaomi	Xiaomi data collection
com.xiaomi.mipicks	GetApps (store Xiaomi)	GetApps (Xiaomi store)
com.miui.videoplayer	Mi Video	Mi Video
com.miui.player	Mi Music	Mi Music
com.mi.globalbrowser	Mi Browser	Mi Browser
com.mi.android.globalminusscreen	App Vault (pagina a sinistra)	App Vault (left page)
com.miui.android.fashiongallery	Carosello sfondi con pubblicità	Wallpaper carousel with ads
com.miui.bugreport	Segnalazione errori Xiaomi	Xiaomi bug reports
com.miui.miservice	Servizi e feedback Xiaomi	Xiaomi Services and feedback
com.miui.yellowpage	Pagine gialle Xiaomi (nome delle aziende che chiamano)	Xiaomi Yellow Pages (names of businesses calling you)
com.xiaomi.glgm	Giochi Xiaomi	Xiaomi Games
com.miui.cleaner	Pulizia Xiaomi	Xiaomi Cleaner
com.miui.gallery	Galleria Xiaomi	Xiaomi Gallery
com.miui.notes	Note Xiaomi	Xiaomi Notes
com.miui.weather2	Meteo Xiaomi	Xiaomi Weather
com.miui.calculator	Calcolatrice Xiaomi	Xiaomi Calculator
com.miui.screenrecorder	Registrazione schermo Xiaomi	Xiaomi Screen recorder
com.android.soundrecorder	Registratore	Sound recorder
com.xiaomi.midrop	ShareMe (Xiaomi)	ShareMe (Xiaomi)
cn.wps.xiaomi.abroad.lite	WPS Office (preinstallato Xiaomi)	WPS Office (preinstalled by Xiaomi)
com.amazon.appmanager	Installer nascosto di Amazon	Hidden Amazon installer
com.android.dreams.basic	Salvaschermo base	Basic screen saver
com.android.dreams.phototable	Salvaschermo con le foto	Photo screen saver
com.android.wallpaper.livepicker	Sfondi animati	Live wallpapers
com.android.bookmarkprovider	Segnalibri del vecchio browser	Old browser bookmarks
com.android.providers.partnerbookmarks	Segnalibri del produttore	Manufacturer bookmarks
com.android.htmlviewer	Visualizzatore di pagine HTML	HTML page viewer
com.android.hotwordenrollment.okgoogle	"Ok Google" con la voce	"Ok Google" by voice
com.android.hotwordenrollment.xgoogle	"Ok Google" con la voce	"Ok Google" by voice
com.google.android.apps.googleassistant	Assistente Google (scorciatoia)	Google Assistant (shortcut)
com.android.printspooler	Stampa	Printing
com.android.bips	Stampa (stampanti di rete)	Printing (network printers)
com.google.android.printservice.recommendation	Stampa (suggerimenti di plugin)	Printing (plugin suggestions)
com.android.camera	Fotocamera	Camera
com.android.deskclock	Orologio e sveglie	Clock and alarms
com.google.android.apps.maps	Google Maps	Google Maps
com.google.android.gm	Gmail	Gmail
com.google.android.calendar	Google Calendar	Google Calendar
com.google.android.contacts	Contatti Google	Google Contacts
com.google.android.youtube	YouTube	YouTube
com.google.android.tts	Sintesi vocale Google	Google text-to-speech
com.android.chrome	Chrome	Chrome
com.heytap.pictorial	Magazine della schermata di blocco	Lock screen magazine
com.heytap.browser	Browser Oppo/Realme	Oppo/Realme browser
com.oplus.games	Games (Oppo/OnePlus)	Games (Oppo/OnePlus)'

# Android roles: the app currently acting as Home, Phone, SMS and so on.
ROLES="HOME DIALER SMS BROWSER ASSISTANT EMERGENCY WALLET CALL_SCREENING"

# The name of a table row in the chosen language, with the reason in brackets.
# Usage: row_name "<row>"
row_name() {
  printf '%s\n' "$1" | awk -F'\t' -v it="$([ "$PD_LANG" = it ] && echo 1)" '{
    n = it ? $4 : $5; w = it ? $6 : $7
    if (n == "") n = $4
    if (w != "") n = (n == "" ? "(" w ")" : n " (" w ")")
    print n }'
}

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

  # Flags of every package in one read, so it stays fast on slow phones too.
  printf '%s\n' "$dump" | awk '
    /^[[:space:]]*Package \[/ { n=$0; sub(/.*\[/,"",n); sub(/\].*/,"",n); cur=n; seen=0; next }
    cur!="" && !seen && /pkgFlags=\[/ { l=$0; sub(/.*pkgFlags=\[/,"",l); sub(/\].*/,"",l); print cur "\t" l; seen=1 }
  ' | sort -u > "$_tmp/flags"

  # Protected because of how this phone is set up, not by name.
  : > "$_tmp/why"
  for r in $ROLES; do
    sh_dev cmd role get-role-holders --user 0 "android.app.role.$r" 2>/dev/null \
      | tr ';' '\n' | grep -E '^[A-Za-z0-9_.]+$' | while read -r p; do
        printf '%s\tnever\tapp predefinita: %s\tdefault app: %s\n' "$p" "$r" "$r"
      done >> "$_tmp/why"
  done
  ime=$(sh_dev settings get secure default_input_method 2>/dev/null)
  [ -z "$ime" ] || [ "$ime" = null ] || printf '%s\tnever\ttastiera in uso\tkeyboard in use\n' "${ime%%/*}" >> "$_tmp/why"
  # Device administrators and owners: find my device, work, financing.
  sh_dev dumpsys device_policy 2>/dev/null | grep -oE 'ComponentInfo\{[A-Za-z0-9_.]+/' \
    | sed 's/ComponentInfo{//; s|/$||' | sort -u | while read -r p; do
      printf '%s\tnever\tamministratore del dispositivo\tdevice administrator\n' "$p"
    done >> "$_tmp/why"
  # Android deletes the Wi-Fi networks saved by an app when it's disabled.
  sh_dev "dumpsys wifi | grep -o -E 'cname=[^ ]*'" 2>/dev/null | sed -n 's/^cname=//p' | sort -u \
    | grep -E '^[A-Za-z0-9_.]+$' | while read -r p; do
      printf '%s\tnever\tha salvato una rete Wi-Fi: spegnerla la cancella\tit saved a Wi-Fi network: turning it off deletes it\n' "$p"
    done >> "$_tmp/why"
  # Accessibility services turned on: someone uses them.
  acc=$(sh_dev settings get secure enabled_accessibility_services 2>/dev/null)
  printf '%s\n' "$acc" | tr ':' '\n' | grep / | sed 's|/.*||' | sort -u | while read -r p; do
    printf '%s\tuseful\tservizio di accessibilità acceso\taccessibility service in use\n' "$p"
  done >> "$_tmp/why"

  printf '%s\n' "$NAMES" > "$_tmp/names"
  _nv=$(printf '%s' "$NEVER" | tr '\n' ' '); _kp=$(printf '%s' "$USEFUL" | tr '\n' ' ')
  _sf=$(printf '%s' "$BLOAT" | tr '\n' ' ')
  # One line per list: macOS awk doesn't accept newlines inside -v.
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
      while ((getline l < (tmp "/names")) > 0)   { split(l,y,"\t"); NI[y[1]]=y[2]; NE[y[1]]=y[3] }
      # The strongest reason wins: never before useful.
      while ((getline l < (tmp "/why")) > 0) {
        split(l,y,"\t")
        if (!(y[1] in WV) || y[2]=="never") { WV[y[1]]=y[2]; WI[y[1]]=y[3]; WE[y[1]]=y[4] }
      }
      ORD["never"]=0; ORD["useful"]=1; ORD["bloat"]=2; ORD["unknown"]=3; ORD["yours"]=4
      while ((getline p < (tmp "/all")) > 0) {
        st=(p in OF) ? "off" : ((p in ON) ? "on" : "removed")
        wi=""; we=""
        pfx=0; for (i=1;i<=np;i++) if (PR[i]!="" && index(p,PR[i])==1) pfx=1
        if (FL[p] ~ /PERSISTENT/)      { v="never"; wi="Android la tiene sempre accesa"; we="Android always keeps it on" }
        else if (p in WV && WV[p]=="never") { v="never"; wi=WI[p]; we=WE[p] }
        else if (p in NV || pfx)       v="never"
        else if (p in WV)              { v=WV[p]; wi=WI[p]; we=WE[p] }
        else if (p in TP)              v="yours"
        else if (p in KP)              v="useful"
        else if (p in SF)              v="bloat"
        else                           v="unknown"
        ni=(p in NI) ? NI[p] : ""; ne=(p in NE) ? NE[p] : ""
        if (pfx && ni=="") { ni="Componente del chip: rete, chiamate, sensori"; ne="Chip component: network, calls, sensors" }
        printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ORD[v], v, st, p, ni, ne, wi, we
      }
      exit
    }
  ' | sort -k1,1n -k4,4 | cut -f2- > "$_table"
  rm -rf "$_tmp"
  [ -s "$_table" ] || { say "Non sono riuscito a ordinare la lista delle app. Non ho cambiato niente." \
    "Couldn't sort the app list. Nothing was changed." >&2; exit 2; }
}
