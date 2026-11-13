import Foundation

/// Everything here is derived from revealed scores only, so results never
/// leak a hidden score, even on the host's phone.
struct PourStats: Identifiable {
    var pour: Pour
    var flight: Flight
    var revealed: Bool
    var scoredBy: [UUID]
    var required: [UUID]
    var scores: [Entry]
    var n: Int
    var avg: Double?
    var spread: Int
    var id: UUID { pour.id }
}

struct Favorite: Equatable {
    var score: Int
    var pours: [Pour]
}

struct FlightResults {
    var rows: [PourStats]
    var ranked: [PourStats]
    var winners: [PourStats]
    var favorites: [(tasterID: UUID, favorite: Favorite)]
    var disagreement: PourStats?
    var high: Entry?
    var low: Entry?
    var hiddenCount: Int
}

struct Award: Identifiable, Equatable {
    var key: String
    var title: String
    var blurb: String
    var ids: [UUID]
    var stat: String
    var id: String { key }
}

enum Results {
    static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
    static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    static func stats(_ pour: Pour, in flight: Flight, _ t: Tasting) -> PourStats {
        let st = t.statuses[pour.id]
        let revealed = st?.revealed == true
        let scores: [Entry] = revealed
            ? t.tasters.compactMap { t.entry($0.id, pour.id) }.filter { $0.score != nil }
            : []
        let vals = scores.compactMap(\.score)
        return PourStats(
            pour: pour,
            flight: flight,
            revealed: revealed,
            scoredBy: st?.scoredBy ?? [],
            required: st?.required ?? [],
            scores: scores,
            n: vals.count,
            avg: mean(vals.map(Double.init)),
            spread: vals.count >= 2 ? (vals.max()! - vals.min()!) : 0
        )
    }

    /// Notes-only entries count on a revealed pour's table too.
    static func tableEntries(_ pourID: UUID, _ t: Tasting) -> [Entry] {
        guard t.statuses[pourID]?.revealed == true else { return [] }
        return t.tasters.compactMap { t.entry($0.id, pourID) }.filter { $0.score != nil || !$0.notes.isEmpty }
    }

    private static func byAvg(_ a: PourStats, _ b: PourStats) -> Bool {
        let x = a.avg ?? 0, y = b.avg ?? 0
        if !same(x, y) { return x > y }
        return a.n > b.n
    }

    static func flight(_ flight: Flight, _ t: Tasting) -> FlightResults {
        let rows = flight.pours.map { stats($0, in: flight, t) }
        let scored = rows.filter { $0.revealed && $0.n > 0 }
        let ranked = scored.sorted(by: byAvg)
        let winners = ranked.first.map { top in ranked.filter { same($0.avg ?? 0, top.avg ?? 0) } } ?? []

        var favs: [UUID: Favorite] = [:]
        for r in scored {
            for s in r.scores {
                guard let score = s.score else { continue }
                var f = favs[s.tasterID] ?? Favorite(score: 0, pours: [])
                if score > f.score { f = Favorite(score: score, pours: [r.pour]) } else if score == f.score { f.pours.append(r.pour) }
                favs[s.tasterID] = f
            }
        }
        var favorites: [(tasterID: UUID, favorite: Favorite)] = []
        for tt in t.tasters { if let f = favs[tt.id] { favorites.append((tasterID: tt.id, favorite: f)) } }

        let disagreement = scored.filter { $0.spread > 0 }.sorted { a, b in
            a.spread != b.spread ? a.spread > b.spread : a.n > b.n
        }.first
        var high: Entry?, low: Entry?
        if let d = disagreement {
            let sorted = d.scores.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
            high = sorted.first
            low = sorted.last
        }
        return FlightResults(
            rows: rows, ranked: ranked, winners: winners, favorites: favorites,
            disagreement: disagreement, high: high, low: low,
            hiddenCount: rows.filter { !$0.revealed }.count
        )
    }

    static func leaderboard(_ t: Tasting) -> [PourStats] {
        t.menu.flights.flatMap { f in f.pours.map { stats($0, in: f, t) } }
            .filter { $0.revealed && $0.n > 0 }
            .sorted(by: byAvg)
    }

    /// Superlatives from revealed scores. Each award lists everyone tied for
    /// it; awards nobody qualifies for, or that everyone ties for, are left out.
    static func awards(_ t: Tasting) -> [Award] {
        struct Person { var given: [Double] = []; var water = 0; var notes = 0; var dev: [Double] = [] }
        var people: [UUID: Person] = [:]
        for r in leaderboard(t) {
            for s in r.scores {
                guard let score = s.score else { continue }
                var p = people[s.tasterID] ?? Person()
                p.given.append(Double(score))
                if s.water { p.water += 1 }
                if !s.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p.notes += 1 }
                if r.n >= 2, let avg = r.avg { p.dev.append(abs(Double(score) - avg)) }
                people[s.tasterID] = p
            }
        }
        let ids = t.tasters.map(\.id).filter { people[$0] != nil }
        guard ids.count >= 2 else { return [] }

        func pick(_ metric: (Person) -> Double?, min floor: Double = -.infinity, low: Bool = false) -> (ids: [UUID], value: Double)? {
            let vals = ids.compactMap { id -> (UUID, Double)? in
                guard let v = metric(people[id]!), v > floor else { return nil }
                return (id, v)
            }
            guard !vals.isEmpty else { return nil }
            let best = low ? vals.map(\.1).min()! : vals.map(\.1).max()!
            return (vals.filter { same($0.1, best) }.map(\.0), best)
        }
        let avgGiven: (Person) -> Double? = { $0.given.count >= 3 ? mean($0.given) : nil }

        var out: [Award] = []
        func add(_ key: String, _ title: String, _ blurb: String, _ r: (ids: [UUID], value: Double)?, _ fmt: (Double) -> String) {
            if let r { out.append(Award(key: key, title: title, blurb: blurb, ids: r.ids, stat: fmt(r.value))) }
        }
        let plural = { (v: Double, word: String) in "\(Int(v)) \(word)\(Int(v) == 1 ? "" : "s")" }
        add("tough", "Toughest grader", "Lowest average score handed out", pick(avgGiven, low: true)) { String(format: "%.1f avg", $0) }
        add("soft", "Softest touch", "Never met a pour they didn’t like", pick(avgGiven)) { String(format: "%.1f avg", $0) }
        add("contrarian", "Contrarian", "Furthest from the table on average", pick({ $0.dev.count >= 3 ? mean($0.dev) : nil }, min: 0)) { String(format: "±%.1f", $0) }
        add("water", "Water carrier", "Most pours cut with water", pick({ Double($0.water) }, min: 0)) { plural($0, "pour") }
        add("poet", "Poet laureate", "Most tasting notes written", pick({ Double($0.notes) }, min: 0)) { plural($0, "note") }
        return out.filter { $0.ids.count < ids.count }
    }

    static func fmtProof(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }

    static func join(_ names: [String]) -> String {
        if names.count <= 2 { return names.joined(separator: " & ") }
        return names.dropLast().joined(separator: ", ") + " & " + names.last!
    }

    static func shareText(_ flight: Flight, _ t: Tasting) -> String {
        let r = self.flight(flight, t)
        var lines = ["\(t.menu.title) · \(flight.title)", ""]
        for (i, row) in r.ranked.enumerated() { lines.append("\(i + 1). \(row.pour.name) \(fmt(row.avg))") }
        if r.hiddenCount > 0 { lines.append("(\(r.hiddenCount) still hidden)") }
        if !r.favorites.isEmpty {
            lines += ["", "Favorites:"]
            for (id, f) in r.favorites {
                lines.append("\(t.name(of: id)): \(f.pours.map(\.name).joined(separator: ", ")) (\(f.score))")
            }
        }
        if let d = r.disagreement, let hi = r.high, let lo = r.low {
            lines += ["", "Biggest debate: \(d.pour.name), \(t.name(of: hi.tasterID)) \(hi.score ?? 0) vs \(t.name(of: lo.tasterID)) \(lo.score ?? 0)"]
        }
        lines += ["", "Scored with Drunkin"]
        return lines.joined(separator: "\n")
    }
}
