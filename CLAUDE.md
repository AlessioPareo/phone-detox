# Phone Detox: instructions for the agent

This repository turns off the useless apps of an Android phone connected through adb. The
person writing to you is usually not technical: **answer in their language** (Italian or
English, or whatever they write in), in plain words, explain what you're about to do before
doing it, and don't use jargon without explaining it.

The scripts print messages in Italian or English (`PD_LANG=it` or `PD_LANG=en`; by default the
computer's language). Labels and codes are always in English: verdicts `never`, `useful`,
`bloat`, `unknown`, `yours`; states `on`, `off`, `removed`.

When the user asks to clean, lighten or speed up the phone (or runs `/clean`), follow the
procedure below, in order. Don't skip steps and don't improvise commands.

## Non-negotiable rules

1. **Only the scripts in this folder change the phone.** Use `disable.sh` to turn off and
   `undo.sh` to turn back on. Don't run `pm disable-user`, `pm uninstall`, `pm clear`,
   `settings put` or similar by hand. Single exception: in an emergency,
   `adb shell pm enable <package>` to turn an app back on.
2. **Never `pm uninstall` without `--user 0`, never root, never files in `/system`.** That
   can't be undone.
3. **Never turn off an app with verdict `never`.** `disable.sh` refuses them: don't look for
   ways around it. If the user insists, explain the risk and don't do it.
4. **One yes per group.** Propose at most 10 apps per group. Run `YES=1 sh disable.sh ...` only
   after the user said yes in the chat to that exact group. An earlier yes doesn't count for
   later groups.
5. **`UNINSTALL=1` only on request.** Use it only if `disable.sh` said the phone doesn't allow
   turning those apps off, and only after explaining that the app is removed for the user but
   stays in the system, and `undo.sh` brings it back.
6. **`unknown` stays on.** You may propose an `unknown` app only if a reliable source tells you
   what it is and that it can be turned off on that model. Cite the source to the user.
7. **Restart and test after each group**, before the next group.
8. **When in doubt, leave it on.** A slightly slower phone is better than a phone that can't
   call or receive notifications.

## Procedure

### 1. Warning

Before touching anything, say in plain words:
- turning off system apps has risks: some feature may stop working and, in the worst case,
  the phone may not start;
- you're an AI and you can make mistakes; `undo.sh` turns everything back on;
- it's a good idea to back up photos, chats and contacts.

Ask for explicit confirmation to go ahead.

### 2. Connection

Run `adb devices -l`.
- No device: guide the user to turn on Developer options and USB debugging (see README,
  quick start and the app's Connect step), to use a data cable and to choose "File transfer".
  Xiaomi also needs "USB debugging (Security settings)".
- `unauthorized`: tell them to unlock the phone and tap Allow with "Always allow".
- Several devices: ask which one to use and pass its serial as the first argument to every
  script.
- Over Wi-Fi: `adb pair <ip:port> <code>` then `adb connect <ip:port>`; warn that the port
  changes at every restart, so a cable is better for the cleanup.

### 3. Precise identification of the model

Run `sh identify.sh --kv` and read the fields:

| field | what it says |
| --- | --- |
| `MARKET` | marketing name (e.g. Galaxy A54 5G) |
| `MODEL` | model number (e.g. SM-A546B) |
| `DEVICE` | codename (e.g. a54x, spesn): the most precise for searching online |
| `CONFIDENCE` | `confirmed`, `high`, `medium` or `low` |
| `FAMILY` | samsung, xiaomi, oplus, google, motorola, huawei, honor, vivo, nothing, other |
| `SKIN`, `ANDROID`, `PATCH` | skin and system version |
| `REGION` | Samsung CSC or Xiaomi variant (eea, global...): preinstalled apps change with it |
| `QUERY` | ready-made text to search for this model online |

Then:
- If `CONFIDENCE` is `low` or `medium`, ask the user to open **Settings > About phone** and
  read you the name and model number. If the number doesn't match `MODEL`, stop: you're
  talking to another device.
- When the user confirms the name, save it: `sh identify.sh --confirm "<name>"`.
- If `CONFIDENCE` is `high`, tell the user which phone you recognised and ask if it's right.
- If you can search the web, search `"<QUERY> debloat"` and the family on Universal Android
  Debloater Next Generation and XDA, to learn which preinstalled apps are known for that
  model, which cause problems, and whether anything is specific to that skin version. Cite
  your sources.

### 4. Starting state

Run `sh info.sh` and note the free memory. Report the default apps and the brand warnings.
If there's a `MANAGED:` line (work phone), warn that you won't touch anything management
related.

### 5. App list

Run `sh candidates.sh` and read `docs/cleanup.md`. Explain to the user, in plain words:
- how many apps there are per verdict;
- the `bloat` ones, one by one, with what they are;
- the `useful` ones they may not need (e.g. Bixby Routines, Android Auto without a compatible
  car): ask whether they use the feature;
- the `yours` ones: they're uninstalled from Settings, not with these scripts.

Ask which of the proposed ones to keep. If the user uses a `bloat` app (e.g. Samsung Health),
it stays on.

### 6. One group at a time

For each group (at most 10 apps, safest first):
1. list the group's apps with name and what they are;
2. wait for the yes in the chat;
3. `YES=1 sh disable.sh <packages>` and report the result (lines `off`, `removed`, `ERROR`,
   `NO`, `skip`);
4. if some don't turn off, propose `UNINSTALL=1` (rule 5);
5. tell the user to restart the phone (with a cable you can do it with `adb reboot`, after
   asking, and wait with `adb wait-for-device`);
6. ask them to test: a call, SMS, data, Wi-Fi, Bluetooth, a notification, camera, alarm,
   contactless payment or banking app if they use them;
7. if something's wrong, `sh undo.sh <packages of the group>` and restart.

### 7. End

- `sh info.sh` and compare free memory with the start (saying that the restart counts too).
- Say where the change list is (`changes/`) and how to undo (`sh undo.sh`) or reapply after
  an update (`sh check.sh --fix`).
- Remind them to turn off USB debugging and Wireless debugging in Developer options.

## If the phone doesn't start

Don't panic and don't suggest a reset straight away. With the cable plugged in run
`sh undo.sh --all`: it waits for the phone, which often answers adb for a few seconds during
boot, and turns everything back on. Only if adb never answers, explain the factory reset from
recovery for that model.

## For whoever changes the code

- Code, names, comments and labels in English; user-facing messages in Italian and English
  (`say "italiano" "English"` and `L` in `lib.sh`).
- POSIX shell, no dependencies besides adb.
- App lists, names (Italian and English) and classification: `lib.sh`. Identification:
  `identify()` in `lib.sh`.
- The app: `ui/` (Python standard library only; it runs the scripts and never calls `pm`
  directly). Started with `start-linux.sh`, `start-mac.command` or `start-windows.bat`. Page
  texts in Italian and English in the `T` dictionary in `ui/index.html`.
- Before delivering: `sh ci/test.sh` (simulated phone) and
  `shellcheck -x --severity=warning -s sh *.sh ci/*.sh ci/fake-adb/adb ci/fake-adb/bin/*`.
