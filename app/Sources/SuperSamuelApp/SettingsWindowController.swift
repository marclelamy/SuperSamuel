import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        let window = ensureWindow()
        let host = NSHostingView(rootView: SettingsView(settings: settings))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = makeLiquidGlassHost(
            content: host,
            cornerRadius: 24
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperSamuel Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        return window
    }
}

private struct SettingsView: View {
    private let settings: SettingsStore

    @State private var openRouterAPIKey: String
    @State private var cleanupModel: String
    @State private var cleanupPrompt: String
    @State private var cleanupEnabledByDefault: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _openRouterAPIKey = State(initialValue: settings.openRouterAPIKey)
        _cleanupModel = State(initialValue: settings.cleanupModel)
        _cleanupPrompt = State(initialValue: settings.cleanupPrompt)
        _cleanupEnabledByDefault = State(initialValue: settings.cleanupEnabledByDefault)
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                settingsContent
            }
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))

                Text("Changes save automatically and apply to the next recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                section(
                    title: "OpenRouter",
                    description: "The same API key is used for Whisper transcription and optional transcript cleanup."
                ) {
                    SecureField("sk-or-v1-...", text: apiKeyBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .liquidGlassSurface(cornerRadius: 11)

                    Text("Stored in your macOS Keychain.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                section(
                    title: "Transcription",
                    description: "Recordings are captured locally as durable 16 kHz mono WAV chunks, then sent after you stop recording."
                ) {
                    labeledValue(
                        label: "Model",
                        value: OpenRouterService.transcriptionModel
                    )
                }

                section(
                    title: "AI Cleanup",
                    description: "After transcription, optionally rewrite spoken dictation into clean text without changing its meaning."
                ) {
                    Toggle(
                        "Enable cleanup by default",
                        isOn: cleanupEnabledByDefaultBinding
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cleanup model or preset")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Enter an OpenRouter model ID or a preset such as @preset/my-dictation-cleanup.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        TextField("@preset/my-dictation-cleanup", text: cleanupModelBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .liquidGlassSurface(cornerRadius: 11)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Cleanup instructions")
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            Button("Restore Default") {
                                cleanupPrompt = OpenRouterService.defaultCleanupInstruction
                                settings.cleanupPrompt = OpenRouterService.defaultCleanupInstruction
                            }
                            .liquidGlassButton(
                                tint: Color.accentColor.opacity(0.78)
                            )
                            .disabled(cleanupPrompt == OpenRouterService.defaultCleanupInstruction)
                        }

                        TextEditor(text: cleanupPromptBinding)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 170)
                            .liquidGlassSurface(cornerRadius: 12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 650)
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { openRouterAPIKey },
            set: { value in
                openRouterAPIKey = value
                settings.openRouterAPIKey = value
            }
        )
    }

    private var cleanupModelBinding: Binding<String> {
        Binding(
            get: { cleanupModel },
            set: { value in
                cleanupModel = value
                settings.cleanupModel = value
            }
        )
    }

    private var cleanupPromptBinding: Binding<String> {
        Binding(
            get: { cleanupPrompt },
            set: { value in
                cleanupPrompt = value
                settings.cleanupPrompt = value
            }
        )
    }

    private var cleanupEnabledByDefaultBinding: Binding<Bool> {
        Binding(
            get: { cleanupEnabledByDefault },
            set: { value in
                cleanupEnabledByDefault = value
                settings.cleanupEnabledByDefault = value
            }
        )
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func labeledValue(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: 11)
    }
}
