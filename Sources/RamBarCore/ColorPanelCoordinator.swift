import AppKit
import SwiftUI

@MainActor
public final class ColorPanelCoordinator: NSObject {
    public static let shared = ColorPanelCoordinator()

    private var onChange: ((Color) -> Void)?

    private override init() {
        super.init()
    }

    public func open(initialColor: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(initialColor).usingColorSpace(.sRGB) ?? .systemRed
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        let srgb = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let swiftUIColor = Color(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            opacity: 1.0
        )
        onChange?(swiftUIColor)
    }
}
