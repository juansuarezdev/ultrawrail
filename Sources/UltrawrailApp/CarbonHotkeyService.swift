import Carbon.HIToolbox
import LayoutEngine
import UltrawrailCore

private let hotkeySignature: OSType = 0x4C4E4B52 // 'LNKR'

private func hotkeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    let service = Unmanaged<CarbonHotkeyService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire(hotkeyID.id) }
    return noErr
}

@MainActor
final class CarbonHotkeyService: HotkeyService {
    var onCommand: ((Command) -> Void)?

    private var shortcuts: [ResolvedShortcut] = []
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register(_ shortcuts: [ResolvedShortcut]) -> [String] {
        installHandlerIfNeeded()
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        self.shortcuts = shortcuts
        var failed: [String] = []
        for (index, shortcut) in shortcuts.enumerated() {
            let combo = shortcut.combo
            var modifiers = 0
            if combo.control { modifiers |= controlKey }
            if combo.option { modifiers |= optionKey }
            if combo.command { modifiers |= cmdKey }
            if combo.shift { modifiers |= shiftKey }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                UInt32(modifiers),
                EventHotKeyID(signature: hotkeySignature, id: UInt32(index)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(shortcut.title)
            }
        }
        return failed
    }

    func fire(_ id: UInt32) {
        guard shortcuts.indices.contains(Int(id)) else { return }
        onCommand?(shortcuts[Int(id)].command)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        handlerInstalled = true
    }
}
