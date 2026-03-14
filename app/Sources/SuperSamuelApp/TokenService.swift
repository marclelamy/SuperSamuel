import Foundation

enum TokenServiceError: LocalizedError {
    case missingAPIKey
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not found. Create ~/.supersamuel/api_key with your SinusoidLabs API key."
        case .requestFailed(let message):
            return "Token request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from token server."
        }
    }
}

private struct TokenResponse: Decodable {
    let token: String
    let expires_in: Int
}

private struct ErrorResponse: Decodable {
    let detail: String?
    let error: String?
    let message: String?
}

actor TokenService {
    private let tokenURL = URL(string: "https://api.sinusoidlabs.com/v1/stt/token")!
    private let urlSession: URLSession
    private let maxRetries = 3

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchToken() async throws -> String {
        let apiKey = try loadAPIKey()
        return try await requestToken(apiKey: apiKey)
    }

    private func loadAPIKey() throws -> String {
        // Try ~/.supersamuel/api_key first
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir.appendingPathComponent(".supersamuel/api_key")

        if let key = try? String(contentsOf: configPath, encoding: .utf8) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        // Fallback: try environment variable
        if let key = ProcessInfo.processInfo.environment["SUPERSAMUEL_API_KEY"] {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        throw TokenServiceError.missingAPIKey
    }

    private func requestToken(apiKey: String) async throws -> String {
        var attempt = 0

        while true {
            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            let (data, response) = try await urlSession.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw TokenServiceError.invalidResponse
            }

            // Handle rate limiting with exponential backoff
            if http.statusCode == 429 && attempt < maxRetries {
                let backoffMs = 1000 * Int(pow(2.0, Double(attempt)))
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                continue
            }

            if !(200...299).contains(http.statusCode) {
                let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                let message = errorBody?.detail ?? errorBody?.error ?? errorBody?.message ?? "HTTP \(http.statusCode)"
                throw TokenServiceError.requestFailed(message)
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            if tokenResponse.token.isEmpty {
                throw TokenServiceError.invalidResponse
            }

            return tokenResponse.token
        }
    }
}
