import Foundation

struct STTToken: Decodable {
    let text: String
    let is_committed: Bool
}

struct TranscriptSnapshot {
    let committedText: String
    let interimText: String
    let finished: Bool

    var combinedText: String {
        committedText + interimText
    }
}

final class TranscriptAssembler {
    private(set) var committedText = ""
    private(set) var interimText = ""

    /// Tokens to filter out from the transcript (STT control tokens)
    private let filteredTokens: Set<String> = ["<|end|>", "<|endoftext|>", "<|start|>"]

    func apply(tokens: [STTToken], finished: Bool) -> TranscriptSnapshot {
        var committedParts: [String] = []
        var interimParts: [String] = []

        for token in tokens {
            // Skip control tokens
            let trimmed = token.text.trimmingCharacters(in: .whitespaces)
            if filteredTokens.contains(trimmed) {
                continue
            }

            if token.is_committed {
                committedParts.append(token.text)
            } else {
                interimParts.append(token.text)
            }
        }

        if !committedParts.isEmpty {
            committedText.append(contentsOf: committedParts.joined())
        }

        interimText = interimParts.joined()

        return TranscriptSnapshot(
            committedText: committedText,
            interimText: interimText,
            finished: finished
        )
    }

    func currentCombined() -> String {
        committedText + interimText
    }
}
