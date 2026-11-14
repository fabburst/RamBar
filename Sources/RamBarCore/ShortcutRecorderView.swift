import AppKit
import Carbon.HIToolbox
import SwiftUI

public struct ShortcutRecorderView: View {
    @Binding public var combo: HotKeyCombo?
    @State private var isRecording = false
    @State private var monitor: Any?

    public init(combo: Binding<HotKeyCombo?>) {
        self._combo = combo
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(labelText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.primary.opacity(isRecording ? 0.16 : 0.08))
                    )
            }
            .buttonStyle(.plain)

            if combo != nil && !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.string("settings.hotkey.clear"))
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var labelText: String {
        if isRecording {
            return L10n.string("settings.hotkey.press")
        }
        return combo?.displayString ?? L10n.string("settings.hotkey.record")
    }

    private func startRecording() {
        isRecording = true
        GlobalHotKeyManager.shared.unregister()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let modifiers = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                return nil
            }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let combo {
            GlobalHotKeyManager.shared.register(combo: combo) {
                GlobalHotKeyManager.toggleMenuBarPopover()
            }
        }
    }
}
