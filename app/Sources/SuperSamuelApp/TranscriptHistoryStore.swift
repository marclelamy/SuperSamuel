import Foundation

struct TranscriptHistoryItem: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let text: String
}

@MainActor
final class TranscriptHistoryStore {
    private let fileManager: FileManager
    private let historyDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let root = rootDirectory ?? applicationSupport
            .appendingPathComponent("SuperSamuel", isDirectory: true)
        self.historyDirectory = root
            .appendingPathComponent("Transcript History", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(
        recordingID: UUID,
        createdAt: Date,
        text: String
    ) throws -> TranscriptHistoryItem {
        try ensureDirectory()

        let item = TranscriptHistoryItem(
            id: recordingID,
            createdAt: createdAt,
            text: text
        )
        try encoder.encode(item).write(
            to: fileURL(for: recordingID),
            options: .atomic
        )
        return item
    }

    func recent(limit: Int = 30) throws -> [TranscriptHistoryItem] {
        try ensureDirectory()

        return try fileManager.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            try? decoder.decode(
                TranscriptHistoryItem.self,
                from: Data(contentsOf: url)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(limit)
        .map { $0 }
    }

    func item(id: UUID) throws -> TranscriptHistoryItem? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try decoder.decode(
            TranscriptHistoryItem.self,
            from: Data(contentsOf: url)
        )
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: historyDirectory.path) else {
            return
        }

        let files = try fileManager.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files where file.pathExtension == "json" {
            try fileManager.removeItem(at: file)
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: historyDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: historyDirectory.path
        )
    }

    private func fileURL(for id: UUID) -> URL {
        historyDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("json")
    }
}
