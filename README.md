<img src="icon.png" width="128" alt="TakoKey icon">

# TakoKey

Got more than two languages on your Mac and tired of juggling them? So was I. Not anymore!

TakoKey gives each input language its own keyboard shortcut. When you push the shortcut, your Mac changes to that language immediately.

> *Tako* (タコ) is Japanese for octopus. **ta-ko-key** - that's the beat of **Cmd-Shift-1**.  


## Requirements

- A Mac with Apple silicon (M1 or later).
- macOS 13 or later. Tested on: 
    - macOS 26.6.2
    - macOS 26.7.1
    - macOS Golden Gate 27.0.1.

## Install

1. Download `TakoKey.dmg` from [Releases](../../releases).
2. Open the DMG. Move TakoKey to Applications.
3. Start TakoKey. If macOS stops it, go to **System Settings > Privacy & Security** and click **Open Anyway**.

To get a new version, click the menu-bar icon > **Check for Updates…**.
Quit TakoKey before you replace the app. A running TakoKey stays the old version until you quit it.

## Build from source

```bash
xcode-select --install
git clone https://github.com/bvpotapenko/takokey.git && cd takokey
chmod +x build.sh && ./build.sh
pkill -x TakoKey; rm -rf /Applications/TakoKey.app
cp -R build/dmg/TakoKey.app /Applications/ && open /Applications/TakoKey.app
```

## Settings

Click the menu-bar icon > **Settings…**. Changes are saved right away. Press **Esc** to close.

- Each language you have is in the list. Click its shortcut, then push the new keys. **Delete** removes the shortcut. **Esc** cancels.
- Use ⌃, ⌥, or ⌘. You can also add ⇧. Keys: 0–9, A–Z.
- New settings use ⇧⌘ with 1, 2, 7, 8, 9 and 0. They skip 3–6 because macOS takes screenshots with them.
- You can also take over a macOS shortcut, like ⇧⌘3. While TakoKey runs, it changes the language instead. Settings shows a warning below it.
- If another language or macOS also uses a shortcut, Settings shows a warning below it. TakoKey cannot see the shortcuts of other apps.
- You cannot use `fn` (🌐). To use the 🌐 key, change it to Control in **System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys**.
- Did you add a language? It is in the list. Give it a shortcut. To start again from your current languages, click **Reset to Defaults**. TakoKey keeps the old file as `takokey.txt.bak`.
- To start TakoKey when you log in, turn on **Start TakoKey at login** in Settings.

TakoKey keeps your settings in `~/.config/takokey.txt`. You can also edit this file. Then quit and start TakoKey again. If a line has an error, the icon changes to a warning triangle. The menu shows the line.

## Routes

Some input methods, for example Chinese, stay active after you change the language. The menu bar shows the new language, but you type English. A route prevents this: TakoKey changes to English first, and then to your language.

TakoKey adds routes for these input methods automatically. To change them, go to **Settings… > Routes**.

Does a different language have this problem? [Open an issue](../../issues).

## License

[GNU GPL v3](LICENSE)

© 2026 Bogdan Potapenko, https://potapenko.ai
