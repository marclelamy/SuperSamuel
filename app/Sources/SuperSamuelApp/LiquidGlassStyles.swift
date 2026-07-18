import SwiftUI

extension View {
    func liquidGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }

    func liquidGlassButton(
        tint: Color? = nil,
        prominent: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassButtonModifier(
                tint: tint,
                prominent: prominent
            )
        )
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .clear.tint(tint),
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
            } else {
                content.glassEffect(
                    .clear,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
            }
        } else {
            content
                .background(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private struct LiquidGlassButtonModifier: ViewModifier {
    let tint: Color?
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                if let tint {
                    content
                        .buttonStyle(.glassProminent)
                        .tint(tint)
                } else {
                    content.buttonStyle(.glassProminent)
                }
            } else {
                if let tint {
                    content
                        .buttonStyle(.glass(.clear))
                        .tint(tint)
                } else {
                    content.buttonStyle(.glass(.clear))
                }
            }
        } else {
            content
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            (tint ?? .white)
                                .opacity(prominent ? 0.34 : 0.16)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
    }
}
