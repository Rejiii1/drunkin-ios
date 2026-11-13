import Foundation
@preconcurrency import MultipeerConnectivity
import Observation

struct Toast: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var tastingID: UUID?
    var pourID: UUID?
}

@MainActor
@Observable
final class AppModel {
    private(set) var tastings: [UUID: Tasting] = [:]
    var ageConfirmed: Bool {
        didSet { defaults.set(ageConfirmed, forKey: Keys.ageConfirmed) }
    }
    var guestLink: GuestLink = .idle
    private(set) var nearbyHosts: [NearbyHost] = []
    private(set) var hostConnected: Set<UUID> = []
    private(set) var hostRunning = false
    var toast: Toast?
    /// Set when a join completes so the root view can open the tasting.
    var openRequest: UUID?
    var joinScreenOpen = false {
        didSet { refreshServices() }
    }
    private(set) var liveTastingID: UUID?
    private var isActive = true
    var saveError: String?

    let deviceID: UUID
    @ObservationIgnored let host = HostService()
    @ObservationIgnored let guest = GuestService()
    @ObservationIgnored private let store: TastingStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var guestSendWork: DispatchWorkItem?

    private enum Keys {
        static let ageConfirmed = "ageConfirmed"
        static let deviceID = "deviceID"
    }

    init(store: TastingStore = .live(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        ageConfirmed = defaults.bool(forKey: Keys.ageConfirmed)
        if let raw = defaults.string(forKey: Keys.deviceID), let id = UUID(uuidString: raw) {
            deviceID = id
        } else {
            let id = UUID()
            defaults.set(id.uuidString, forKey: Keys.deviceID)
            deviceID = id
        }
        for t in store.loadAll() { tastings[t.id] = t }
        host.model = self
        guest.model = self
    }

    var sortedTastings: [Tasting] {
        tastings.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Persistence

    private func persist(_ t: Tasting) {
        do {
            try store.save(t)
            saveError = nil
        } catch {
            saveError = "Couldn't save to this phone. Free up some storage and try again."
        }
    }

    /// Stores a tasting after a change and tells the table about it.
    func replaceTasting(_ t: Tasting) {
        let before = tastings[t.id]
        tastings[t.id] = t
        persist(t)
        announceReveals(before: before, after: t)
        if t.role == .host, host.tastingID == t.id { host.scheduleBroadcast() }
    }

    func update(_ id: UUID, _ body: (inout Tasting) -> Void) {
        guard var t = tastings[id] else { return }
        body(&t)
        replaceTasting(t)
    }

    private func announceReveals(before: Tasting?, after: Tasting) {
        guard let before, after.role != .archive, after.id == liveTastingID else { return }
        let newly = after.revealedPourIDs.subtracting(before.revealedPourIDs)
        guard let first = after.allPours.first(where: { newly.contains($0.pour.id) }) else { return }
        let stats = Results.stats(first.pour, in: first.flight, after)
        let text = newly.count == 1
            ? "\(first.pour.name) revealed · table avg \(Results.fmt(stats.avg))"
            : "\(newly.count) pours revealed · \(first.pour.name) and more"
        toast = Toast(text: text, tastingID: after.id, pourID: first.pour.id)
    }

    // MARK: Creating and removing

    func createTasting(title: String, subtitle: String, yourName: String, template: TastingTemplate) -> UUID {
        let name = Sanitize.line(yourName, max: Limits.name)
        let me = Taster(name: name.isEmpty ? "Host" : name)
        let cleanTitle = Sanitize.line(title, max: Limits.title)
        var t = Tasting(role: .host, menu: template.menu(
            title: cleanTitle.isEmpty ? "Tasting" : cleanTitle,
            subtitle: Sanitize.line(subtitle)
        ).sanitized())
        t.tasters = [me]
        t.me = me.id
        t.joinCode = Secrets.joinCode()
        t.currentFlightID = t.menu.flights.first?.id
        t.recomputeStatuses()
        replaceTasting(t)
        return t.id
    }

    func hostAgain(from t: Tasting, yourName: String) -> UUID {
        var menu = t.menu
        for f in menu.flights.indices {
            menu.flights[f].id = UUID()
            for p in menu.flights[f].pours.indices { menu.flights[f].pours[p].id = UUID() }
        }
        let id = createTasting(title: menu.title, subtitle: menu.subtitle, yourName: yourName, template: .blank)
        update(id) {
            $0.replaceMenu(menu)
            $0.currentFlightID = $0.menu.flights.first?.id
        }
        return id
    }

    func delete(_ id: UUID) {
        if host.tastingID == id { host.stop(notifyEnded: true) }
        if guest.autoRejoin == id { guest.autoRejoin = nil; guest.disconnect() }
        tastings[id] = nil
        store.delete(id)
        Keychain.remove(id.uuidString)
        if liveTastingID == id { liveTastingID = nil }
        refreshServices()
    }

    func deleteEverything() {
        host.stop(notifyEnded: true)
        guest.stop()
        tastings = [:]
        store.deleteAll()
        Keychain.removeAll()
        liveTastingID = nil
    }

    /// Guest leaves the table: keeps a read-only copy of what they've seen.
    func leave(_ id: UUID) {
        if guest.autoRejoin == id { guest.autoRejoin = nil; guest.disconnect() }
        Keychain.remove(id.uuidString)
        update(id) {
            $0.role = .archive
            $0.dirty = []
        }
        refreshServices()
    }

    /// Host closes the table: guests keep their copies, nobody can join.
    func endHosting(_ id: UUID) {
        if host.tastingID == id { host.stop(notifyEnded: true) }
        update(id) {
            $0.role = .archive
            $0.members = []
            $0.joinCode = nil
        }
        refreshServices()
    }

    // MARK: Lifecycle

    func open(_ id: UUID?) {
        liveTastingID = id
        refreshServices()
    }

    func setActive(_ active: Bool) {
        isActive = active
        refreshServices()
    }

    func refreshServices() {
        let live = liveTastingID.flatMap { tastings[$0] }
        if isActive, let live, live.role == .host {
            host.start(live)
        } else if host.isRunning {
            host.stop()
        }
        let wantsGuest = isActive && (joinScreenOpen || live?.role == .guest)
        if wantsGuest {
            guest.startBrowsing()
            guest.autoRejoin = live?.role == .guest ? live?.id : nil
        } else {
            guest.autoRejoin = nil
            guest.stop()
        }
        hostStatusChanged()
    }

    func hostStatusChanged() {
        hostConnected = host.connectedDeviceIDs
        hostRunning = host.isRunning
    }

    func nearbyChanged() { nearbyHosts = guest.nearby }

    func hostNotice(_ text: String) { toast = Toast(text: text) }

    // MARK: Scoring (both roles)

    func edit(_ tastingID: UUID, pour: UUID, _ change: (inout Entry) -> Void) {
        guard var t = tastings[tastingID], t.editMine(pour, change) else { return }
        replaceTasting(t)
        if t.role == .guest { scheduleGuestSend(tastingID) }
    }

    private func scheduleGuestSend(_ id: UUID) {
        guestSendWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushGuest(id) }
        }
        guestSendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func flushGuest(_ id: UUID) {
        guard guest.connectedTastingID == id, let t = tastings[id], t.role == .guest else { return }
        let pending = t.dirtyEntries()
        if !pending.isEmpty { guest.send(.entries(pending)) }
    }

    func isConnected(_ t: Tasting) -> Bool {
        switch t.role {
        case .host: host.tastingID == t.id && hostRunning
        case .guest: guestLink == .connected(t.id)
        case .archive: false
        }
    }

    // MARK: Guest side

    func claim(_ tastingID: UUID, taster: UUID) {
        guard guest.connectedTastingID == tastingID else { return }
        guest.send(.claim(taster))
    }

    func claimNew(_ tastingID: UUID, name: String) {
        let clean = Sanitize.line(name, max: Limits.name)
        guard guest.connectedTastingID == tastingID, !clean.isEmpty else { return }
        guest.send(.newTaster(clean))
    }

    func setMyPhoto(_ tastingID: UUID, imageData: Data) -> Bool {
        guard let jpeg = ImageTools.avatarJPEG(from: imageData), let t = tastings[tastingID], let me = t.me else { return false }
        switch t.role {
        case .host:
            update(tastingID) { $0.avatars[me] = jpeg }
            host.broadcast(.avatars([me: jpeg]))
        case .guest:
            update(tastingID) { $0.avatars[me] = jpeg }
            guest.send(.avatar(jpeg))
        case .archive:
            return false
        }
        return true
    }

    func guestHandle(_ msg: HostMessage, tastingID: UUID) {
        switch msg {
        case .welcome(let w):
            guard w.snapshot.tastingID == tastingID else { return }
            if let existing = tastings[tastingID], existing.role == .host { return }
            if let token = w.token, token.count <= 128 { Keychain.set(token, for: tastingID.uuidString) }
            var t = tastings[tastingID] ?? Tasting(id: tastingID, role: .guest, menu: w.snapshot.menu)
            if t.role == .archive { t.role = .guest }
            t.applySnapshot(w.snapshot)
            t.avatars = cleanAvatars(w.avatars, roster: Set(t.tasters.map(\.id)))
            replaceTasting(t)
            if joinScreenOpen { openRequest = tastingID }
            if liveTastingID != tastingID { liveTastingID = tastingID }
            guest.autoRejoin = tastingID
            flushGuest(tastingID)
        case .snapshot(let s):
            guard s.tastingID == tastingID, var t = tastings[tastingID], t.role == .guest else { return }
            t.applySnapshot(s)
            replaceTasting(t)
            if !t.dirty.isEmpty { scheduleGuestSend(tastingID) }
        case .avatars(let a):
            guard var t = tastings[tastingID], t.role == .guest else { return }
            for (k, v) in cleanAvatars(a, roster: Set(t.tasters.map(\.id))) { t.avatars[k] = v }
            replaceTasting(t)
        case .notice(let text):
            toast = Toast(text: Sanitize.line(text, max: 200))
        case .ended:
            guest.autoRejoin = nil
            guest.disconnect()
            Keychain.remove(tastingID.uuidString)
            update(tastingID) { $0.role = .archive }
            toast = Toast(text: "The host closed this tasting. Your copy is saved.")
            refreshServices()
        }
    }

    func guestDisconnected(_ tastingID: UUID) {}

    private func cleanAvatars(_ a: [UUID: Data], roster: Set<UUID>) -> [UUID: Data] {
        var out: [UUID: Data] = [:]
        for (k, v) in a where roster.contains(k) && v.count <= Limits.avatarBytes * 2 {
            if let clean = ImageTools.avatarJPEG(from: v, maxBytes: Limits.avatarBytes * 2) { out[k] = clean }
        }
        return out
    }

    // MARK: Host side

    func hostHandle(_ msg: GuestMessage, deviceID: UUID, peer: MCPeerID) {
        guard let id = host.tastingID, var t = tastings[id], t.role == .host,
              let mi = t.members.firstIndex(where: { $0.deviceID == deviceID }) else { return }
        let bound = t.members[mi].tasterID

        switch msg {
        case .entries(let list):
            guard let bound else { return }
            if t.applyIncoming(list, as: bound) {
                replaceTasting(t)
            } else {
                host.send(.snapshot(t.snapshot(for: bound)), to: peer)
            }
        case .claim(let tasterID):
            guard t.claimableTasterIDs().contains(tasterID) || bound == tasterID else {
                host.send(.notice("Someone else already joined as \(t.name(of: tasterID))."), to: peer)
                host.send(.snapshot(t.snapshot(for: bound)), to: peer)
                return
            }
            t.members[mi].tasterID = tasterID
            replaceTasting(t)
        case .newTaster(let raw):
            let name = Sanitize.line(raw, max: Limits.name)
            guard !name.isEmpty else { return }
            if let existing = t.tasters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                guard t.claimableTasterIDs().contains(existing.id) else {
                    host.send(.notice("Someone already joined as \(existing.name). Try a different name."), to: peer)
                    return
                }
                t.members[mi].tasterID = existing.id
            } else {
                guard t.tasters.count < Limits.tasters else {
                    host.send(.notice("This table is full."), to: peer)
                    return
                }
                let new = Taster(name: name)
                t.tasters.append(new)
                t.members[mi].tasterID = new.id
                t.recomputeStatuses()
            }
            replaceTasting(t)
        case .avatar(let data):
            guard let bound, let jpeg = ImageTools.avatarJPEG(from: data, maxBytes: Limits.avatarBytes * 2) else { return }
            t.avatars[bound] = jpeg
            replaceTasting(t)
            host.broadcast(.avatars([bound: jpeg]))
        }
    }

    func setHostSeat(_ tastingID: UUID, taster: UUID) {
        update(tastingID) { t in
            guard t.role == .host, t.tasters.contains(where: { $0.id == taster }) else { return }
            for i in t.members.indices where t.members[i].tasterID == taster { t.members[i].tasterID = nil }
            t.me = taster
            t.recomputeStatuses()
        }
    }

    func addHostSeat(_ tastingID: UUID, name: String) {
        let clean = Sanitize.line(name, max: Limits.name)
        guard !clean.isEmpty else { return }
        update(tastingID) { t in
            guard t.role == .host, t.tasters.count < Limits.tasters else { return }
            let me = Taster(name: clean)
            t.tasters.append(me)
            t.me = me.id
            t.recomputeStatuses()
        }
    }

    func addTaster(_ tastingID: UUID, name: String) {
        let clean = Sanitize.line(name, max: Limits.name)
        guard !clean.isEmpty else { return }
        update(tastingID) { t in
            guard t.role == .host, t.tasters.count < Limits.tasters,
                  !t.tasters.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
            t.tasters.append(Taster(name: clean))
            t.recomputeStatuses()
        }
    }

    func unlinkPhone(_ tastingID: UUID, deviceID: UUID) {
        update(tastingID) { t in t.members.removeAll { $0.deviceID == deviceID } }
        for peer in host.peers(for: deviceID) { host.send(.ended, to: peer) }
    }

    func newJoinCode(_ tastingID: UUID) {
        update(tastingID) { $0.joinCode = Secrets.joinCode() }
    }

    // MARK: Files

    func exportResults(_ id: UUID) throws -> URL {
        guard let t = tastings[id] else { throw ImportError.unreadable }
        return try TastingFile.results(of: t).write()
    }

    /// Moves hosting to another phone. This phone becomes a guest seated as
    /// the same person, with its own rejoin token already in the file.
    func handOffHosting(_ id: UUID) throws -> URL {
        guard var t = tastings[id], t.role == .host, let me = t.me else { throw ImportError.unreadable }
        let token = Secrets.token()
        t.members.removeAll { $0.deviceID == deviceID }
        t.members.append(Member(deviceID: deviceID, tokenHash: Secrets.sha256(token), tasterID: me))
        let url = try TastingFile.handoff(of: t).write()
        host.stop(notifyEnded: false)
        Keychain.set(token, for: id.uuidString)
        t.role = .guest
        t.members = []
        t.joinCode = nil
        t.hostName = nil
        replaceTasting(t)
        refreshServices()
        return url
    }

    @discardableResult
    func importFile(_ url: URL) throws -> UUID {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Limits.fileBytes else { throw ImportError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        defer {
            if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        return try importData(data)
    }

    @discardableResult
    func importData(_ data: Data) throws -> UUID {
        let file = try TastingFile.decode(data)
        var incoming = file.tasting
        let existing = tastings[incoming.id]
        if existing?.role == .host { throw ImportError.alreadyHosting }

        switch file.kind {
        case .results:
            incoming.role = .archive
            if let existing {
                incoming.me = existing.me
                if let me = existing.me {
                    for e in existing.entries.values where e.tasterID == me && incoming.entries[e.key] == nil {
                        incoming.entries[e.key] = e
                    }
                }
            }
        case .handoff:
            incoming.role = .host
            let seat = incoming.members.first { $0.deviceID == deviceID }?.tasterID ?? existing?.me
            incoming.members.removeAll { $0.deviceID == deviceID }
            if let seat, incoming.tasters.contains(where: { $0.id == seat }) {
                for i in incoming.members.indices where incoming.members[i].tasterID == seat { incoming.members[i].tasterID = nil }
                incoming.me = seat
            } else {
                incoming.me = nil
            }
            if let existing, existing.role == .guest, let me = existing.me {
                for e in existing.entries.values where e.tasterID == me {
                    if let have = incoming.entries[e.key], have.rev >= e.rev { continue }
                    if e.generation == (incoming.generations[e.pourID] ?? 0) { incoming.entries[e.key] = e }
                }
            }
            incoming.recomputeStatuses()
            Keychain.remove(incoming.id.uuidString)
            if guest.autoRejoin == incoming.id { guest.autoRejoin = nil; guest.disconnect() }
        }
        replaceTasting(incoming)
        refreshServices()
        return incoming.id
    }
}
