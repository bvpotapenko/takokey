// TakoKey - one hotkey per input source, like Windows' Ctrl+Shift+1/2/3.
// Copyright (C) 2026 Bogdan Potapenko, https://potapenko.ai. SPDX-License-Identifier: GPL-3.0-or-later
//
// Config: ~/.config/takokey.txt — generated on first launch from your enabled input
//         sources. Edit it, then click the menu-bar icon -> Reload Config.
// Build:  ./build.sh   (needs only Xcode Command Line Tools: xcode-select --install)
//
// Hotkeys use Carbon's RegisterEventHotKey: system-wide, matched by physical key
// position (so they fire whatever layout is active), no Accessibility permission needed.

import AppKit
import Carbon

// Pause between the two hops of a route ("route X via Y" in the config).
// Raise it if the target language still comes up wrong after a route.
let routeDelay = 0.1   // seconds

final class TakoKey: NSObject {
    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/takokey.txt")
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var hotKeys: [EventHotKeyRef] = []
    var targets: [UInt32: String] = [:]   // hotkey id -> input source ID
    var routes: [String: String] = [:]    // input source ID -> source to pass through when leaving it
    var lastRequest = 0                   // lets a newer press cancel a route's pending second hop

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
    }

    // MARK: Config -> hotkeys + menu

    @objc func reload() {
        if !FileManager.default.fileExists(atPath: configURL.path) { writeDefaultConfig() }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        targets = [:]
        routes = [:]

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
                guard ids.count == 2, let from = inputSource(ids[0]), let via = inputSource(ids[1]) else {
                    problems.append("line \(lineNo): expected  route <ID> via <ID>  (both enabled)"); continue
                }
                routes[ids[0]] = ids[1]
                routeLines.append("↪ leaving \(property(from, kTISPropertyLocalizedName)): "
                                  + "via \(property(via, kTISPropertyLocalizedName))")
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
            guard register(parts[0], id: lineNo) else {
                problems.append("line \(lineNo): invalid or already-taken shortcut \(parts[0])"); continue
            }
            targets[lineNo] = parts[1]
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
        menu.addItem(withTitle: "Quit TakoKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: problems.isEmpty ? "keyboard" : "exclamationmark.triangle",
            accessibilityDescription: "TakoKey")
    }

    // "ctrl+shift+1" -> a registered global hotkey. Rejects unknown words, and combos whose
    // only modifier is shift (shift+1 would hijack typing "!").
    func register(_ shortcut: String, id: UInt32) -> Bool {
        var modifiers = 0
        var keyCode: Int?
        for word in shortcut.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch word {
            case "ctrl", "control": modifiers |= controlKey
            case "opt", "option", "alt": modifiers |= optionKey
            case "cmd", "command": modifiers |= cmdKey
            case "shift": modifiers |= shiftKey
            default:
                guard keyCode == nil, let code = TakoKey.keyCodes[word] else { return false }
                keyCode = code
            }
        }
        guard let keyCode, modifiers & ~shiftKey != 0 else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: 0, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeys.append(ref)
        return true
    }

    // First launch: bind ctrl+shift+1…9 to the input sources currently enabled on this Mac.
    func writeDefaultConfig() {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        let enabled = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] ?? []
        var lines = [
            "# TakoKey — one binding per line:   shortcut = input-source-ID",
            "# Modifiers: ctrl opt cmd shift (at least one besides shift). Keys: 0-9 a-z, by physical position.",
            "# Save, then menu-bar icon -> Reload Config. Text after # is ignored.",
            "# Delete this file and Reload to regenerate it from your currently enabled input sources.",
            "#",
            "# If leaving a language goes wrong (menu bar shows the new one, you type another),",
            "# make TakoKey pass through a safe language first:",
            "#   route com.apple.inputmethod.SCIM.ITABC via com.apple.keylayout.ABC",
            "",
        ]
        for (i, source) in enabled.enumerated() {
            let shortcut = i < 9 ? "ctrl+shift+\(i + 1)" : "# ctrl+shift+?"
            lines.append("\(shortcut) = \(property(source, kTISPropertyInputSourceID))"
                         + "   # \(property(source, kTISPropertyLocalizedName))")
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
        // No route for where we are (or nowhere to go): switch directly.
        guard currentID != id, let viaID = routes[currentID], viaID != id,
              let via = inputSource(viaID) else {
            TISSelectInputSource(target)
            return
        }
        TISSelectInputSource(via)
        DispatchQueue.main.asyncAfter(deadline: .now() + routeDelay) {
            if request == self.lastRequest { TISSelectInputSource(target) }   // skip if a newer press won
        }
    }

    func property(_ source: TISInputSource, _ key: CFString) -> String {
        guard let value = TISGetInputSourceProperty(source, key) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    // MARK: Menu actions

    @objc func pick(_ item: NSMenuItem) { select(item.representedObject as! String) }
    @objc func editConfig() { NSWorkspace.shared.open(configURL) }
}

let app = NSApplication.shared   // must exist before we touch the menu bar
let takoKey = TakoKey()          // a global, so it lives as long as the app
app.run()
