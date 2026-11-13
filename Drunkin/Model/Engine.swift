import Foundation

/// The table rules, ported from the Deer Camp server. The host phone is the
/// authority: it holds every score and decides what each guest may see. A
/// pour reveals itself once everyone at that flight's table has scored it;
/// the host can force it either way.
struct GuestSnapshot: Codable, Equatable {
    var tastingID: UUID
    var menu: TastingMenu
    var menuRevision: Int
    var tasters: [Taster]
    var currentFlightID: UUID?
    var statuses: [UUID: PourStatus]
    var entries: [Entry]
    var you: UUID?
    var claimable: [UUID]
    var hostName: String
}

extension Tasting {
    var activeTasterIDs: [UUID] { tasters.filter(\.active).map(\.id) }

    func tableIDs(for flightID: UUID) -> [UUID] {
        let known = Set(tasters.map(\.id))
        return (attendance[flightID] ?? activeTasterIDs).filter { known.contains($0) }
    }

    // MARK: Host

    mutating func recomputeStatuses() {
        guard role == .host else { return }
        var out: [UUID: PourStatus] = [:]
        let roster = tasters.map(\.id)
        for f in menu.flights {
            let table = tableIDs(for: f.id)
            for p in f.pours {
                let scored = roster.filter { entries[Entry.key($0, p.id)]?.score != nil }
                var required = table
                for id in scored where !required.contains(id) { required.append(id) }
                let everyone = !required.isEmpty && required.allSatisfy { scored.contains($0) }
                let override = overrides[p.id]
                let revealed = override == .show || (override != .hide && everyone)
                out[p.id] = PourStatus(
                    required: required,
                    scoredBy: scored,
                    revealed: revealed,
                    override: override,
                    generation: generations[p.id] ?? 0
                )
            }
        }
        statuses = out
    }

    /// Applies edits sent by the phone bound to `tasterID`. Anything for
    /// another person, an unknown pour or a stale reset generation is ignored.
    @discardableResult
    mutating func applyIncoming(_ incoming: [Entry], as tasterID: UUID) -> Bool {
        guard role == .host, tasters.contains(where: { $0.id == tasterID }) else { return false }
        let pourIDs = Set(allPours.map(\.pour.id))
        var changed = false
        for raw in incoming.prefix(Limits.entriesPerMessage) {
            guard raw.tasterID == tasterID, pourIDs.contains(raw.pourID) else { continue }
            guard raw.generation == (generations[raw.pourID] ?? 0) else { continue }
            var e = raw.sanitized()
            let existing = entries[e.key]
            if let existing, e.rev <= existing.rev { continue }
            if statuses[e.pourID]?.revealed == true, let locked = existing?.score { e.score = locked }
            entries[e.key] = e
            changed = true
        }
        if changed {
            recomputeStatuses()
            updatedAt = Date()
        }
        return changed
    }

    mutating func setOverride(_ pourID: UUID, _ mode: RevealOverride?) {
        guard role == .host, pour(pourID) != nil else { return }
        overrides[pourID] = mode
        recomputeStatuses()
        updatedAt = Date()
    }

    mutating func setAttendance(_ flightID: UUID, _ ids: [UUID]?) {
        guard role == .host, flight(flightID) != nil else { return }
        if let ids {
            let known = Set(tasters.map(\.id))
            attendance[flightID] = ids.filter { known.contains($0) }
        } else {
            attendance[flightID] = nil
        }
        recomputeStatuses()
        updatedAt = Date()
    }

    /// Clears every score for these pours. Bumping the generation makes any
    /// phone still holding an older unsent edit drop it instead of resending.
    mutating func resetPours(_ pourIDs: [UUID]) {
        guard role == .host else { return }
        let set = Set(pourIDs)
        entries = entries.filter { !set.contains($0.value.pourID) }
        for id in set {
            overrides[id] = nil
            generations[id] = (generations[id] ?? 0) + 1
        }
        recomputeStatuses()
        updatedAt = Date()
    }

    mutating func removeTaster(_ id: UUID) {
        guard role == .host, id != me else { return }
        tasters.removeAll { $0.id == id }
        avatars[id] = nil
        entries = entries.filter { $0.value.tasterID != id }
        for i in members.indices where members[i].tasterID == id { members[i].tasterID = nil }
        for (k, v) in attendance { attendance[k] = v.filter { $0 != id } }
        recomputeStatuses()
        updatedAt = Date()
    }

    mutating func replaceMenu(_ newMenu: TastingMenu) {
        guard role == .host else { return }
        menu = newMenu.sanitized()
        menuRevision += 1
        let pourIDs = Set(allPours.map(\.pour.id))
        overrides = overrides.filter { pourIDs.contains($0.key) }
        let flightIDs = Set(menu.flights.map(\.id))
        attendance = attendance.filter { flightIDs.contains($0.key) }
        if let c = currentFlightID, !flightIDs.contains(c) { currentFlightID = nil }
        recomputeStatuses()
        updatedAt = Date()
    }

    func boundTasterIDs() -> Set<UUID> {
        var s = Set(members.compactMap(\.tasterID))
        if let me { s.insert(me) }
        return s
    }

    func claimableTasterIDs() -> [UUID] {
        let bound = boundTasterIDs()
        return tasters.map(\.id).filter { !bound.contains($0) }
    }

    /// What one guest phone is allowed to know: the menu, the roster, who has
    /// scored, every revealed score, and its own entries. Nothing else.
    func snapshot(for tasterID: UUID?) -> GuestSnapshot {
        var out: [Entry] = []
        for e in entries.values {
            guard let st = statuses[e.pourID] else { continue }
            if e.tasterID == tasterID || (st.revealed && (e.score != nil || !e.notes.isEmpty)) {
                out.append(e)
            }
        }
        return GuestSnapshot(
            tastingID: id,
            menu: menu,
            menuRevision: menuRevision,
            tasters: tasters,
            currentFlightID: currentFlightID,
            statuses: statuses,
            entries: out,
            you: tasterID,
            claimable: claimableTasterIDs(),
            hostName: name(of: me)
        )
    }

    // MARK: Both roles

    /// Records an edit to this phone's own entry. The score locks once the
    /// pour is revealed; notes and water stay editable.
    @discardableResult
    mutating func editMine(_ pourID: UUID, _ change: (inout Entry) -> Void) -> Bool {
        guard let me, role != .archive, pour(pourID) != nil else { return false }
        let generation = role == .host ? (generations[pourID] ?? 0) : (statuses[pourID]?.generation ?? 0)
        let key = Entry.key(me, pourID)
        var e = entries[key] ?? Entry(tasterID: me, pourID: pourID, generation: generation)
        let locked = statuses[pourID]?.revealed == true && e.score != nil
        let before = e.score
        change(&e)
        if locked { e.score = before }
        e.rev += 1
        e.generation = generation
        entries[key] = e.sanitized()
        if role == .host {
            recomputeStatuses()
        } else {
            dirty.insert(pourID)
        }
        updatedAt = Date()
        return true
    }

    func isLocked(_ pourID: UUID) -> Bool {
        statuses[pourID]?.revealed == true && myEntry(pourID)?.score != nil
    }

    // MARK: Guest

    func dirtyEntries() -> [Entry] {
        guard let me else { return [] }
        return dirty.compactMap { entries[Entry.key(me, $0)] }
    }

    /// Takes the host's view of the table and keeps any local edits the host
    /// hasn't seen yet. Edits from before a host reset are dropped.
    mutating func applySnapshot(_ s: GuestSnapshot) {
        guard role == .guest, s.tastingID == id else { return }
        let previousMe = me
        menu = s.menu.sanitized()
        menuRevision = s.menuRevision
        tasters = Sanitized.tasters(s.tasters)
        let known = Set(tasters.map(\.id))
        let pourIDs = Set(allPours.map(\.pour.id))
        currentFlightID = s.currentFlightID.flatMap { id in menu.flights.contains { $0.id == id } ? id : nil }
        statuses = s.statuses.filter { pourIDs.contains($0.key) }
        me = s.you.flatMap { known.contains($0) ? $0 : nil }
        hostName = Sanitize.line(s.hostName, max: Limits.name)
        claimable = s.claimable.filter { known.contains($0) }

        var next: [String: Entry] = [:]
        for raw in s.entries.prefix(Limits.tasters * Limits.flights * Limits.poursPerFlight) {
            guard known.contains(raw.tasterID), pourIDs.contains(raw.pourID) else { continue }
            let e = raw.sanitized()
            next[e.key] = e
        }

        var stillDirty = Set<UUID>()
        if let me, me == previousMe {
            for local in entries.values where local.tasterID == me {
                guard let st = statuses[local.pourID] else { continue }
                if local.generation < st.generation { continue }
                if let remote = next[local.key] {
                    if local.rev > remote.rev {
                        next[local.key] = local
                        stillDirty.insert(local.pourID)
                    }
                } else if !local.isEmpty || dirty.contains(local.pourID) {
                    next[local.key] = local
                    stillDirty.insert(local.pourID)
                }
            }
        }
        entries = next
        dirty = stillDirty
        lastSync = Date()
        updatedAt = Date()
    }

    var revealedPourIDs: Set<UUID> {
        Set(statuses.filter { $0.value.revealed }.map(\.key))
    }
}
