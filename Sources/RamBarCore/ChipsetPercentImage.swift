import AppKit
import SwiftUI

public enum ChipsetPercentImage {
    @MainActor
    public static func make(
        percent: Int,
        tint: Color,
        isTemplate: Bool,
        style: ChipsetStyle = .outline
    ) -> NSImage {
        let clamped = max(0, min(999, percent))
        let text = "\(clamped)"
        let width: CGFloat = clamped >= 100 ? 25 : 22
        let height: CGFloat = 18
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            let drawColor: NSColor = isTemplate ? .black : NSColor(tint)

            let bodyRect = NSRect(x: 1.5, y: 3.25, width: rect.width - 3, height: 11.5)
            let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 2.8, yRadius: 2.8)

            switch style {
            case .outline:
                drawColor.setStroke()
                bodyPath.lineWidth = 1.25
                bodyPath.stroke()
                drawColor.withAlphaComponent(0.08).setFill()
                bodyPath.fill()

            case .filled:
                drawColor.setFill()
                bodyPath.fill()
            }

            // Pins (4 top, 4 bottom)
            drawColor.setFill()
            let pinWidth: CGFloat = style == .outline ? 1.2 : 1.5
            let pinHeight: CGFloat = style == .outline ? 1.7 : 1.9
            let pinCount = 4
            let usableWidth = bodyRect.width - 7
            let step = usableWidth / CGFloat(pinCount - 1)

            for i in 0..<pinCount {
                let x = bodyRect.minX + 3.5 + CGFloat(i) * step - pinWidth / 2
                let topPin = NSRect(x: x, y: bodyRect.maxY + 0.3, width: pinWidth, height: pinHeight)
                let bottomPin = NSRect(x: x, y: bodyRect.minY - pinHeight - 0.3, width: pinWidth, height: pinHeight)
                NSBezierPath(roundedRect: topPin, xRadius: 0.5, yRadius: 0.5).fill()
                NSBezierPath(roundedRect: bottomPin, xRadius: 0.5, yRadius: 0.5).fill()
            }

            // Percentage text
            let fontSize: CGFloat = clamped >= 100 ? 7.6 : 8.8
            let baseFont = NSFont.systemFont(
                ofSize: fontSize,
                weight: style == .outline ? .semibold : .bold
            )
            let font: NSFont
            if let rounded = baseFont.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: rounded, size: fontSize) ?? baseFont
            } else {
                font = baseFont
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style == .outline ? drawColor : NSColor.black
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attrString.size()
            let textOrigin = NSPoint(
                x: bodyRect.midX - textSize.width / 2,
                y: bodyRect.midY - textSize.height / 2 + 0.25
            )

            if style == .filled {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                attrString.draw(at: textOrigin)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                attrString.draw(at: textOrigin)
            }

            return true
        }

        image.isTemplate = isTemplate
        return image
    }
}
