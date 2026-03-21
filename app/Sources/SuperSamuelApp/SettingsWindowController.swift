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
        updateWindowContent(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperSamuel Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 720, height: 760))
        updateWindowContent(window)
        self.window = window
        return window
    }

    private func updateWindowContent(_ window: NSWindow) {
        let host = NSHostingView(rootView: SettingsView(settings: settings))
        host.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }
}

private struct SettingsView: View {
    private let settings: SettingsStore

    @State private var apiKey: String
    @State private var transcriptionContext: String
    @State private var customVocabulary: String
    @State private var openRouterAPIKey: String
    @State private var openRouterModel: String
    @State private var openRouterCleanupPrompt: String
    @State private var aiCleanupEnabledByDefault: Bool
    @State private var isModelPickerPresented = false
    @StateObject private var modelStore: OpenRouterModelPickerStore

    init(settings: SettingsStore) {
        self.settings = settings
        _apiKey = State(initialValue: settings.apiKey)
        _transcriptionContext = State(initialValue: settings.transcriptionContext)
        _customVocabulary = State(initialValue: settings.customVocabulary)
        _openRouterAPIKey = State(initialValue: settings.openRouterAPIKey)
        _openRouterModel = State(initialValue: settings.openRouterModel)
        _openRouterCleanupPrompt = State(initialValue: settings.openRouterCleanupPrompt)
        _aiCleanupEnabledByDefault = State(initialValue: settings.aiCleanupEnabledByDefault)
        _modelStore = StateObject(wrappedValue: OpenRouterModelPickerStore())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))

                Text("Changes save automatically and apply to the next recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                section(
                    title: "Sinusoid API Key",
                    description: "Used to create the temporary realtime STT token for transcription."
                ) {
                    TextField("sk-slabs-...", text: apiKeyBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                section(
                    title: "Context",
                    description: "Optional free-text context that biases transcription toward your topic or domain."
                ) {
                    multilineEditor(text: transcriptionContextBinding, minHeight: 110)
                }

                section(
                    title: "Vocabulary",
                    description: "Optional custom terms. Use commas or one term per line. Example: Vercel, Supabase, Next.js"
                ) {
                    multilineEditor(text: customVocabularyBinding, minHeight: 130)
                }

                section(
                    title: "AI Cleanup",
                    description: "Optionally send the finalized transcript to OpenRouter, clean it up without changing the meaning, and insert the cleaned result instead of the raw transcript."
                ) {
                    Toggle("Enable AI cleanup by default", isOn: aiCleanupEnabledByDefaultBinding)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenRouter API Key")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Used only for the optional post-processing cleanup step.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        TextField("sk-or-v1-...", text: openRouterAPIKeyBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cleanup Model")
                            .font(.system(size: 13, weight: .semibold))

                        Text("The picker fetches models from OpenRouter when opened. Search matches the full JSON payload for each model, not just the name.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Button(action: { isModelPickerPresented = true }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedModelDisplayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(openRouterModel)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
                            OpenRouterModelPickerView(
                                store: modelStore,
                                selectedModelID: openRouterModel,
                                onSelect: { model in
                                    openRouterModel = model.id
                                    settings.openRouterModel = model.id
                                    isModelPickerPresented = false
                                }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Cleanup Prompt")
                                .font(.system(size: 13, weight: .semibold))

                            Spacer(minLength: 12)

                            Button("Restore Default") {
                                openRouterCleanupPrompt = OpenRouterService.defaultCleanupInstruction
                                settings.openRouterCleanupPrompt = OpenRouterService.defaultCleanupInstruction
                            }
                            .disabled(openRouterCleanupPrompt == OpenRouterService.defaultCleanupInstruction)
                        }

                        Text("Extra instructions for the cleanup model. The system still preserves meaning and returns only cleaned text.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        multilineEditor(text: openRouterCleanupPromptBinding, minHeight: 180)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 720, minHeight: 760)
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                settings.apiKey = newValue
            }
        )
    }

    private var transcriptionContextBinding: Binding<String> {
        Binding(
            get: { transcriptionContext },
            set: { newValue in
                transcriptionContext = newValue
                settings.transcriptionContext = newValue
            }
        )
    }

    private var customVocabularyBinding: Binding<String> {
        Binding(
            get: { customVocabulary },
            set: { newValue in
                customVocabulary = newValue
                settings.customVocabulary = newValue
            }
        )
    }

    private var openRouterAPIKeyBinding: Binding<String> {
        Binding(
            get: { openRouterAPIKey },
            set: { newValue in
                openRouterAPIKey = newValue
                settings.openRouterAPIKey = newValue
            }
        )
    }

    private var openRouterCleanupPromptBinding: Binding<String> {
        Binding(
            get: { openRouterCleanupPrompt },
            set: { newValue in
                openRouterCleanupPrompt = newValue
                settings.openRouterCleanupPrompt = newValue
            }
        )
    }

    private var aiCleanupEnabledByDefaultBinding: Binding<Bool> {
        Binding(
            get: { aiCleanupEnabledByDefault },
            set: { newValue in
                aiCleanupEnabledByDefault = newValue
                settings.aiCleanupEnabledByDefault = newValue
            }
        )
    }

    private var selectedModelDisplayName: String {
        if let model = modelStore.models.first(where: { $0.id == openRouterModel }) {
            return model.displayName
        }

        return openRouterModel
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func multilineEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}

@MainActor
private final class OpenRouterModelPickerStore: ObservableObject {
    @Published var models: [OpenRouterModelSummary] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = OpenRouterService()

    var filteredModels: [OpenRouterModelSummary] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return models
        }

        let loweredQuery = trimmedQuery.localizedLowercase
        return models.filter { $0.searchableText.contains(loweredQuery) }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        searchText = ""

        do {
            models = try await service.fetchModels()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct OpenRouterModelPickerView: View {
    @ObservedObject var store: OpenRouterModelPickerStore
    let selectedModelID: String
    let onSelect: (OpenRouterModelSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Cleanup Model")
                .font(.system(size: 15, weight: .semibold))

            TextField("Search by id, name, description, pricing, or any JSON field", text: $store.searchText)
                .textFieldStyle(.roundedBorder)

            if store.isLoading {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView()
                    Text("Fetching models...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let errorMessage = store.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Couldn't load models.")
                        .font(.system(size: 13, weight: .semibold))

                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await store.refresh()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("\(store.filteredModels.count) models")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.filteredModels) { model in
                            Button(action: { onSelect(model) }) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.displayName)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(model.id)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        if !model.description.isEmpty {
                                            Text(model.description)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer(minLength: 12)

                                    if model.id == selectedModelID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(model.id == selectedModelID ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(16)
        .frame(width: 540, height: 460)
        .task {
            await store.refresh()
        }
    }
}
