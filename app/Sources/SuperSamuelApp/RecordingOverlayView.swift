import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var state: AppState
    var onStop: (() -> Void)?
    var onCopyAndStop: (() -> Void)?
    private let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SuperSamuel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(state.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)

                // Copy & Stop button
                Button(action: { onCopyAndStop?() }) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy transcript and stop")

                // Stop button
                Button(action: { onStop?() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop recording")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(formattedDuration(state.elapsedSeconds))
                    .font(.system(.body, design: .monospaced))
            }

            WaveformView(samples: state.waveformSamples, color: statusColor)
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.transcriptPreviewLines, id: \.self) { line in
                    Text(line)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .bottomLeading)
        }
        .padding(18)
        .frame(width: 460)
        .background {
            ZStack {
                VisualEffectGlassView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .clipShape(cardShape)

                // Top highlight to mimic glass edge light.
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(cardShape)
            }
        }
        .overlay {
            cardShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.52),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var statusColor: Color {
        switch state.phase {
        case .recording:
            return .red
        case .finalizing:
            return .blue
        case .inserting:
            return .green
        case .error:
            return .orange
        case .done:
            return .green
        case .idle:
            return .secondary
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        let minutes = whole / 60
        let remaining = whole % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

private struct WaveformView: View {
    let samples: [CGFloat]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.95),
                                    color.opacity(0.55)
                                ],
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

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        guard !samples.isEmpty else {
            return 2
        }
        let spacing = CGFloat(samples.count - 1) * 3
        return max(2, (totalWidth - spacing) / CGFloat(samples.count))
    }

    private func barHeight(_ sample: CGFloat) -> CGFloat {
        let minimum: CGFloat = 6
        let maxHeight: CGFloat = 42
        return minimum + ((maxHeight - minimum) * sample)
    }
}
