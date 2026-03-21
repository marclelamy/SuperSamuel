import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var state: AppState
    var onStop: (() -> Void)?
    var onCopy: (() -> Void)?

    private let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private let panelWidth: CGFloat = 430
    private let controlSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SuperSamuel")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor.opacity(0.88))
                }

                Spacer(minLength: 8)

                controlButton(
                    symbol: "doc.on.doc",
                    action: onCopy,
                    foreground: .primary,
                    accent: nil,
                    prominent: false,
                    help: "Copy transcript"
                )

                controlButton(
                    symbol: "stop.fill",
                    action: onStop,
                    foreground: .white,
                    accent: .red,
                    prominent: true,
                    help: stopHelpText
                )
            }

            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(formattedDuration(state.elapsedSeconds))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            WaveformView(samples: state.waveformSamples, color: statusColor)
                .frame(height: 40)

            HStack(alignment: .center, spacing: 10) {
                Toggle(isOn: $state.aiCleanupEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI cleanup")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(cleanupDetailText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!canEditCleanupToggle)

                Spacer(minLength: 8)

                Text(state.aiCleanupEnabled ? "On" : "Off")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.aiCleanupEnabled ? Color.green.opacity(0.92) : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                    let isLastLine = index == previewLines.count - 1

                    Text(line)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: isLastLine ? 13.5 : 11.5, weight: isLastLine ? .medium : .regular))
                        .foregroundStyle(isLastLine ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: panelWidth)
        .background { cardBackground }
        .overlay { cardOverlay }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
    }

    private var previewLines: [String] {
        Array(state.transcriptPreviewLines.suffix(2))
    }

    private var cardBackground: some View {
        cardShape
            .fill(Color.black.opacity(0.96))
    }

    private var cardOverlay: some View {
        cardShape
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
    }

    private func controlButton(
        symbol: String,
        action: (() -> Void)?,
        foreground: Color,
        accent: Color?,
        prominent: Bool,
        help: String
    ) -> some View {
        Button(action: { action?() }) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: controlSize, height: controlSize)
        }
        .buttonStyle(.plain)
        .background {
            MinimalGlassSurface(shape: Circle(), accent: accent, prominent: prominent)
        }
        .clipShape(Circle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var statusLabel: String {
        switch state.phase {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .finalizing:
            return "Finalizing"
        case .inserting:
            return "AI Cleanup"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }

    private var statusColor: Color {
        switch state.phase {
        case .recording:
            return .red
        case .finalizing:
            return .blue
        case .inserting:
            return .purple
        case .error:
            return .orange
        case .done:
            return .green
        case .idle:
            return .secondary
        }
    }

    private var canEditCleanupToggle: Bool {
        state.phase == .recording
    }

    private var cleanupDetailText: String {
        switch state.phase {
        case .recording:
            return state.aiCleanupEnabled
                ? "Will rewrite the final transcript before paste."
                : "Will use the raw finalized transcript."
        case .finalizing:
            return "Locked while waiting for the final transcript."
        case .inserting:
            return "Cleaning the finalized transcript with AI."
        case .done:
            return state.aiCleanupEnabled ? "Cleanup stayed enabled for this recording." : "Cleanup stayed disabled for this recording."
        case .idle, .error:
            return state.aiCleanupEnabled ? "Enabled for the next recording." : "Disabled for the next recording."
        }
    }

    private var stopHelpText: String {
        switch state.phase {
        case .recording:
            return "Stop recording"
        case .finalizing:
            return "Cancel finalizing"
        case .inserting:
            return "Cancel AI cleanup"
        case .idle, .done, .error:
            return "Stop recording"
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        let minutes = whole / 60
        let remaining = whole % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

private struct MinimalGlassSurface<S: Shape>: View {
    let shape: S
    var accent: Color?
    var prominent = false

    var body: some View {
        ZStack {
            shape
                .fill(Color.black.opacity(prominent ? 0.84 : 0.72))

            if let accent {
                shape
                    .fill(accent.opacity(prominent ? 0.34 : 0.14))
            }

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(prominent ? 0.10 : 0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)
        }
        .overlay {
            shape
                .stroke(Color.white.opacity(prominent ? 0.18 : 0.10), lineWidth: 1)
        }
    }
}

private struct WaveformView: View {
    let samples: [CGFloat]
    let color: Color

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: barGradient(for: sample),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth(in: geometry.size.width), height: barHeight(sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barGradient(for sample: CGFloat) -> [Color] {
        let clamped = max(0, min(sample, 1))
        let accentOpacity = 0.42 + (clamped * 0.38)
        return [
            Color.white.opacity(0.96),
            Color.white.opacity(Double(accentOpacity)),
            Color.white.opacity(Double(accentOpacity * 0.88))
        ]
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        guard !samples.isEmpty else {
            return 2
        }

        let totalSpacing = CGFloat(samples.count - 1) * spacing
        let calculated = (totalWidth - totalSpacing) / CGFloat(samples.count)
        return max(1.25, calculated)
    }

    private func barHeight(_ sample: CGFloat) -> CGFloat {
        let clamped = max(0, min(sample, 1))
        let minimum: CGFloat = 3
        let shapedSample = pow(clamped, 1.7)
        return minimum + (34 * shapedSample)
    }
}
