import AppKit
import QuartzCore

func makeLiquidGlassHost(
    content: NSView,
    cornerRadius: CGFloat
) -> NSView {
    if #available(macOS 26.0, *) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = cornerRadius
        root.layer?.masksToBounds = true

        let backdrop = LiquidGlassBackdropView(frame: root.bounds)
        backdrop.autoresizingMask = [.width, .height]
        root.addSubview(backdrop)

        let glass = NSGlassEffectView(frame: root.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.style = .clear
        glass.cornerRadius = cornerRadius
        glass.tintColor = nil
        glass.contentView = content
        root.addSubview(glass)
        return root
    }

    let fallback = NSView()
    fallback.wantsLayer = true
    fallback.layer?.cornerRadius = cornerRadius
    fallback.layer?.backgroundColor = NSColor.windowBackgroundColor
        .withAlphaComponent(0.94)
        .cgColor
    content.frame = fallback.bounds
    content.autoresizingMask = [.width, .height]
    fallback.addSubview(content)
    return fallback
}

private final class LiquidGlassBackdropView: NSView {
    private let spectrum = CAGradientLayer()
    private let warmCaustic = CAGradientLayer()
    private let coolCaustic = CAGradientLayer()
    private let highlight = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override func layout() {
        super.layout()
        let expanded = bounds.insetBy(dx: -bounds.width * 0.22, dy: -bounds.height * 0.35)
        spectrum.frame = expanded
        warmCaustic.frame = expanded
        coolCaustic.frame = expanded
        highlight.frame = bounds
    }

    private func configureLayers() {
        wantsLayer = true
        guard let layer else {
            return
        }

        spectrum.startPoint = CGPoint(x: 0, y: 0.18)
        spectrum.endPoint = CGPoint(x: 1, y: 0.82)
        spectrum.colors = [
            NSColor.systemPink.withAlphaComponent(0.20).cgColor,
            NSColor.systemOrange.withAlphaComponent(0.09).cgColor,
            NSColor.clear.cgColor,
            NSColor.systemCyan.withAlphaComponent(0.18).cgColor,
            NSColor.systemBlue.withAlphaComponent(0.08).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.19).cgColor
        ]
        spectrum.locations = [0, 0.18, 0.38, 0.61, 0.78, 1]

        configureRadial(
            warmCaustic,
            color: NSColor.systemPink.withAlphaComponent(0.24),
            start: CGPoint(x: 0.14, y: 0.76),
            end: CGPoint(x: 0.72, y: 0.16)
        )
        configureRadial(
            coolCaustic,
            color: NSColor.systemCyan.withAlphaComponent(0.22),
            start: CGPoint(x: 0.84, y: 0.24),
            end: CGPoint(x: 0.25, y: 0.88)
        )

        highlight.startPoint = CGPoint(x: 0.5, y: 1)
        highlight.endPoint = CGPoint(x: 0.5, y: 0)
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.07).cgColor
        ]
        highlight.locations = [0, 0.35, 1]

        layer.addSublayer(spectrum)
        layer.addSublayer(warmCaustic)
        layer.addSublayer(coolCaustic)
        layer.addSublayer(highlight)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        animate(
            spectrum,
            keyPath: "transform.translation.x",
            from: -20,
            to: 28,
            duration: 8.5
        )
        animate(
            warmCaustic,
            keyPath: "transform.translation.y",
            from: -14,
            to: 18,
            duration: 7.2
        )
        animate(
            coolCaustic,
            keyPath: "transform.translation.x",
            from: 18,
            to: -22,
            duration: 9.4
        )
    }

    private func configureRadial(
        _ gradient: CAGradientLayer,
        color: NSColor,
        start: CGPoint,
        end: CGPoint
    ) {
        gradient.type = .radial
        gradient.startPoint = start
        gradient.endPoint = end
        gradient.colors = [
            color.cgColor,
            color.withAlphaComponent(color.alphaComponent * 0.34).cgColor,
            NSColor.clear.cgColor
        ]
        gradient.locations = [0, 0.42, 1]
    }

    private func animate(
        _ layer: CALayer,
        keyPath: String,
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        layer.add(animation, forKey: keyPath)
    }
}
