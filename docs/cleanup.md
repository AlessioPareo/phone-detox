# Cleaning a phone without breaking it

**English** · [Italiano](pulizia.md)

Turning off useless apps is an app-by-app choice, so it isn't automatic. This page collects
the rules that keep it safe and reversible. The app follows them for you; they're here for
anyone who wants to know why, or who uses the scripts directly.

Start from `sh candidates.sh` (or the **Apps** step in the app). It lists every app on the
phone with a verdict and changes nothing:

| verdict | in the app | meaning |
| --- | --- | --- |
| `never` | System | the phone needs it (boot, calls, SMS, network, security) or Android always keeps it on. |
| `useful` | You may need | provides a feature you might use. Off only if you don't use it. |
| `bloat` | Recommended | usually safe to turn off: ads, duplicates, manufacturer apps. |
| `unknown` | Unknown | unknown. Stays on until you know what it is. |
| `yours` | Yours | you installed it: uninstall it normally from Settings. |

Then turn apps off in groups with `sh disable.sh <app> <app> ...`, restart and test the phone.

## The rules

### 1. Turn off, don't delete

`pm disable-user --user 0 <app>` turns an app off and `pm enable <app>` turns it back on.
That's what `disable.sh` does.

Some phones (many recent Samsung, ColorOS, OxygenOS) don't let adb turn off certain system
apps. In that case `UNINSTALL=1` uses `pm uninstall -k --user 0`: the app disappears for you
but the file stays in the system, and `undo.sh` brings it back with
`cmd package install-existing`, without a reset. Never use `pm uninstall` without `--user 0`,
nor tools that delete files from `/system`: that can't be undone.

### 2. Don't touch what makes a phone work

Boot, home screen, keyboard, Settings, calls, SMS, mobile network, Wi-Fi, Bluetooth, NFC, app
installation, initial setup. If you turn one of them off you may end up with a phone that
doesn't start or can't call, and adb is the only way back. `candidates.sh` marks them `never`,
including the chip components (`com.qualcomm.qti.*`, `com.mediatek.*` and similar).

**Emergency alerts.** Public alerts (IT-alert in Italy, EU-Alert, Wireless Emergency Alerts)
arrive through cell broadcast (`com.android.cellbroadcastreceiver` and similar). They're
`never`: never turn them off.

### 3. Change default apps before turning them off

The app that is currently Home, Phone, SMS, browser, assistant or wallet, and the keyboard in
use, are `never` for this phone as long as they're the default. If you want to turn off, say,
Samsung Messages, first pick Google Messages as the SMS app in Settings, then run
`candidates.sh` again.

On Pixels and several other phones the recent apps screen lives inside the system launcher:
don't turn it off even if you use another launcher.

### 4. PERSISTENT apps can't be turned off

Android turns them back on as soon as the system restarts. The command says it worked, but
after a reboot they're back, and on some phones turning them off causes problems:

```
adb shell dumpsys package com.example.app | grep -m1 pkgFlags
# pkgFlags=[ SYSTEM HAS_CODE PERSISTENT ... ]
```

`candidates.sh` marks them `never`.

### 5. Don't turn off the app that saved the Wi-Fi

Android deletes the Wi-Fi networks saved by an app when you turn it off. Usually the system
saved them, but sometimes it's a setup or backup app:

```
adb shell "dumpsys wifi | grep -o 'cname=[^ ]*' | sort -u"
```

`candidates.sh` marks them `never`.

### 6. Administrators, work phones and financed phones

Apps with administrator rights (Find my device, work management, Knox Guard on financed
Samsung phones) are `never`. On a managed work phone, don't touch anything related to
management: `info.sh` and the app tell you.

### 7. Notifications, alarms and payments break first

- Push notifications go through Google Play Services, and on Xiaomi also through
  `com.xiaomi.xmsf`. They're `never`.
- Alarms live in the Clock app: it's `useful`, but if you turn it off they won't ring.
- Contactless payments and many banking apps depend on Play Services, NFC and the wallet.
  After each group try a payment or at least open your banking app.

### 8. A package name doesn't always say what it is

Before turning off something you don't recognise, look at what it contains:

```
adb shell dumpsys package <app> | grep -E 'versionName|firstInstallTime'
adb shell cmd package resolve-activity --brief <app>
```

If it stays `unknown`, leave it on. A slightly slower phone is better than a phone that
doesn't work.

## In groups, with a restart

Turn off 5-10 apps, restart, and test: a call, an SMS, mobile data, Wi-Fi, Bluetooth, a
notification, the camera, an alarm, a payment. If everything works, move on to the next
group. If something breaks, you know which group to undo instead of guessing among forty
changes.

The restart matters: a turned-off app can leave processes running until the reboot, so the
phone is only really tested afterwards.

## If something goes wrong

- Turn one app back on: `sh undo.sh <app>`
- Turn back on everything done with `disable.sh`: `sh undo.sh`
- Turn back on anything that's off or removed, even by hand or by other programs:
  `sh undo.sh --all`
- **The phone keeps restarting.** If USB debugging was allowed, adb often answers for a few
  seconds during boot. Keep the cable plugged in and run `sh undo.sh --all`: the command
  waits for the phone and turns everything back on.
- If adb never answers, the last resort is a factory reset from recovery. That's why you go
  in small groups and back up before you start.

## After a system update

Updates sometimes turn disabled apps back on. `sh check.sh` checks, and `sh check.sh --fix`
turns them off again (in the app: **Check** on the Done page).

## Reference lists

The lists in `lib.sh` are cautious and largely derived from the "recommended" level of
[Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation),
which has descriptions and risk levels for thousands of packages. If an app is `unknown`, look
it up there before deciding.

### Usually safe to turn off, if you don't use them

| brand | apps |
| --- | --- |
| all | hidden Facebook installers (`com.facebook.appmanager`, `.services`, `.system`), `com.netflix.partner.activation` |
| Google | Google TV, Podcasts, News, One, YouTube Music, Play Games, Meet (`com.google.android.apps.tachyon`), Feedback |
| Samsung | Bixby (`com.samsung.android.bixby.*`, `visionintelligence`), Samsung Free (`app.spage`), Tips, Game Launcher, AR Zone/Emoji, Samsung TV Plus, Samsung Members |
| Xiaomi | ads and analytics (`com.miui.msa.global`, `com.miui.analytics`, `com.miui.daemon`), GetApps, Mi Video, Mi Music, Mi Browser, App Vault, wallpaper carousel |
| Oppo, Realme, OnePlus | lock screen magazine (`com.heytap.pictorial`), HeyTap browser and store, Games |

### Never

| brand | apps |
| --- | --- |
| all | Play Services, Play Store, Settings, system UI, phone and telephony, emergency alerts, WebView, package installer, permissions, initial setup |
| Samsung | Knox Guard (`com.samsung.android.kgclient`), IMS services (`com.sec.imsservice`), Device care (`com.samsung.android.lool`), setup (`com.sec.android.app.SecSetupWizard`) |
| Xiaomi | Security (`com.miui.securitycenter`), permissions (`com.lbe.security.miui`), push notifications (`com.xiaomi.xmsf`), Find device, Xiaomi account |
| Oppo, Realme, OnePlus | security and permissions center (`com.oplus.safecenter`, `com.oplus.securitypermission`), battery (`com.oplus.battery`) |

Manufacturers change names with every version. Take these lists as strong hints, not as the
truth.
