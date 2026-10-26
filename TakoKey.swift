// TakoKey - one hotkey combo per input source, like Windows' Ctrl+Shift+1/2/3.
// Copyright (C) 2026 Bogdan Potapenko, https://potapenko.ai. SPDX-License-Identifier: GPL-3.0-or-later
//
// Config: ~/.config/takokey.txt — generated on first launch from your enabled input sources. Edit it, then click the menu-bar icon -> Reload Config.
//
// Build:  ./build.sh   (needs only Xcode Command Line Tools: xcode-select --install)
//
// Hotkeys use Carbon's RegisterEventHotKey: system-wide, matched by physical key position (so they fire whatever layout is active), no Accessibility permission needed.

import AppKit   // menu bar, menus, files (also brings in Foundation)
import Carbon   // global hotkeys and input sources (TIS...)


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

final class TakoKey: NSObject {
    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/takokey.txt")
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var hotKeys: [EventHotKeyRef] = []
    var targets: [UInt32: String] = [:]   // hotkey id -> input source ID
    var routes: [String: String] = [:]    // input source ID -> source to pass through when leaving it
    var lastRequest = 0                   // lets a newer press cancel a route's pending second hop
    var shortcutList: [String] = []       // "ctrl+shift+1   ABC" lines for the About window
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
            if let sourceID = me.targets[hotKey.id] { me.select(sourceID) }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        reload()
        warmUp()
    }
 
    // MARK: Config -> hotkeys + menu
 
    @objc func reload() {
        if !FileManager.default.fileExists(atPath: configURL.path) { writeDefaultConfig() }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        targets = [:]
        routes = [:]
        shortcutList = []
 
        let menu = NSMenu()
        var routeLines: [String] = []
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
                guard ids.count == 2, !ids[0].isEmpty, let via = inputSource(ids[1]) else {
                    problems.append("line \(lineNo): expected  route <ID> via <enabled ID>"); continue
                }
                routes[ids[0]] = ids[1]
                if let from = inputSource(ids[0]) {   // only list routes for sources you have
                    routeLines.append("↪ leaving \(property(from, kTISPropertyLocalizedName)): "
                                      + "via \(property(via, kTISPropertyLocalizedName))")
                }
                continue
            }
 
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else {
                problems.append("line \(lineNo): expected  shortcut = input-source-ID"); continue
            }
            guard let source = inputSource(parts[1]) else {
                problems.append("line \(lineNo): no enabled input source \(parts[1])"); continue
            }
            if let problem = register(parts[0], id: lineNo) {
                problems.append("line \(lineNo): \(problem)"); continue
            }
            targets[lineNo] = parts[1]
            shortcutList.append("\(parts[0])   \(property(source, kTISPropertyLocalizedName))")
            let item = NSMenuItem(title: "\(parts[0])   \(property(source, kTISPropertyLocalizedName))",
                                  action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = parts[1]
            menu.addItem(item)
        }
        // Items without an action show greyed out: information only.
        for line in routeLines + problems.map({ "⚠︎ " + $0 }) {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Config…", action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reset Settings", action: #selector(resetConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TakoKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "About TakoKey \(version)", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: problems.isEmpty ? "keyboard" : "exclamationmark.triangle",
            accessibilityDescription: "TakoKey")
    }
 
    // "ctrl+shift+1" -> a registered global hotkey. Returns what's wrong, or nil on success.
    // Shift alone is refused: shift+1 would hijack typing "!".
    func register(_ shortcut: String, id: UInt32) -> String? {
        var modifiers = 0
        var keyCode: Int?
        for word in shortcut.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch word {
            case "ctrl", "control": modifiers |= controlKey
            case "opt", "option", "alt": modifiers |= optionKey
            case "cmd", "command": modifiers |= cmdKey
            case "shift": modifiers |= shiftKey
            case "fn", "globe": return "fn is reserved by macOS; use ctrl, opt or cmd (if you remapped 🌐, write the key it became)"
            default:
                guard keyCode == nil, let code = TakoKey.keyCodes[word] else { return "unknown key \(word)" }
                keyCode = code
            }
        }
        guard let keyCode else { return "no key in \(shortcut)" }
        guard modifiers & ~shiftKey != 0 else { return "\(shortcut) needs ctrl, opt or cmd" }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: 0, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return "macOS refused \(shortcut) (error \(status))" }
        hotKeys.append(ref)
        return nil
    }
 
    // First launch: bind cmd+shift+1, 2, 6…9, 0 to the enabled input sources (3, 4, 5 take
    // macOS screenshots), and route every input method (plus the known sticky ones) through an English layout.
    func writeDefaultConfig() {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        let enabled = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] ?? []
        let id = { (s: TISInputSource) in self.property(s, kTISPropertyInputSourceID) }
        let name = { (s: TISInputSource) in self.property(s, kTISPropertyLocalizedName) }
        let isLayout = { (s: TISInputSource) in
            self.property(s, kTISPropertyInputSourceType) == kTISTypeKeyboardLayout as String
        }
        // The safe stop for routes: ABC or U.S., else any plain layout that types Latin letters.
        let english = enabled.first { ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(id($0)) }
            ?? enabled.first { isLayout($0) && self.isASCIICapable($0) }
 
        var lines = [
            "# TakoKey settings. Text after # is ignored.",
            "# After you change this file: menu-bar icon -> Reload Config.",
            "# To start again from your current input sources: menu-bar icon -> Reset Settings",
            "# (your old file is kept as takokey.txt.bak).",
            "",
            "# ---- Shortcuts --------------------------------------------------------------",
            "# Format:     shortcut = input-source-ID",
            "# Modifiers:  ctrl (or control), opt (or option, alt), cmd (or command), shift",
            "#             Use at least one of ctrl / opt / cmd. fn (🌐) can't be used: macOS reserves it.",
            "#             Avoid cmd+shift+3, 4, 5: macOS takes screenshots with them.",
            "# Example:    ctrl+opt+r = com.apple.keylayout.Romanian",
            "",
        ]
        let keys = ["1", "2", "6", "7", "8", "9", "0"]   // cmd+shift+3, 4, 5 take screenshots
        for (i, source) in enabled.enumerated() {
            let shortcut = i < keys.count ? "cmd+shift+\(keys[i])" : "# cmd+shift+?"
            lines.append("\(shortcut) = \(id(source))   # \(name(source))")
        }
        lines += [
            "",
            "# ---- Routing ----------------------------------------------------------------",
            "# Some input methods (Chinese, Japanese, Korean...) stick: after you switch away,",
            "# the menu bar shows the new language, but you still type in another one.",
            "# A route fixes this: ",
            "#      when you leave <from-ID>, TakoKey first switches to <via-ID>, then to your target.",
            "# Format:",     
            "#      route <from-ID> via <via-ID>",
            "#",
            "# <via-ID> must be an enabled plain layout, usually English (ABC or U.S.).",
            "# Routes for input sources you don't have are ignored, so it's safe to keep them all.",
            "",
        ]
        var routed = enabled.filter { !isLayout($0) }.map { (id($0), name($0)) }
        for known in knownSticky where !routed.contains(where: { $0.0 == known.0 }) { routed.append(known) }
        if english == nil {
            lines.append("# No English layout is enabled. Add ABC in System Settings, then delete this file and Reload.")
        }
        let viaID = english.map(id) ?? "com.apple.keylayout.ABC"
        for (fromID, fromName) in routed {
            lines.append("\(english == nil ? "# " : "")route \(fromID) via \(viaID)   # \(fromName)")
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

            Settings: ~/.config/takokey.txt
            To change them: menu-bar icon → Edit Config…

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
    @objc func editConfig() { NSWorkspace.shared.open(configURL) }
 
    // Keep the old file as takokey.txt.bak (one level of undo), then write fresh defaults.
    @objc func resetConfig() {
        let backup = configURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: configURL, to: backup)
        reload()   // no config file -> reload writes the defaults
    }
}
 
let app = NSApplication.shared   // must exist before we touch the menu bar
let takoKey = TakoKey()          // a global, so it lives as long as the app
app.run()

