import Foundation

enum SessionDocumentError: LocalizedError {
    case unsupportedVersion(Int)
    case encodeFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Unsupported session version \(v)."
        case .encodeFailed:
            return "Could not encode session."
        case .decodeFailed:
            return "Could not decode session."
        }
    }
}

enum SessionDocumentService {
    static let fileExtension = "soundplayback"

    static func save(_ session: PlaybackSession, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { throw SessionDocumentError.encodeFailed }
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> PlaybackSession {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(PlaybackSession.self, from: data) else {
            throw SessionDocumentError.decodeFailed
        }
        guard session.version == 1 else {
            throw SessionDocumentError.unsupportedVersion(session.version)
        }
        return session
    }
}
