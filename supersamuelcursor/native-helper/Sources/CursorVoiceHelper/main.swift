import Foundation

struct HelperEvent: Encodable {
    let type: String
    let state: String?
    let message: String?
    let text: String?

    init(type: String, state: String? = nil, message: String? = nil, text: String? = nil) {
        self.type = type
        self.state = state
        self.message = message
        self.text = text
    }
}

actor EventEmitter {
    private let encoder = JSONEncoder()

    func send(_ event: HelperEvent) {
        guard let data = try? encoder.encode(event),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}

@MainActor
final class RecorderRuntime {
    private let permissions = PermissionsService()
    private let audioCapture = AudioCaptureService()
    private let sttSession: STTSessionService
    private let emitter: EventEmitter
    private let finalizationTailMs: Int

    init(
        apiKey: String,
        model: String,
        finalizationTailMs: Int,
        emitter: EventEmitter
    ) {
        self.sttSession = STTSessionService(
            tokenService: TokenService(apiKey: apiKey),
            model: model
        )
        self.finalizationTailMs = finalizationTailMs
        self.emitter = emitter
    }

    func start() async throws {
        try await permissions.ensureMicrophonePermission()

        audioCapture.onChunk = { [weak self] data in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.sttSession.sendAudioChunk(data)
            }
        }

        try await sttSession.start()
        try audioCapture.start()
        await emitter.send(HelperEvent(type: "state", state: "recording"))
    }

    func stop() async throws -> String {
        await emitter.send(HelperEvent(type: "state", state: "transcribing"))
        audioCapture.stop()

        let transcript = try await sttSession.finishAndWait(timeoutMs: finalizationTailMs)
        sttSession.cancel()

        await emitter.send(HelperEvent(type: "transcript", text: transcript))
        await emitter.send(HelperEvent(type: "done"))
        return transcript
    }

    func cancel() {
        audioCapture.stop()
        sttSession.cancel()
    }
}

func readRequiredEnvironment(_ key: String) throws -> String {
    let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !value.isEmpty else {
        throw NSError(domain: "CursorVoiceHelper", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Missing environment variable \(key)."
        ])
    }
    return value
}

func readOptionalIntEnvironment(_ key: String, fallback: Int) -> Int {
    let rawValue = ProcessInfo.processInfo.environment[key] ?? ""
    return Int(rawValue) ?? fallback
}

func runHelper() async -> Int32 {
    let emitter = EventEmitter()

    do {
        let apiKey = try readRequiredEnvironment("SUPERSAMUEL_SINUSOID_API_KEY")
        let model = ProcessInfo.processInfo.environment["SUPERSAMUEL_SINUSOID_MODEL"] ?? "spark"
        let tailMs = readOptionalIntEnvironment("SUPERSAMUEL_FINALIZATION_TAIL_MS", fallback: 1800)

        let runtime = await MainActor.run {
            RecorderRuntime(
                apiKey: apiKey,
                model: model,
                finalizationTailMs: tailMs,
                emitter: emitter
            )
        }

        do {
            try await runtime.start()
        } catch {
            await emitter.send(HelperEvent(type: "error", message: error.localizedDescription))
            return 1
        }

        guard let command = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines),
              command == "stop" else {
            await emitter.send(HelperEvent(type: "error", message: "Helper did not receive a stop command."))
            await MainActor.run { runtime.cancel() }
            return 1
        }

        do {
            _ = try await runtime.stop()
            return 0
        } catch {
            await emitter.send(HelperEvent(type: "error", message: error.localizedDescription))
            await MainActor.run { runtime.cancel() }
            return 1
        }
    } catch {
        await emitter.send(HelperEvent(type: "error", message: error.localizedDescription))
        return 1
    }
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1

Task {
    exitCode = await runHelper()
    semaphore.signal()
}

semaphore.wait()
Foundation.exit(exitCode)
