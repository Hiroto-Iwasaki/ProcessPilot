import SwiftUI
import AppKit

struct LiquidGlassBackgroundView: View, Equatable {
    static func == (lhs: LiquidGlassBackgroundView, rhs: LiquidGlassBackgroundView) -> Bool {
        true
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.2),
                    Color.accentColor.opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.85, y: 0.05),
                startRadius: 48,
                endRadius: 460
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.16),
                    Color.cyan.opacity(0.06),
                    .clear
                ],
                center: UnitPoint(x: 0.1, y: 0.95),
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            // Keep inner content within the same rounded shape as the glass panel.
            .clipShape(panelShape)
            .background(
                panelShape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        panelShape
                            .fill(tint)
                    )
                    .overlay(
                        panelShape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.42),
                                        Color.white.opacity(0.1),
                                        Color.black.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
            )
    }
}

extension View {
    func liquidGlassPanel(
        cornerRadius: CGFloat = 16,
        tint: Color = Color.white.opacity(0.06)
    ) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}
