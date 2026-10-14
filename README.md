<img src="icon.png" width="128" alt="TakoKey icon">

# TakoKey

Got more than two languages on your Mac and tired of juggling them? So was I. Not anymore!

TakoKey gives each input language its own keyboard shortcut. When you push the shortcut, your Mac changes to that language immediately.

> *Tako* (タコ) is Japanese for octopus. **ta-ko-key** - that's the beat of **Ctrl-Shift-1**.  


## Requirements

- A Mac with Apple silicon (M1 or later).
- macOS 13 or later. Tested on macOS 26.6.2.

## Install

1. Download `TakoKey.dmg` from [Releases](../../releases).
2. Open the DMG.
3. Move TakoKey to the Applications folder.
4. Start TakoKey. A keyboard icon shows in the menu bar.

> **Note:** The app does not have an Apple developer certificate. Thus, macOS stops the app the first time. To start it, go to **System Settings > Privacy & Security** and click **Open Anyway**.

## Build from source

You must have the Xcode Command Line Tools.

```bash
xcode-select --install
git clone https://github.com/bvpotapenko/takokey.git
cd takokey
chmod +x ./build.sh && ./build.sh
```

The script makes `TakoKey.dmg` in the same folder. You can install the app from the DMG. You can also copy the app directly:

```bash
pkill -x TakoKey; rm -rf /Applications/TakoKey.app
cp -R build/dmg/TakoKey.app /Applications/
open /Applications/TakoKey.app
```

The first line stops and removes the old version. Do not copy the new app over the old app, because macOS can then stop the new app.

## Set the shortcuts

When the app starts for the first time, it makes the file `~/.config/takokey.txt`. The file has one line for each input language on your Mac. For example:

```
ctrl+shift+1 = com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese  # Japanese
ctrl+shift+2 = com.apple.keylayout.Hawaiian                         # Hawaiian (ʻŌlelo Hawaiʻi)
ctrl+shift+3 = com.apple.keylayout.ABC                              # English
ctrl+shift+4 = com.apple.keylayout.German                           # German
ctrl+shift+5 = com.apple.keylayout.Russian                          # Russian
ctrl+shift+6 = com.apple.keylayout.Ukrainian-PC                     # Ukrainian
ctrl+shift+7 = com.apple.inputmethod.SCIM.ITABC                     # Chinese (Pinyin)
```

To change a shortcut:

1. Click the menu-bar icon.
2. Click **Edit Config…**.
3. Change the file and save it.
4. Click **Reload Config**.

Each shortcut must have one modifier key that is not Shift. If a line has an error, the icon changes to ⚠️. The menu shows the line with the error.

To add a new language:

1. Add the language in **System Settings > Keyboard > Input Sources**.
2. Delete the file `~/.config/takokey.txt`.
3. Click **Reload Config**. The app makes a new file with the correct IDs for all your languages.

To start the app automatically, add it in **System Settings > General > Login Items**.

## Routes

Some input methods cause a problem when you change from them to a different language. 
That's a known Mac issue.  
For example, you change from Chinese (Pinyin) to German. The menu bar shows Gernman, but you type English.

A route prevents this problem. TakoKey changes to a safe language first, and then to your language. Add one line for each problem language:

```
route com.apple.inputmethod.SCIM.ITABC via com.apple.keylayout.ABC
```

This line means: when you leave Chinese (Pinyin), go through ABC first. The menu shows all routes that are active.

Did you find a different language with this problem? Please [open an issue](../../issues) and tell us the input source ID.

## License

TakoKey is free software under the [GNU GPL v3](LICENSE). You can use it, change it, and share it, also for work. If you share a changed version or use this code in your own app, you must also share that source code under the GPL. You must keep the copyright notice: © 2026 Bogdan Potapenko, https://potapenko.ai.
