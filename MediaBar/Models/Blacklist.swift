import Foundation

func blacklistKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
}

struct BlacklistedArtist: Codable, Hashable {
    enum Match: String, Codable { case individual, fullText }
    let name: String
    let match: Match
}

struct BlacklistedSong: Codable, Hashable {
    let title: String
    let artistText: String
}

enum BlacklistEntry: Hashable {
    case artist(BlacklistedArtist)
    case song(BlacklistedSong)
}

struct BlacklistDocument: Codable {
    var version = 1
    var artists: [BlacklistedArtist] = []
    var songs: [BlacklistedSong] = []

    func contains(_ entry: BlacklistEntry) -> Bool {
        switch entry {
        case .artist(let item):
            return artists.contains { $0.match == item.match && blacklistKey($0.name) == blacklistKey(item.name) }
        case .song(let item):
            return songs.contains { blacklistKey($0.title) == blacklistKey(item.title) && blacklistKey($0.artistText) == blacklistKey(item.artistText) }
        }
    }

    mutating func add(_ entry: BlacklistEntry) -> Bool {
        guard !contains(entry) else { return false }
        switch entry {
        case .artist(let artist):
            guard !blacklistKey(artist.name).isEmpty else { return false }
            artists.append(artist)
        case .song(let song):
            guard !blacklistKey(song.title).isEmpty, !blacklistKey(song.artistText).isEmpty else { return false }
            songs.append(song)
        }
        return true
    }

    mutating func remove(_ entry: BlacklistEntry) {
        switch entry {
        case .artist(let item):
            artists.removeAll { $0.match == item.match && blacklistKey($0.name) == blacklistKey(item.name) }
        case .song(let item):
            songs.removeAll { blacklistKey($0.title) == blacklistKey(item.title) && blacklistKey($0.artistText) == blacklistKey(item.artistText) }
        }
    }

    func matches(_ state: MediaState) -> Bool {
        guard state.hasMedia else { return false }
        let artistText = blacklistKey(state.artistText)
        if !artistText.isEmpty, songs.contains(where: {
            blacklistKey($0.title) == blacklistKey(state.title) && blacklistKey($0.artistText) == artistText
        }) { return true }
        return artists.contains { artist in
            let key = blacklistKey(artist.name)
            guard !key.isEmpty else { return false }
            if artist.match == .individual, !state.artistNames.isEmpty {
                return state.artistNames.contains { blacklistKey($0) == key }
            }
            // No tokenization, reordering, punctuation removal or substring matching.
            return !artistText.isEmpty && key == artistText
        }
    }
}

final class BlacklistStore {
    enum StorageError: LocalizedError {
        case unsupportedVersion, unreadableFile
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "Karaliste dosyasının sürümü desteklenmiyor."
            case .unreadableFile: return "Karaliste okunamadığı için dosya değiştirilmedi."
            }
        }
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MediaBar/blacklist.json")
    }

    let fileURL: URL
    private(set) var document = BlacklistDocument()
    private(set) var readError: String?

    init(fileURL: URL = BlacklistStore.defaultURL) {
        self.fileURL = fileURL
        reload()
    }

    func reload() {
        do {
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                document = BlacklistDocument()
                readError = nil
                return
            }
            let decoded = try JSONDecoder().decode(BlacklistDocument.self, from: data)
            guard decoded.version == 1 else { throw StorageError.unsupportedVersion }
            document = decoded
            readError = nil
        } catch {
            // Keep the original file intact; a failed read never becomes an empty save.
            readError = error.localizedDescription
        }
    }

    func add(_ entry: BlacklistEntry) throws {
        guard readError == nil else { throw StorageError.unreadableFile }
        var next = document
        guard next.add(entry) else { return }
        try save(next)
    }

    func remove(_ entry: BlacklistEntry) throws {
        guard readError == nil else { throw StorageError.unreadableFile }
        var next = document
        next.remove(entry)
        try save(next)
    }

    private func save(_ next: BlacklistDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        document = next
    }
}
