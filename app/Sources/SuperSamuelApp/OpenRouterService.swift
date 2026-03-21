import Foundation

struct OpenRouterModelSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let searchableText: String
}

enum OpenRouterServiceError: LocalizedError {
    case missingAPIKey
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key is missing."
        case .requestFailed(let message):
            return "OpenRouter request failed: \(message)"
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        }
    }
}

actor OpenRouterService {
    static let defaultModel = "openai/gpt-5.4-nano"
    static let defaultCleanupInstruction =
        "Rewrite the raw transcript into clean written dictation while preserving all meaning and technical details. Remove filler words such as um, uh, like when used as filler, you know, repeated words, false starts, self-corrections, stutters, and speech artifacts. Keep the same intent, facts, uncertainty, and level of detail. Do not summarize, shorten for brevity, add new facts, or change any meaning. Return only the cleaned transcript."

    private let chatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchModels() async throws -> [OpenRouterModelSummary] {
        let (data, response) = try await urlSession.data(from: modelsURL)
        try validate(response: response, data: data)

        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawModels = payload["data"] as? [Any]
        else {
            throw OpenRouterServiceError.invalidResponse
        }

        let models = rawModels.compactMap { rawModel -> OpenRouterModelSummary? in
            guard
                let dictionary = rawModel as? [String: Any],
                let id = dictionary["id"] as? String,
                !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            let name = (dictionary["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = (dictionary["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let searchableText = buildSearchableText(from: rawModel, fallback: [id, name, description].joined(separator: "\n"))

            return OpenRouterModelSummary(
                id: id,
                displayName: name.isEmpty ? id : name,
                description: description,
                searchableText: searchableText
            )
        }

        return models.sorted {
            let lhsName = $0.displayName.localizedLowercase
            let rhsName = $1.displayName.localizedLowercase
            if lhsName == rhsName {
                return $0.id.localizedLowercase < $1.id.localizedLowercase
            }
            return lhsName < rhsName
        }
    }

    func cleanupTranscript(
        apiKey: String,
        model: String,
        rewriteInstruction: String,
        rawTranscript: String
    ) async throws -> String {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw OpenRouterServiceError.missingAPIKey
        }

        let trimmedTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw OpenRouterServiceError.invalidResponse
        }

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let payload: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultModel : model,
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You convert messy spoken dictation into clean written text.
                    Treat the raw transcript as the source of truth, but rewrite it into natural, readable sentence-by-sentence dictation.
                    Remove filler words and speech artifacts such as "um", "uh", "like" when used as filler, "you know", repeated words, false starts, self-corrections, stutters, and obvious recognition noise.
                    Preserve all concrete meaning, technical details, intent, uncertainty, and important qualifiers.
                    Do not summarize, shorten for brevity, add new facts, answer the transcript, or change the meaning.
                    Return only the cleaned transcript.
                    """
                ],
                [
                    "role": "user",
                    "content": """
                    Raw transcript to rewrite:
                    \(trimmedTranscript)

                    Rewrite rules:
                    \(rewriteInstruction)
                    """
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        guard
            let payloadObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = payloadObject["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"]
        else {
            throw OpenRouterServiceError.invalidResponse
        }

        let text = extractText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenRouterServiceError.invalidResponse
        }

        return text
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenRouterServiceError.requestFailed(message)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if
            let error = payload["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        {
            return message
        }

        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private func extractText(from content: Any) -> String {
        if let text = content as? String {
            return text
        }

        if let parts = content as? [[String: Any]] {
            return parts
                .compactMap { part -> String? in
                    if let text = part["text"] as? String {
                        return text
                    }
                    return nil
                }
                .joined(separator: "\n")
        }

        return ""
    }

    private func buildSearchableText(from rawModel: Any, fallback: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: rawModel, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return fallback.localizedLowercase
        }

        return text.localizedLowercase
    }
}
