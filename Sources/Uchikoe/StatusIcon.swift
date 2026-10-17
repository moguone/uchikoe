import AppKit

/// メニューバーのアイコン。吹き出しの中に音の波を描く。
/// テンプレート画像にして、ライト・ダークの色合わせは macOS に任せる
enum StatusIcon {
    enum Style {
        /// 線の吹き出しと音の波
        case idle
        /// 塗りつぶした吹き出しと、くり抜いた音の波
        case recording
        /// 吹き出しの中に点を 3 つ
        case processing
    }

    private static let size = NSSize(width: 20, height: 18)

    static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(style)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Uchikoe"
        return image
    }

    private static func draw(_ style: Style) {
        let (body, tail) = bubble()
        NSColor.black.set()
        body.lineWidth = 1.5
        tail.fill()
        switch style {
        case .idle:
            body.stroke()
            for bar in bars() { bar.fill() }
        case .recording:
            body.fill()
            // 音の波を背景色でくり抜く
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for bar in bars() { bar.fill() }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        case .processing:
            body.stroke()
            for x in [6.6, 10.0, 13.4] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.2, y: 9.6 - 1.2, width: 2.4, height: 2.4)).fill()
            }
        }
    }

    /// 角の丸い吹き出しの本体と、左下のしっぽ。しっぽは塗りつぶして本体の線につなげる
    private static func bubble() -> (body: NSBezierPath, tail: NSBezierPath) {
        let rect = NSRect(x: 1.5, y: 4.5, width: 17, height: 11)
        let body = NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.6, y: rect.minY + 0.75))
        tail.line(to: NSPoint(x: 3.6, y: 1.0))
        tail.line(to: NSPoint(x: 8.6, y: rect.minY + 0.75))
        tail.close()
        return (body, tail)
    }

    /// 音の波。高さの違う縦の棒を 4 本
    private static func bars() -> [NSBezierPath] {
        let heights: [CGFloat] = [3.2, 6.4, 4.6, 2.6]
        let width: CGFloat = 1.6
        let gap: CGFloat = 1.6
        let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
        let centerY: CGFloat = 10
        return heights.enumerated().map { index, height in
            let x = 10 - total / 2 + CGFloat(index) * (width + gap)
            return NSBezierPath(
                roundedRect: NSRect(x: x, y: centerY - height / 2, width: width, height: height),
                xRadius: width / 2, yRadius: width / 2)
        }
    }
}
