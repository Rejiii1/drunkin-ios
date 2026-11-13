import Foundation

/// Everything that arrives from another phone or from a file goes through
/// here before it is stored or shown. Strings are trimmed of control
/// characters and capped, numbers are clamped and collections are bounded.
enum Sanitize {
    static func text(_ s: String, max: Int, multiline: Bool = false) -> String {
        var view = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if multiline && scalar == "\n" { view.append(scalar); continue }
            switch scalar.properties.generalCategory {
            case .control, .surrogate, .privateUse, .unassigned: continue
            case .format where scalar.value != 0x200D: continue
            case .lineSeparator, .paragraphSeparator: continue
            default: view.append(scalar)
            }
        }
        let str = String(view)
        let trimmed = multiline ? str : str.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(max))
    }

    static func line(_ s: String, max: Int = Limits.shortText) -> String { text(s, max: max) }
    static func paragraph(_ s: String, max: Int = Limits.longText) -> String { text(s, max: max, multiline: true) }

    static func score(_ v: Int?) -> Int? {
        guard let v, (1...5).contains(v) else { return nil }
        return v
    }

    static func proof(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v > 0, v <= 200 else { return nil }
        return (v * 10).rounded() / 10
    }
}

extension Entry {
    func sanitized() -> Entry {
        var e = self
        e.score = Sanitize.score(score)
        e.notes = Sanitize.paragraph(notes)
        e.rev = max(0, min(rev, Int(Int32.max)))
        e.generation = max(0, min(generation, Int(Int32.max)))
        return e
    }
}

extension Pour {
    func sanitized() -> Pour {
        var p = self
        p.name = Sanitize.line(name, max: Limits.title)
        p.proof = Sanitize.proof(proof)
        p.descriptor = Sanitize.line(descriptor)
        p.nose = Sanitize.paragraph(nose, max: 400)
        p.palate = Sanitize.paragraph(palate, max: 400)
        p.finish = Sanitize.paragraph(finish, max: 400)
        p.trivia = Sanitize.paragraph(trivia, max: 600)
        return p
    }
}

extension Flight {
    func sanitized() -> Flight {
        var f = self
        f.title = Sanitize.line(title, max: Limits.title)
        f.intro = Sanitize.paragraph(intro, max: 1200)
        var seen = Set<UUID>()
        f.pours = pours.prefix(Limits.poursPerFlight).filter { seen.insert($0.id).inserted }.map { $0.sanitized() }
        return f
    }
}

extension TastingMenu {
    func sanitized() -> TastingMenu {
        var m = self
        m.title = Sanitize.line(title, max: Limits.title)
        m.subtitle = Sanitize.line(subtitle)
        var seenFlights = Set<UUID>()
        var seenPours = Set<UUID>()
        m.flights = flights.prefix(Limits.flights)
            .filter { seenFlights.insert($0.id).inserted }
            .map { flight in
                var f = flight.sanitized()
                f.pours = f.pours.filter { seenPours.insert($0.id).inserted }
                return f
            }
        if m.title.isEmpty { m.title = "Tasting" }
        return m
    }
}

extension Taster {
    func sanitized() -> Taster {
        var t = self
        t.name = Sanitize.line(name, max: Limits.name)
        if t.name.isEmpty { t.name = "Guest" }
        return t
    }
}

enum Sanitized {
    static func tasters(_ list: [Taster]) -> [Taster] {
        var seen = Set<UUID>()
        return list.prefix(Limits.tasters).filter { seen.insert($0.id).inserted }.map { $0.sanitized() }
    }
}
