import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let drunkinTasting = UTType(exportedAs: "fun.dunkin.drunkin.tasting")
}

/// A tasting as a file anyone can AirDrop or text.
/// - `results`: menu, roster, photos and revealed scores only. Safe to send
///   to anyone; hidden scores never go in it.
/// - `handoff`: the host's full copy, used to move hosting to another phone.
struct TastingFile: Codable {
    enum Kind: String, Codable { case results, handoff }

    static let format = "fun.dunkin.drunkin.tasting"
    static let currentVersion = 1

    var format = TastingFile.format
    var version = TastingFile.currentVersion
    var kind: Kind
    var exportedAt = Date()
    var tasting: Tasting

    static func results(of t: Tasting) -> TastingFile {
        var c = t
        c.role = .archive
        c.entries = c.entries.filter { _, e in
            c.statuses[e.pourID]?.revealed == true && (e.score != nil || !e.notes.isEmpty)
        }
        c.members = []
        c.joinCode = nil
        c.dirty = []
        c.me = nil
        c.attendance = [:]
        c.hostName = t.isHost ? t.name(of: t.me) : t.hostName
        return TastingFile(kind: .results, tasting: c)
    }

    static func handoff(of t: Tasting) -> TastingFile {
        var c = t
        c.dirty = []
        c.hostName = nil
        return TastingFile(kind: .handoff, tasting: c)
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }

    static func decode(_ data: Data) throws -> TastingFile {
        guard data.count <= Limits.fileBytes else { throw ImportError.tooLarge }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let file = try? dec.decode(TastingFile.self, from: data) else { throw ImportError.notATasting }
        guard file.format == TastingFile.format else { throw ImportError.notATasting }
        guard file.version <= TastingFile.currentVersion else { throw ImportError.newerVersion }
        var f = file
        f.tasting = file.tasting.sanitizedImport(kind: file.kind)
        return f
    }

    func write(to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let base = Sanitize.line(tasting.menu.title, max: 40)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let suffix = kind == .handoff ? " (hosting)" : ""
        let name = (base.isEmpty ? "Tasting" : base) + suffix
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("drunkin")
        try encoded().write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

enum ImportError: LocalizedError, Equatable {
    case tooLarge, notATasting, newerVersion, alreadyHosting, unreadable

    var errorDescription: String? {
        switch self {
        case .tooLarge: "That file is too big to be a Drunkin tasting."
        case .notATasting: "That file isn't a Drunkin tasting."
        case .newerVersion: "That tasting was made with a newer version of Drunkin. Update the app and try again."
        case .alreadyHosting: "You're already hosting this tasting on this phone."
        case .unreadable: "Couldn't open that file."
        }
    }
}

extension Tasting {
    /// Rebuilds a tasting from an untrusted file: every string, number,
    /// photo and reference is checked; anything that doesn't fit is dropped.
    func sanitizedImport(kind: TastingFile.Kind) -> Tasting {
        var t = Tasting(id: id, role: kind == .handoff ? .host : .archive, menu: menu.sanitized())
        t.menuRevision = max(0, min(menuRevision, Int(Int32.max)))
        t.tasters = Sanitized.tasters(tasters)
        let tasterIDs = Set(t.tasters.map(\.id))
        let pourIDs = Set(t.allPours.map(\.pour.id))
        let flightIDs = Set(t.menu.flights.map(\.id))

        for (id, data) in avatars where tasterIDs.contains(id) {
            if let clean = ImageTools.avatarJPEG(from: data, maxBytes: Limits.avatarBytes * 2) { t.avatars[id] = clean }
        }
        t.currentFlightID = currentFlightID.flatMap { flightIDs.contains($0) ? $0 : nil }
        for (fid, ids) in attendance where flightIDs.contains(fid) {
            t.attendance[fid] = Array(ids.filter { tasterIDs.contains($0) }.prefix(Limits.tasters))
        }
        t.overrides = overrides.filter { pourIDs.contains($0.key) }
        t.generations = generations.filter { pourIDs.contains($0.key) }.mapValues { max(0, min($0, Int(Int32.max))) }
        for e in entries.values where tasterIDs.contains(e.tasterID) && pourIDs.contains(e.pourID) {
            let clean = e.sanitized()
            t.entries[clean.key] = clean
        }
        t.statuses = statuses.filter { pourIDs.contains($0.key) }.mapValues { s in
            PourStatus(
                required: s.required.filter { tasterIDs.contains($0) },
                scoredBy: s.scoredBy.filter { tasterIDs.contains($0) },
                revealed: s.revealed,
                override: s.override,
                generation: max(0, min(s.generation, Int(Int32.max)))
            )
        }
        t.me = nil
        t.hostName = hostName.map { Sanitize.line($0, max: Limits.name) }
        t.createdAt = createdAt
        t.updatedAt = Date()

        if kind == .handoff {
            t.members = Array(members.filter { m in
                m.tokenHash.count == 64 && m.tokenHash.allSatisfy(\.isHexDigit)
            }.prefix(64)).map { m in
                var m = m
                if let tid = m.tasterID, !tasterIDs.contains(tid) { m.tasterID = nil }
                return m
            }
            if let code = joinCode, code.count == 6, code.allSatisfy(\.isASCIIDigit) { t.joinCode = code } else { t.joinCode = Secrets.joinCode() }
            t.me = me.flatMap { tasterIDs.contains($0) ? $0 : nil }
            t.recomputeStatuses()
        } else {
            t.entries = t.entries.filter { _, e in t.statuses[e.pourID]?.revealed == true }
        }
        return t
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
