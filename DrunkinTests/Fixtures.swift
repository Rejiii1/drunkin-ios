import Foundation
@testable import Drunkin

enum Fixture {
    static let ana = Taster(name: "Ana")
    static let ben = Taster(name: "Ben")
    static let cal = Taster(name: "Cal")

    static let pours = (1...5).map { Pour(name: "Pour \($0)", proof: Double(88 + $0 * 4)) }
    static let flight = Flight(title: "Age & Proof", intro: "Climb the ladder.", pours: pours)

    /// Hosted by Ana; Ben and Cal are at the table.
    static func hosted() -> Tasting {
        var t = Tasting(role: .host, menu: TastingMenu(title: "Test Night", subtitle: "", flights: [flight]))
        t.tasters = [ana, ben, cal]
        t.me = ana.id
        t.joinCode = "123456"
        t.currentFlightID = flight.id
        t.recomputeStatuses()
        return t
    }

    static func entry(_ who: Taster, _ pour: Int, _ score: Int?, notes: String = "", water: Bool = false, rev: Int = 1) -> Entry {
        Entry(tasterID: who.id, pourID: pours[pour].id, score: score, notes: notes, water: water, rev: rev)
    }

    /// Pours 0–2 fully scored and revealed, pour 3 only scored by Ana.
    static func scored() -> Tasting {
        var t = hosted()
        t.applyIncoming([entry(ana, 0, 3), entry(ana, 1, 4), entry(ana, 2, 4), entry(ana, 3, 5)], as: ana.id)
        t.applyIncoming([entry(ben, 0, 4), entry(ben, 1, 5), entry(ben, 2, 4)], as: ben.id)
        t.applyIncoming([entry(cal, 0, 2), entry(cal, 1, 4, notes: "leather"), entry(cal, 2, 5, notes: "licorice")], as: cal.id)
        return t
    }
}
