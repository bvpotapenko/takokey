// TakoKey - one hotkey combo per input source, like Windows' Ctrl+Shift+1/2/3.
// Copyright (C) 2026 Bogdan Potapenko, https://potapenko.ai. SPDX-License-Identifier: GPL-3.0-or-later
//
// Config: ~/.config/takokey.txt — generated on first launch from your enabled input sources. Change it in the menu-bar icon -> Settings
//
// Build:  ./build.sh   (needs only Xcode Command Line Tools: xcode-select --install)
//
// Hotkeys use Carbon's RegisterEventHotKey: system-wide, matched by physical key position (so they fire whatever layout is active), no Accessibility permission needed.

import AppKit   // menu bar, menus, files (also brings in Foundation)
import Carbon   // global hotkeys and input sources (TIS...)
import SwiftUI  // the Settings window


// Pause between the two hops of a route ("route X via Y" in the config).
let routeDelay = 0.03   // seconds

// After a switch, select the same language once more after this pause. macOS's language
// popup near the cursor sometimes shows the old language after a switch made by an app;
// a repeat makes it show the right one (like pressing the shortcut twice). 0 = off.
let popupFixDelay = 0.03   // seconds
 
// Input methods known to "stick" when you leave them. Written as routes into a new config
// even when not installed, so they work the day you add them. A wrong ID here is harmless:
// routes for input sources you don't have never fire.
let knownSticky: [(String, String)] = [
    ("com.apple.inputmethod.SCIM.ITABC", "Chinese, Pinyin – Simplified"),
    ("com.apple.inputmethod.TCIM.Pinyin", "Chinese, Pinyin – Traditional"),
    ("com.apple.inputmethod.TCIM.Zhuyin", "Chinese, Zhuyin"),
    ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "Japanese, Romaji"),
    ("com.apple.inputmethod.Korean.2SetKorean", "Korean, 2-Set"),
]
 
// Pause between the steps of the start-up warm-up (see warmUp). Keep it above
// routeDelay + popupFixDelay, so each step finishes before the next one starts.
let warmUpStep = 0.2   // seconds

let repoURL = "https://github.com/bvpotapenko/takokey"

final class TakoKey: NSObject, ObservableObject, NSWindowDelegate {
    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/takokey.txt")
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var hotKeys: [EventHotKeyRef] = []
    var targets: [UInt32: String] = [:]   // hotkey id -> input source ID
    var routes: [String: String] = [:]    // input source ID -> source to pass through when leaving it
    var lastRequest = 0                   // lets a newer press cancel a route's pending second hop
    var shortcutList: [String] = []       // "⇧ ⌘ 1   ABC" lines for the About window
    var shortcuts: [String: String] = [:] // input source ID -> "cmd+shift+1", for Settings
    @Published var recording: String?     // Settings: input source ID waiting for its new keys
    var keyMonitor: Any?                  // catches those keys
    var recordKeys: [UInt32: String] = [:] // while recording: hotkey id -> the shortcut it stands for
    var settingsWindow: NSWindow?
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
 
    // Physical keys, named by their US-layout label.
    static let keyCodes: [String: Int] = [
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
    ]

    static func keyName(_ code: Int) -> String? { keyCodes.first { $0.value == code }?.key }

    // The modifiers in the order macOS shows them: Carbon bit, AppKit flag, config word, symbol.
    static let modifiers: [(carbon: Int, flag: NSEvent.ModifierFlags, word: String, symbol: String)] = [
        (controlKey, .control, "ctrl", "⌃"), (optionKey, .option, "opt", "⌥"),
        (shiftKey, .shift, "shift", "⇧"), (cmdKey, .command, "cmd", "⌘"),
    ]

    override init() {
        super.init()
        // One handler for all our hotkeys; the hotkey's id says which binding fired.
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let me = Unmanaged<TakoKey>.fromOpaque(userData!).takeUnretainedValue()
            if let shortcut = me.recordKeys[hotKey.id] {
                me.finishRecording(shortcut)
            } else if let sourceID = me.targets[hotKey.id] {
                me.select(sourceID)
            }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        reload()
        warmUp()
    }
 
    // MARK: Config -> hotkeys + menu
 
    @objc func reload() {
        if !FileManager.default.fileExists(atPath: configURL.path) { writeDefaultConfig() }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        objectWillChange.send()   // Settings shows what we read below
        hotKeys = []
        targets = [:]
        routes = [:]
        shortcutList = []
        shortcuts = [:]
 
        let menu = NSMenu()
        var problems: [String] = []
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = UInt32(index + 1)   // doubles as the hotkey id
 
            // "route <from-ID> via <via-ID>": when leaving <from>, pass through <via> first.
            if line.hasPrefix("route ") {
                let ids = line.dropFirst(6).components(separatedBy: " via ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard ids.count == 2, !ids[0].isEmpty, inputSource(ids[1]) != nil else {
                    problems.append("line \(lineNo): expected  route <ID> via <enabled ID>"); continue
                }
                routes[ids[0]] = ids[1]
                
                continue
            }
 
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else {
                problems.append("line \(lineNo): expected  shortcut = input-source-ID"); continue
            }
            shortcuts[parts[1]] = parts[0]   // even if it fails below: Settings shows it with a warning
            guard let source = inputSource(parts[1]) else {
                problems.append("line \(lineNo): no enabled input source \(parts[1])"); continue
            }
            if let problem = register(parts[0], id: lineNo) {
                problems.append("line \(lineNo): \(problem)"); continue
            }
            targets[lineNo] = parts[1]
            let name = property(source, kTISPropertyLocalizedName)
            shortcutList.append("\(TakoKey.symbols(parts[0]))   \(name)")
            // The shortcut shows on the right, the way macOS menus show theirs.
            let combo = TakoKey.combo(parts[0])!   // register() just accepted it
            let item = NSMenuItem(title: name, action: #selector(pick(_:)), keyEquivalent: TakoKey.keyName(combo[0])!)
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(
                TakoKey.modifiers.filter { combo[1] & $0.carbon != 0 }.map { $0.flag })

            item.target = self
            item.representedObject = parts[1]
            menu.addItem(item)
        }
        // Items without an action show greyed out: information only.
        for line in problems.map({ "⚠︎ " + $0 }) {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "About TakoKey \(version)", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit TakoKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: problems.isEmpty ? "keyboard" : "exclamationmark.triangle",
            accessibilityDescription: "TakoKey")
    }
 
     // "cmd+shift+1" -> [physical key code, Carbon modifiers], or nil if a word is unknown
    // (fn included: macOS reserves it).
    static func combo(_ shortcut: String) -> [Int]? {
        var modifiers = 0
        var keyCode: Int?
        for word in shortcut.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch word {
            case "ctrl", "control": modifiers |= controlKey
            case "opt", "option", "alt": modifiers |= optionKey
            case "cmd", "command": modifiers |= cmdKey
            case "shift": modifiers |= shiftKey
            default:
                guard keyCode == nil, let code = keyCodes[word] else { return nil }
                keyCode = code
            }
        }
        return keyCode.map { [$0, modifiers] }
    }

    // [key code, Carbon modifiers] -> "shift+cmd+1", modifiers in the order macOS shows them.
    static func shortcut(_ combo: [Int]) -> String {
        (modifiers.filter { combo[1] & $0.carbon != 0 }.map { $0.word } + [keyName(combo[0]) ?? "?"]).joined(separator: "+")
    }


    // "cmd+shift+1" -> "⇧⌘1", the way macOS writes shortcuts.
    static func symbols(_ shortcut: String) -> String {
        guard let combo = combo(shortcut) else { return shortcut }
        return modifiers.filter { combo[1] & $0.carbon != 0 }.map { $0.symbol }.joined()
            + keyName(combo[0])!.uppercased()
    }

    // "ctrl+shift+1" -> a registered global hotkey. Returns what's wrong, or nil on success.
    // Shift alone is refused: shift+1 would hijack typing "!".
    func register(_ shortcut: String, id: UInt32) -> String? {
        guard let combo = TakoKey.combo(shortcut) else {
            return "can't read \(shortcut): use ctrl, opt, cmd, shift and one key 0-9 or a-z"
        }
        guard combo[1] & ~shiftKey != 0 else { return "\(shortcut) needs ctrl, opt or cmd" }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo[0]), UInt32(combo[1]),
                                         EventHotKeyID(signature: 0, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return "macOS refused \(shortcut) (error \(status))" }
        hotKeys.append(ref)
        return nil
    }
 
    // First launch: bind cmd+shift+1, 2, 7…9, 0 to the enabled input sources (3…6 take
    // macOS screenshots), and route every input method (plus the known sticky ones) through an English layout.
    func writeDefaultConfig() {
        let enabled = enabledSources()
        // The safe stop for routes: ABC or U.S., else any plain layout that types Latin letters.
        let english = enabled.first { ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(sourceID($0)) }
            ?? enabled.first { isPlainLayout($0) && isASCIICapable($0) }
        let keys = ["1", "2", "7", "8", "9", "0"]   // cmd+shift+3…6 take screenshots (6: of the Touch Bar)
        shortcuts = [:]
        for (key, source) in zip(keys, enabled) { shortcuts[sourceID(source)] = "shift+cmd+\(key)" }
        routes = [:]
        if let english {   // none: no routes, the user can pick one in Settings
            for from in enabled.filter({ !isPlainLayout($0) }).map(sourceID) + knownSticky.map({ $0.0 }) {
                routes[from] = sourceID(english)
            }
        }
        writeConfig()
    }

    // Shortcuts and routes -> the config file. Settings calls this, then reload().
    func writeConfig() {
        let order = enabledSources().map(sourceID)   // languages in System Settings order
        let rank = { (id: String) in (order.firstIndex(of: id) ?? order.count, id) }
        var lines = [
            "# TakoKey settings. Change them in the menu-bar icon -> Settings…",
            "# You can also edit this file by hand; then quit and reopen TakoKey. Text after # is ignored.",
            "#   shortcut = input-source-ID     ctrl, opt, cmd, shift + one key 0-9 or a-z",
            "#   route <from-ID> via <via-ID>   when you leave <from-ID>, pass through <via-ID> first",
            "",
        ]
        for id in shortcuts.keys.sorted(by: { rank($0) < rank($1) }) {
            lines.append("\(shortcuts[id]!) = \(id)   # \(name(id))")
        }
        lines.append("")
        for (from, via) in routes.sorted(by: { $0.key < $1.key }) {
            lines.append("route \(from) via \(via)   # \(name(from))")
        }
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }
 
    // MARK: Input sources
 
    func inputSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first
    }
 
    func select(_ id: String) {
        lastRequest += 1
        let request = lastRequest
        guard let target = inputSource(id) else { NSSound.beep(); return }
        let currentID = property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(),
                                 kTISPropertyInputSourceID)
        // Every delayed step checks `request`, so a newer press always wins.
        func later(_ delay: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if request == self.lastRequest { step() } }
        }
        func finish() {
            TISSelectInputSource(target)
            if popupFixDelay > 0 { later(popupFixDelay) { _ = TISSelectInputSource(target) } }
        }
        // No route for where we are (or nowhere to go): switch directly.
        guard currentID != id, let viaID = routes[currentID], viaID != id,
              let via = inputSource(viaID) else {
            finish()
            return
        }
        TISSelectInputSource(via)
        later(routeDelay, finish)
    }
 
    func property(_ source: TISInputSource, _ key: CFString) -> String {
        guard let value = TISGetInputSourceProperty(source, key) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
 
    func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
 
    func isPlainLayout(_ source: TISInputSource) -> Bool {
        property(source, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String
    }

    // Input sources turned on in System Settings, in their order there.
    func enabledSources() -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        return TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    func sourceID(_ source: TISInputSource) -> String { property(source, kTISPropertyInputSourceID) }

    // The Routes list: your input methods, then the known sticky ones and any other route in
    // the file, so they're ready the day you add that language.
    func routeIDs() -> [String] {
        var ids = enabledSources().filter { !isPlainLayout($0) }.map(sourceID)
        for id in knownSticky.map({ $0.0 }) + routes.keys.sorted() where !ids.contains(id) { ids.append(id) }
        return ids
    }

    func name(_ id: String) -> String {
        inputSource(id).map { property($0, kTISPropertyLocalizedName) } ?? knownSticky.first { $0.0 == id }?.1 ?? id
    }

    // Why a language's shortcut may not work, for Settings. nil = fine, as far as we can tell:
    // other apps' global shortcuts can't be seen, and TakoKey wins over shortcuts inside apps.
    func warning(_ id: String) -> String? {
        guard let shortcut = shortcuts[id] else { return nil }
        guard let combo = TakoKey.combo(shortcut) else { return "TakoKey can't read \(shortcut)" }
        if let other = shortcuts.first(where: { $0.key != id && TakoKey.combo($0.value) == combo }) {
            return "Also the shortcut for \(name(other.key))"
        }
        return macOSShortcuts().contains(combo) ? "Takes over a macOS shortcut (System Settings > Keyboard > Keyboard Shortcuts)" : nil
    }

    // macOS's own shortcuts that are on (System Settings > Keyboard > Keyboard Shortcuts),
    // as [key code, Carbon modifiers] like combo().
    func macOSShortcuts() -> [[Int]] {
        var list: Unmanaged<CFArray>?
        CopySymbolicHotKeys(&list)
        return (list?.takeRetainedValue() as? [[String: Any]] ?? [])
            .filter { ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true }
            .map { [$0[kHISymbolicHotKeyCode as String] as? Int ?? -1,
                    ($0[kHISymbolicHotKeyModifiers as String] as? Int ?? 0) & (controlKey | optionKey | shiftKey | cmdKey)] }
    }

    // macOS bug: after TakoKey is installed, the first switch into an input method (Pinyin,
    // Kana...) shows in the menu bar but types plain letters until you switch away and back.
    // So do that once at start: a plain layout, then each input method, then back to where you
    // were. Goes through select(), so routes apply.
    func warmUp() {
        let start = property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
        let ids = Set(targets.values)
        let methods = ids.filter { id in inputSource(id).map { !self.isPlainLayout($0) } ?? false }
        guard !methods.isEmpty else { return }
        let layout = ids.first { id in inputSource(id).map { self.isPlainLayout($0) } ?? false }
        let steps = [layout].compactMap { $0 } + methods.sorted() + [start]
        for (i, id) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * warmUpStep) { self.select(id) }
        }
    }

    // MARK: Menu actions

    // Standard macOS dialog with the app icon, from the menu.
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "TakoKey \(version)"
        alert.informativeText = """
            Your shortcuts:
            \(shortcutList.isEmpty ? "(none yet)" : shortcutList.joined(separator: "\n"))

            To change them: menu-bar icon -> Settings…

            © 2026 Bogdan Potapenko
            github.com/bvpotapenko/takokey
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app must come forward to show a dialog
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: repoURL)!)
        } else {
            NSApp.hide(nil)   // give focus back to the app you were using
        }
    }

    // Show the window at once ("Checking…"), ask GitHub for the latest release, and fill in the
    // answer when it arrives. No auto-install: the app is not signed, so macOS asks
    // "Open Anyway" for every downloaded copy in any case.
    @objc func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Checking for updates…"
        alert.informativeText = repoURL
        let mainButton = alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Close")
        var link = repoURL

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/bvpotapenko/takokey/releases/latest")!)
        request.timeoutInterval = 10   // GitHub can be slow or blocked on some networks
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let tag = release?["tag_name"] as? String   // e.g. "v0.3"
            DispatchQueue.main.async {   // runs while the window is open
                guard let tag else { alert.messageText = "Can't reach GitHub. Try again later."; return }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                switch latest.compare(self.version, options: .numeric) {
                case .orderedDescending:
                    alert.messageText = "TakoKey v\(latest) is available"
                    alert.informativeText = "You have v\(self.version). Download the new DMG, quit TakoKey, and replace the app."
                    mainButton.title = "Download"
                    link = repoURL + "/releases/latest"
                case .orderedSame:
                    alert.messageText = "Your TakoKey v\(self.version) is up to date"
                case .orderedAscending:   // e.g. a build made before its release is published
                    alert.messageText = "Your TakoKey v\(self.version) is newer than the latest release (v\(latest))"
                }
                alert.layout()
            }
        }.resume()

        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app must come forward to show a dialog
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: link)!)
        } else {
            NSApp.hide(nil)   // give focus back to the app you were using
        }
    }

    @objc func pick(_ item: NSMenuItem) { select(item.representedObject as! String) }
 
    // Keep the old file as takokey.txt.bak (one level of undo), then write fresh defaults.
    @objc func resetConfig() {
        let backup = configURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: configURL, to: backup)
        reload()   // no config file -> reload writes the defaults
    }

     // MARK: Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            // As tall as its content, but no taller than the screen: then it scrolls.
            let content = NSHostingView(rootView: SettingsView(tako: self)).fittingSize.height
            let height = min(content, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
            settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(tako: self, height: height)))
            settingsWindow?.title = "TakoKey Settings"
            settingsWindow?.isReleasedWhenClosed = false   // we keep it and show it again
            settingsWindow?.delegate = self
        }
        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app must come forward to show a window
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // Wait for the next key press in Settings and make it the shortcut for `id`.
    // Delete removes the shortcut, Esc cancels. Our hotkeys are off meanwhile, so a combo
    // that's already in use reaches us instead of switching the language.
    func record(_ id: String) {
        let again = recording == id
        stopRecording()
        if again { return }   // a second click cancels
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        recording = id
        // Shortcuts macOS keeps for itself (⇧⌘3 takes a screenshot) never reach this window,
        // but a hotkey beats them. So while we wait, each one is a hotkey too (see init).
        for (i, combo) in macOSShortcuts().enumerated() where TakoKey.keyName(combo[0]) != nil {
            let hotKeyID = UInt32(10_000 + i)   // above any config line number
            if register(TakoKey.shortcut(combo), id: hotKeyID) == nil { recordKeys[hotKeyID] = TakoKey.shortcut(combo) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = TakoKey.modifiers.filter { event.modifierFlags.contains($0.flag) }.reduce(0) { $0 | $1.carbon }
            if TakoKey.keyName(Int(event.keyCode)) != nil, modifiers & ~shiftKey != 0 {
                self.finishRecording(TakoKey.shortcut([Int(event.keyCode), modifiers]))
            } else if [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)) {
                self.finishRecording(nil)
            } else if Int(event.keyCode) == kVK_Escape {
                self.stopRecording()
            } else {
                NSSound.beep()   // not a shortcut TakoKey can use; keep waiting
            }
            return nil
        }
    }

    // The recorder's answer: the new shortcut for the language being recorded (nil removes it).
    func finishRecording(_ shortcut: String?) {
        guard let id = recording else { return }
        shortcuts[id] = shortcut
        writeConfig()
        stopRecording()
    }

    func stopRecording() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
        recording = nil
        recordKeys = [:]
        reload()   // hotkeys back on, with the new shortcut
    }

    // Leaving the window (or closing it) cancels a recording, so the hotkeys never stay off.
    func windowDidResignKey(_ notification: Notification) { stopRecording() }
    func windowWillClose(_ notification: Notification) { NSApp.hide(nil) }   // focus back to your app
}

struct SettingsView: View {
    @ObservedObject var tako: TakoKey
    var height: CGFloat?   // nil: as tall as the content (to measure it), else scroll inside this

    var body: some View {
        let sources = tako.enabledSources()
        let layouts = sources.filter(tako.isPlainLayout).map(tako.sourceID)
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(sources.map(tako.sourceID), id: \.self) { id in
                        LabeledContent {
                            Button(tako.recording == id ? "Press keys…" : tako.shortcuts[id].map(TakoKey.symbols) ?? "Set…") {
                                tako.record(id)
                            }
                        } label: {
                            Text(tako.name(id))
                            if tako.recording == id {
                              Text("Press the new keys. Esc cancels, Delete removes the shortcut.")
                            } else if let warning = tako.warning(id) {
                                Text("⚠︎ " + warning).foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("""
                        Click a shortcut, then press the new keys. Use ⌃, ⌥ or ⌘, plus ⇧ if you like, \
                        with 0–9 or A–Z. These are physical keys, so they work in every layout.
                        You can take over a macOS shortcut too, like ⇧⌘3 for screenshots: while TakoKey \
                        runs, it changes the language instead.
                        You can't use fn (🌐). To use the 🌐 key, change it to Control in \
                        System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys.
                        """)
                }
                Section {
                    ForEach(tako.routeIDs(), id: \.self) { id in
                      Picker(selection: Binding(
                          get: { tako.routes[id] ?? "" },
                          set: { tako.routes[id] = $0.isEmpty ? nil : $0; tako.writeConfig(); tako.reload() }
                      )) {
                          Text("Direct").tag("")
                          ForEach(layouts, id: \.self) { Text("via " + tako.name($0)).tag($0) }
                      } label: {
                          Text(tako.name(id))
                          if tako.inputSource(id) == nil { Text("Not on this Mac yet") }
                      }
                  }
                } header: {
                    Text("Routes")
                } footer: {
                    Text("""
                        Some input methods (Chinese, Japanese, Korean…) stick: after you switch away, \
                        the menu bar shows the new language, but you still type in the old one. A route \
                        fixes this: when you leave the input method, TakoKey first switches to the layout \
                        you pick here (usually English), then to your language.
                        """)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: height == nil)
            Divider()
            HStack {
                Button("Reset to Defaults") { tako.resetConfig() }
                    .help("Start again from the input sources you have now. The old settings are kept in ~/.config/takokey.txt.bak.")
                Spacer()
                Text("Changes are saved right away.").foregroundStyle(.secondary)
                Button("Done") { tako.settingsWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: height)
    }
}
 
let app = NSApplication.shared   // must exist before we touch the menu bar
let takoKey = TakoKey()          // a global, so it lives as long as the app
app.run()

