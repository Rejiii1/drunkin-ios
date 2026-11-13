import Foundation

enum Limits {
    static let name = 40
    static let title = 80
    static let shortText = 160
    static let longText = 2000
    static let flights = 30
    static let poursPerFlight = 30
    static let tasters = 40
    static let avatarBytes = 400_000
    static let avatarPixels = 320
    static let messageBytes = 8_000_000
    static let fileBytes = 30_000_000
    static let entriesPerMessage = 2_000
}

struct Pour: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var proof: Double?
    var descriptor = ""
    var nose = ""
    var palate = ""
    var finish = ""
    var trivia = ""
}

struct Flight: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var intro = ""
    var pours: [Pour] = []
}

struct TastingMenu: Codable, Hashable {
    var title = ""
    var subtitle = ""
    var flights: [Flight] = []
}

struct Taster: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var active = true
}

/// One person's score for one pour. Each person only ever writes their own
/// entries, so conflicts are resolved by `rev` (last write wins). `generation`
/// is the pour's reset counter at the time of the edit: edits made before a
/// host reset are dropped instead of coming back.
struct Entry: Codable, Hashable {
    var tasterID: UUID
    var pourID: UUID
    var score: Int?
    var notes = ""
    var water = false
    var rev = 0
    var generation = 0

    static func key(_ tasterID: UUID, _ pourID: UUID) -> String {
        "\(tasterID.uuidString)|\(pourID.uuidString)"
    }

    var key: String { Entry.key(tasterID, pourID) }
    var isEmpty: Bool { score == nil && notes.isEmpty && !water }
}

enum RevealOverride: String, Codable, Hashable {
    case show, hide
}

/// What everyone at the table may know about a pour. Built by the host;
/// guests only ever receive this, never other people's hidden scores.
struct PourStatus: Codable, Hashable {
    var required: [UUID]
    var scoredBy: [UUID]
    var revealed: Bool
    var override: RevealOverride?
    var generation: Int
}

enum Role: String, Codable {
    case host, guest, archive
}

/// A phone that joined a hosted tasting. Only the SHA-256 of its rejoin token
/// is kept, so a copied tasting file can't be used to impersonate it.
struct Member: Codable, Hashable {
    var deviceID: UUID
    var tokenHash: String
    var tasterID: UUID?
    var joinedAt = Date()
}

struct Tasting: Codable, Identifiable {
    var id = UUID()
    var role: Role
    var menu: TastingMenu
    var menuRevision = 0
    var tasters: [Taster] = []
    var avatars: [UUID: Data] = [:]
    var currentFlightID: UUID?
    var attendance: [UUID: [UUID]] = [:]
    var overrides: [UUID: RevealOverride] = [:]
    var generations: [UUID: Int] = [:]
    var entries: [String: Entry] = [:]
    var statuses: [UUID: PourStatus] = [:]
    var me: UUID?
    var members: [Member] = []
    var joinCode: String?
    var hostName: String?
    var claimable: [UUID] = []
    var dirty: Set<UUID> = []
    var lastSync: Date?
    var createdAt = Date()
    var updatedAt = Date()
}

extension Tasting {
    var allPours: [(flight: Flight, pour: Pour)] {
        menu.flights.flatMap { f in f.pours.map { (f, $0) } }
    }

    func pour(_ id: UUID) -> Pour? {
        for f in menu.flights { if let p = f.pours.first(where: { $0.id == id }) { return p } }
        return nil
    }

    func flight(_ id: UUID) -> Flight? { menu.flights.first { $0.id == id } }

    func flight(containing pourID: UUID) -> Flight? {
        menu.flights.first { $0.pours.contains { $0.id == pourID } }
    }

    func taster(_ id: UUID?) -> Taster? {
        guard let id else { return nil }
        return tasters.first { $0.id == id }
    }

    func name(of id: UUID?) -> String { taster(id)?.name ?? "Someone" }

    func entry(_ tasterID: UUID?, _ pourID: UUID) -> Entry? {
        guard let tasterID else { return nil }
        return entries[Entry.key(tasterID, pourID)]
    }

    func myEntry(_ pourID: UUID) -> Entry? { entry(me, pourID) }

    var isHost: Bool { role == .host }
    var isReadOnly: Bool { role == .archive || me == nil }

    var currentFlight: Flight? { currentFlightID.flatMap { flight($0) } }

    var pendingCount: Int { role == .guest ? dirty.count : 0 }
}
