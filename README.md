<img src="icon.png" width="128" alt="TakoKey icon">

# TakoKey

Got more than two languages on your Mac and tired of juggling them? So was I. Not anymore!

TakoKey gives each input language its own keyboard shortcut. When you push the shortcut, your Mac changes to that language immediately.

> *Tako* (タコ) is Japanese for octopus. **ta-ko-key** - that's the beat of **Cmd-Shift-1**.  


## Requirements

- A Mac with Apple silicon (M1 or later).
- macOS 13 or later. Tested on macOS 26.6.2.

## Install

1. Download `TakoKey.dmg` from [Releases](../../releases).
2. Open the DMG. Move TakoKey to Applications.
3. Start TakoKey. If macOS stops it, go to **System Settings > Privacy & Security** and click **Open Anyway**.

To get a new version, click the menu-bar icon > **Check for Updates…**.

## Build from source

```bash
xcode-select --install
git clone https://github.com/bvpotapenko/takokey.git && cd takokey
chmod +x build.sh && ./build.sh
pkill -x TakoKey; rm -rf /Applications/TakoKey.app
cp -R build/dmg/TakoKey.app /Applications/ && open /Applications/TakoKey.app
```

## Settings

Click the menu-bar icon > **Edit Config…**. Change the file, save it, and click **Reload Config**.

```
cmd+shift+1 = com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese  # Japanese
cmd+shift+2 = com.apple.keylayout.Hawaiian                         # Hawaiian (ʻŌlelo Hawaiʻi)
cmd+shift+6 = com.apple.keylayout.ABC                              # English
cmd+shift+7 = com.apple.keylayout.German                           # German
cmd+shift+8 = com.apple.keylayout.Russian                          # Russian
cmd+shift+9 = com.apple.keylayout.Ukrainian-PC                     # Ukrainian
cmd+shift+0 = com.apple.inputmethod.SCIM.ITABC                     # Chinese (Pinyin)
```

- Use `ctrl`, `opt`, or `cmd`. You can also add `shift`. Keys: `0`–`9`, `a`–`z`.
- You cannot use `fn` (🌐). To use the 🌐 key, change it to Control in **System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys**, and write `ctrl`.
- If a line has an error, the icon changes to a warning triangle. The menu shows the line.
- Did you add a language, or is the file broken? Click **Reset Settings**. TakoKey keeps the old file as `takokey.txt.bak`.
- New settings use cmd+shift with 1, 2, 6–9 and 0. They skip 3, 4 and 5 because macOS takes screenshots with them.
- To start TakoKey automatically, add it in **System Settings > General > Login Items**.

## Routes

Some input methods, for example Chinese, stay active after you change the language. The menu bar shows the new language, but you type English. A route prevents this: TakoKey changes to English first, and then to your language.

TakoKey adds routes for these input methods automatically:

```
route com.apple.inputmethod.SCIM.ITABC via com.apple.keylayout.ABC
```

Does a different language have this problem? [Open an issue](../../issues).

## License

[GNU GPL v3](LICENSE)

© 2026 Bogdan Potapenko, https://potapenko.ai
