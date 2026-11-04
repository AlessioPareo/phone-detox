# The prompt to give Claude

Open [Claude Code](https://claude.com/claude-code) **in this repository's folder**, on the
computer the phone is connected to. Claude reads [CLAUDE.md](CLAUDE.md) by itself, which has
all the rules and the procedure. Write in your own language: Claude answers in the same one.

## The shortest way

Type:

```
/clean
```

You can add details after the command, for example `/clean I use Samsung Health and Android Auto`.

Other commands:

- `/identify`: says which phone is connected, with marketing name and model number, without
  changing anything
- `/undo`: turns everything back on, or `/undo com.example.app` for a single app

## The full prompt

If you'd rather write it yourself, or you use another agent (Codex, Gemini CLI, Cursor), paste
this and fill in the parts between `< >`:

```
Help me clean the useless apps off my Android phone, using the scripts in
this folder and following CLAUDE.md.

My phone: <brand and model, if you know it, otherwise write "I don't know">
Apps and features I use that must stay: <e.g. Samsung Health, Android Auto,
paying with the phone, alarms, banking app>
How it's connected: <USB cable / Wi-Fi>

1. First tell me in plain words that turning off system apps has risks and
   that you can make mistakes, remind me to back up and ask me to confirm.
2. Connect and identify the phone precisely with identify.sh. If you're not
   sure about the model, ask me to read you Settings > About phone and save
   the name I give you.
3. Look up online the preinstalled apps known for my exact model and tell me
   your sources.
4. Show me the free memory with info.sh and the app list with candidates.sh,
   explained in plain words.
5. Propose groups of at most 10 apps. Wait for my yes for each group. Never
   touch "never" apps, and when in doubt leave them on.
6. After each group have me restart and test calls, SMS, data, Wi-Fi,
   Bluetooth, notifications, camera, alarms and payments. If something's
   wrong, undo that group.
7. At the end show me free memory before and after and remind me to turn
   off USB and wireless debugging.
```

## If you use an agent without this folder

Claude in the app or on claude.ai can't see your phone: it runs on Anthropic's servers. You
need an agent that runs on your computer, in this repository's folder, so it has the scripts
and their protections. Without the scripts the agent would use adb by hand, without the
`never` lists and without the list to undo changes: don't do that.
