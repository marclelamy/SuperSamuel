import Foundation

enum STTSessionError: LocalizedError {
    case notStarted
    case brokerError(String)
    case invalidBrokerResponse
    case serverError(String)
    case socketClosed

    var errorDescription: String? {
        switch self {
        case .notStarted:
            return "STT session is not started."
        case .brokerError(let message):
            return "Token broker error: \(message)"
        case .invalidBrokerResponse:
            return "Invalid token broker response."
        case .serverError(let message):
            return "STT server error: \(message)"
        case .socketClosed:
            return "STT websocket closed unexpectedly."
        }
    }
}

private struct BrokerTokenResponse: Decodable {
    let token: String
    let expires_in: Int
}

private struct BrokerErrorResponse: Decodable {
    let error: String?
    let message: String?
}

private struct STTResponse: Decodable {
    let tokens: [STTToken]?
    let finished: Bool?
    let error_code: String?
    let error_message: String?
}

@MainActor
final class STTSessionService {
    private let brokerURL: URL
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let assembler = TranscriptAssembler()

    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var hasFinished = false
    private var terminalError: Error?

    var onSnapshot: ((TranscriptSnapshot) -> Void)?

    init(brokerURL: URL, urlSession: URLSession = .shared) {
        self.brokerURL = brokerURL
        self.urlSession = urlSession
    }

    deinit {
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
    }

    func start() async throws {
        let token = try await fetchToken()
        let wsURL = URL(string: "wss://api.sinusoidlabs.com/v1/stt/stream")!
        let socket = urlSession.webSocketTask(with: wsURL)
        socketTask = socket
        socket.resume()

        let firstPayload: [String: Any] = [
            "token": token,
            "model": "spark",
            "audio_format": "pcm_s16le",
            "sample_rate": 16_000,
            "num_channels": 1
        ]

        let data = try JSONSerialization.data(withJSONObject: firstPayload, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw STTSessionError.invalidBrokerResponse
        }

        try await socket.send(.string(json))
        startReceiveLoop()
    }

    func sendAudioChunk(_ data: Data) {
        guard let socketTask else {
            return
        }

        Task { [weak self] in
            do {
                try await socketTask.send(.data(data))
            } catch {
                await MainActor.run {
                    self?.markTerminalError(error)
                }
            }
        }
    }

    func finishAndWait(timeoutMs: Int) async throws -> String {
        guard let socketTask else {
            throw STTSessionError.notStarted
        }

        try await socketTask.send(.string(""))

        let deadline = Date().addingTimeInterval(Double(max(timeoutMs, 300)) / 1000)
        while Date() < deadline {
            if let terminalError {
                throw terminalError
            }

            if hasFinished {
                return assembler.currentCombined().trimmingCharacters(in: .whitespacesAndNewlines)
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Tail timeout elapsed: return best effort transcript.
        return assembler.currentCombined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        receiveTask?.cancel()
        receiveTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
    }

    private func fetchToken() async throws -> String {
        var request = URLRequest(url: brokerURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw STTSessionError.invalidBrokerResponse
        }

        if !(200...299).contains(http.statusCode) {
            let brokerError = try? decoder.decode(BrokerErrorResponse.self, from: data)
            let message = brokerError?.message ?? brokerError?.error ?? "HTTP \(http.statusCode)"
            throw STTSessionError.brokerError(message)
        }

        let payload = try decoder.decode(BrokerTokenResponse.self, from: data)
        guard !payload.token.isEmpty else {
            throw STTSessionError.invalidBrokerResponse
        }

        return payload.token
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self, let socket = self.socketTask else {
                return
            }

            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    try self.handleMessage(message)
                }
            } catch {
                self.markTerminalError(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) throws {
        let payloadData: Data
        switch message {
        case .data(let data):
            payloadData = data
        case .string(let text):
            payloadData = Data(text.utf8)
        @unknown default:
            throw STTSessionError.socketClosed
        }

        let response = try decoder.decode(STTResponse.self, from: payloadData)

        if let errorCode = response.error_code {
            let errorMessage = response.error_message ?? errorCode
            throw STTSessionError.serverError(errorMessage)
        }

        let snapshot = assembler.apply(
            tokens: response.tokens ?? [],
            finished: response.finished ?? false
        )

        onSnapshot?(snapshot)

        if snapshot.finished {
            hasFinished = true
        }
    }

    private func markTerminalError(_ error: Error) {
        if terminalError == nil {
            terminalError = error
        }
    }
}
