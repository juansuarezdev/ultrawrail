import Carbon.HIToolbox
import LayoutEngine
import LinkrCore

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

    private struct Binding {
        let name: String
        let keyCode: Int
        let command: Command
        var shift = false
    }

    private static let bindings: [Binding] = [
        Binding(name: "⌃⌥H", keyCode: kVK_ANSI_H, command: .focusLeft),
        Binding(name: "⌃⌥←", keyCode: kVK_LeftArrow, command: .focusLeft),
        Binding(name: "⌃⌥L", keyCode: kVK_ANSI_L, command: .focusRight),
        Binding(name: "⌃⌥→", keyCode: kVK_RightArrow, command: .focusRight),
        Binding(name: "⌃⌥K", keyCode: kVK_ANSI_K, command: .focusUp),
        Binding(name: "⌃⌥↑", keyCode: kVK_UpArrow, command: .focusUp),
        Binding(name: "⌃⌥J", keyCode: kVK_ANSI_J, command: .focusDown),
        Binding(name: "⌃⌥↓", keyCode: kVK_DownArrow, command: .focusDown),
        Binding(name: "⌃⌥R", keyCode: kVK_ANSI_R, command: .cycleWidth),
        Binding(name: "⌃⌥F", keyCode: kVK_ANSI_F, command: .toggleFullWidth),
        Binding(name: "⌃⌥C", keyCode: kVK_ANSI_C, command: .centerColumn),
        Binding(name: "⌃⌥[", keyCode: kVK_ANSI_LeftBracket, command: .stackLeft),
        Binding(name: "⌃⌥]", keyCode: kVK_ANSI_RightBracket, command: .unstack),
        Binding(name: "⌃⌥⇧H", keyCode: kVK_ANSI_H, command: .moveColumnLeft, shift: true),
        Binding(name: "⌃⌥⇧←", keyCode: kVK_LeftArrow, command: .moveColumnLeft, shift: true),
        Binding(name: "⌃⌥⇧L", keyCode: kVK_ANSI_L, command: .moveColumnRight, shift: true),
        Binding(name: "⌃⌥⇧→", keyCode: kVK_RightArrow, command: .moveColumnRight, shift: true),
        Binding(name: "⌃⌥T", keyCode: kVK_ANSI_T, command: .showTemplates),
    ]

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register() -> [String] {
        installHandlerIfNeeded()
        var failed: [String] = []
        for (index, binding) in Self.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                UInt32(controlKey | optionKey | (binding.shift ? shiftKey : 0)),
                EventHotKeyID(signature: hotkeySignature, id: UInt32(index)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(binding.name)
            }
        }
        return failed
    }

    func fire(_ id: UInt32) {
        guard Self.bindings.indices.contains(Int(id)) else { return }
        onCommand?(Self.bindings[Int(id)].command)
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
