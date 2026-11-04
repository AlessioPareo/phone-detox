# Phone Detox

**English** · [Italiano](README.it.md)

### Clean up an Android phone, without root and without deleting anything.

A fork of [tv-detox](https://github.com/Ansub/tv-detox) by Ansub Khan, rebuilt for phones
only. It turns off preinstalled junk (ads, hidden installers, manufacturer duplicates) with
safety rules made for a phone: calls, SMS, notifications, payments and emergency alerts are
protected.

| **🧹 Turns off the junk**<br>Manufacturer bloatware, system ads, duplicates. | **🛡️ Protects the essentials**<br>Refuses to turn off what the phone needs and your default apps. | **↩️ Always reversible**<br>Apps are turned off, not deleted. One button turns them back on. |
| --- | --- | --- |

> [!WARNING]
> **At your own risk.** Turning off system apps can break features or, in the worst case,
> stop the phone from booting. Phone Detox refuses the known dangerous apps and asks before
> every change, but it can't know every phone. Back up first and go in small groups.
> Everything can be turned back on.

## Quick start (no technical knowledge needed)

**1. Download Phone Detox.** At the top of this page click **Code → Download ZIP**, then
unzip it (on Windows: right-click → Extract all).

**2. Install what's missing** (only once):

| | what you need |
| --- | --- |
| **Windows** | [Python](https://www.python.org/downloads/) (during setup tick **"Add python.exe to PATH"**) and [Git for Windows](https://git-scm.com/download/win) (keep the default options) |
| **Mac** | nothing: if Python is missing, the Mac offers to install it the first time |
| **Linux** | nothing on most distributions (Python 3 is already there) |

You don't need to install adb, the program that talks to the phone: the app downloads it
from Google for you.

**3. Open the app** from the Phone Detox folder:

| | how |
| --- | --- |
| **Windows** | double-click `start-windows.bat` |
| **Mac** | double-click `start-mac.command` (the first time: right-click → **Open**) |
| **Linux** | open a terminal in the folder and type `sh start-linux.sh` |

A small window stays open (keep it open) and the app opens in your browser, in English or
Italian.

**4. Follow the steps on the page.** It guides you through everything:

1. **Before you start**: what can go wrong and a reminder to back up.
2. **Connect**: how to turn on USB debugging on the phone (with instructions for Samsung,
   Xiaomi, OnePlus and others). The page notices the phone by itself, and tells you what to
   do if it asks for permission. Wi-Fi works too.
3. **Your phone**: the exact model, which you confirm by looking at Settings → About phone.
4. **Apps**: every app on the phone in plain words, sorted into *Recommended*, *You may need*,
   *Yours*, *Unknown*, *System*. Tick up to 10, or press **Choose the safest for me**.
   Then restart the phone and test it with a checklist. If something's wrong, one button
   turns the group back on.
5. **Done**: free memory before and after, and a reminder to turn USB debugging off.

If you close the app halfway, it picks up from where you were.

## Other ways to use it

### With Claude Code

Download this repository, open [Claude Code](https://claude.com/claude-code) in its folder
and type `/pulisci`. Claude reads [CLAUDE.md](CLAUDE.md), which has the procedure and the
rules. It warns you about the risks, identifies the model, looks up the apps known for that
phone, proposes groups of apps and waits for your yes on each one. There's also
`/identifica` (identify) and `/annulla` (undo). [PROMPT.md](PROMPT.md) has the full prompt
for Codex, Gemini CLI or Cursor.

Claude in the claude.ai chat can't do this: it runs on Anthropic's servers and can't see your
phone. You need something that runs on your computer.

### In the terminal

The scripts need a POSIX `sh` and `adb` (Mac: `brew install android-platform-tools`; Linux:
`sudo apt install adb`; Windows: Git Bash plus the
[SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)). Their
messages are in Italian.

```
sh guida.sh                    # guided wizard: asks questions, does everything
sh identify.sh                 # which phone it is, and how sure
sh info.sh                     # free memory, default apps, brand warnings
sh candidates.sh               # every app with a verdict (changes nothing)
sh disable.sh <app> <app> ...  # turns off, asking for confirmation
sh undo.sh                     # turns back on everything you turned off
sh check.sh --fix              # after a system update, turns off what came back
```

With several devices connected, or over Wi-Fi, put the phone first:
`sh candidates.sh 192.168.1.20:41234` or `sh candidates.sh R58N123ABC` (the serial from
`adb devices`).

## How the apps are sorted

| in the app | in the scripts | meaning |
| --- | --- | --- |
| System | `mai` | The phone needs it, or it's a default app, the keyboard in use, a device administrator, or it saved a Wi-Fi network, or Android always keeps it on. **Refused.** |
| You may need | `serve` | A feature you might use: alarms, payments, Android Auto, accessibility… Off only if you don't use it. |
| Recommended | `via` | Usually safe to turn off. |
| Unknown | `dubbio` | Unknown: stays on unless you know what it is (expert mode). |
| Yours | `tua` | You installed it: uninstall it from Settings if you don't need it. |

[docs/cleanup.md](docs/cleanup.md) explains the rules behind the verdicts and what to test
after each group.

Each phone is identified precisely (brand, model number, variant, system version), because
manufacturers preinstall different apps on different variants of the same model. When the
name isn't certain, you confirm it from Settings → About phone.

## Turning things back on

In the app: the **Turn on** button next to each app, **Something's wrong** after a group, or
the buttons on the Done page. In the terminal:

```
sh undo.sh                        # everything turned off with Phone Detox
sh undo.sh com.example.app        # just this one
sh undo.sh --all                  # rescue: every app that's off or removed, by anyone
```

**Phone stuck restarting?** If USB debugging was allowed, adb often answers for a few seconds
during boot. Plug in the cable and run `sh undo.sh --all`: it waits for the phone and turns
everything back on. If adb never answers, the last resort is a factory reset from recovery.

## FAQ

**Do I need root?** No. Everything goes through adb and applies to the main user. The system
partition is never touched, and a factory reset brings the phone back as it was.

**Will the phone be faster?** On cheap or old phones with lots of bloatware, usually yes:
fewer background apps, more free memory and fewer advertising notifications. On a Pixel
there's little to remove. The app shows free memory before and after.

**Why not use Universal Android Debloater?**
[UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation)
is excellent and has much larger lists. Phone Detox is smaller and more guided. It has
protections tied to your phone: default apps, keyboard in use, administrators, whoever saved
the Wi-Fi, PERSISTENT apps. It makes you test after each group, and keeps a list to undo
changes and to reapply them after updates.

**An update turned something back on.** Open the app and press **Check** on the Done page, or
run `sh check.sh --fix`.

**Banking apps and payments.** Never turn off Play Services, NFC, the wallet or carrier
services. After each group, open your banking app and, if you use it, try a payment.

**Work or financed phone.** Leave management apps and device administrators alone. The app
tells you if the phone is managed.

**Turn off debugging when you're done.** With USB or wireless debugging on, an authorised
computer can control the phone. Turn it on only when you need it.

**Is the app safe to run?** It's a small Python server that listens only on your computer
(127.0.0.1), rejects requests without a random token and runs only the scripts in this
folder. The only download is adb, from Google's official address.

## For developers

The scripts are POSIX shell with no dependencies besides `adb`. App lists (`mai`, `serve`,
`via`) and Italian names live in `lib.sh`; English names in `ui/app_names_en.json`.

```
sh ci/test.sh       # tests every script and the app on a simulated phone
shellcheck -x -s sh *.sh ci/*.sh
```

- `ui/phone_detox_ui.py` is the local server (Python standard library only) that runs the
  scripts. `ui/index.html` is the page, with every text in Italian and English in the `T`
  dictionary.
- `ci/fake-adb/` is a fake `adb` that answers the commands the scripts use. To add a case,
  change the fake phone in `ci/test.sh`.
- Agent instructions are in `CLAUDE.md` (other agents find them via `AGENTS.md`).
  `.claude/settings.json` allows only the read-only scripts without confirmation and blocks
  destructive adb commands.

Pull requests are welcome, especially for brand lists: include the model, Android version and
what you tested after turning the app off.

## Credits and license

Based on [tv-detox](https://github.com/Ansub/tv-detox) by Ansub Khan (MIT license). The idea,
the script structure and the basic rules come from there: turn off instead of deleting,
PERSISTENT apps, whoever saved the Wi-Fi. App lists partly derived from
[Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation).

MIT license, see [LICENSE](LICENSE).
