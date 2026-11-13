import XCTest
@testable import Drunkin

final class EngineTests: XCTestCase {
    typealias F = Fixture

    func testPourRevealsOnlyWhenEveryoneAtTheTableHasScored() {
        var t = F.hosted()
        let p = F.pours[0].id
        t.applyIncoming([F.entry(F.ana, 0, 3)], as: F.ana.id)
        t.applyIncoming([F.entry(F.ben, 0, 4)], as: F.ben.id)
        XCTAssertEqual(t.statuses[p]?.revealed, false)
        XCTAssertEqual(Set(t.statuses[p]!.scoredBy), [F.ana.id, F.ben.id])
        t.applyIncoming([F.entry(F.cal, 0, 2)], as: F.cal.id)
        XCTAssertEqual(t.statuses[p]?.revealed, true)
    }

    func testBenchedTasterDoesNotHoldUpTheReveal() {
        var t = F.hosted()
        t.tasters[2].active = false
        t.applyIncoming([F.entry(F.ana, 0, 3)], as: F.ana.id)
        t.applyIncoming([F.entry(F.ben, 0, 4)], as: F.ben.id)
        XCTAssertEqual(t.statuses[F.pours[0].id]?.revealed, true)
    }

    func testAttendanceDecidesWhoMustScore() {
        var t = F.hosted()
        t.setAttendance(F.flight.id, [F.ana.id])
        t.applyIncoming([F.entry(F.ana, 0, 3)], as: F.ana.id)
        XCTAssertEqual(t.statuses[F.pours[0].id]?.revealed, true)
        t.setAttendance(F.flight.id, nil)
        XCTAssertEqual(t.statuses[F.pours[0].id]?.revealed, false)
    }

    func testAnyoneWhoScoredIsRequiredEvenIfNotOnTheTable() {
        var t = F.hosted()
        t.setAttendance(F.flight.id, [F.ana.id])
        t.applyIncoming([F.entry(F.ben, 0, 3)], as: F.ben.id)
        XCTAssertEqual(t.statuses[F.pours[0].id]?.revealed, false)
        XCTAssertTrue(t.statuses[F.pours[0].id]!.required.contains(F.ben.id))
    }

    func testHostOverridesWinBothWays() {
        var t = F.scored()
        let hidden = F.pours[3].id
        let shown = F.pours[0].id
        t.setOverride(hidden, .show)
        XCTAssertEqual(t.statuses[hidden]?.revealed, true)
        t.setOverride(shown, .hide)
        XCTAssertEqual(t.statuses[shown]?.revealed, false)
        t.setOverride(shown, nil)
        XCTAssertEqual(t.statuses[shown]?.revealed, true)
    }

    func testAPhoneCanOnlyWriteItsOwnEntries() {
        var t = F.hosted()
        let forged = F.entry(F.ana, 0, 1)
        XCTAssertFalse(t.applyIncoming([forged], as: F.ben.id))
        XCTAssertNil(t.entry(F.ana.id, F.pours[0].id))
    }

    func testUnknownPoursAndTastersAreIgnored() {
        var t = F.hosted()
        let stray = Entry(tasterID: F.ben.id, pourID: UUID(), score: 5)
        XCTAssertFalse(t.applyIncoming([stray], as: F.ben.id))
        XCTAssertFalse(t.applyIncoming([F.entry(F.ben, 0, 5)], as: UUID()))
    }

    func testOlderRevisionsLose() {
        var t = F.hosted()
        t.applyIncoming([F.entry(F.ben, 0, 4, rev: 5)], as: F.ben.id)
        t.applyIncoming([F.entry(F.ben, 0, 1, rev: 3)], as: F.ben.id)
        XCTAssertEqual(t.entry(F.ben.id, F.pours[0].id)?.score, 4)
        t.applyIncoming([F.entry(F.ben, 0, 2, rev: 6)], as: F.ben.id)
        XCTAssertEqual(t.entry(F.ben.id, F.pours[0].id)?.score, 2)
    }

    func testScoresAreClampedAndNotesCapped() {
        var t = F.hosted()
        let huge = String(repeating: "a", count: 5000)
        t.applyIncoming([Entry(tasterID: F.ben.id, pourID: F.pours[0].id, score: 9, notes: huge, rev: 1)], as: F.ben.id)
        let e = t.entry(F.ben.id, F.pours[0].id)!
        XCTAssertNil(e.score)
        XCTAssertEqual(e.notes.count, Limits.longText)
    }

    func testScoreLocksOnceRevealedButNotesStayEditable() {
        var t = F.scored()
        t.applyIncoming([F.entry(F.ben, 0, 1, notes: "changed my mind", rev: 9)], as: F.ben.id)
        let e = t.entry(F.ben.id, F.pours[0].id)!
        XCTAssertEqual(e.score, 4)
        XCTAssertEqual(e.notes, "changed my mind")

        t.editMine(F.pours[0].id) { $0.score = 1 }
        XCTAssertEqual(t.myEntry(F.pours[0].id)?.score, 3)
        XCTAssertTrue(t.isLocked(F.pours[0].id))
    }

    func testResetDropsScoresAndStaleEdits() {
        var t = F.scored()
        let p = F.pours[0].id
        t.resetPours([p])
        XCTAssertNil(t.entry(F.ben.id, p))
        XCTAssertEqual(t.statuses[p]?.revealed, false)
        XCTAssertEqual(t.statuses[p]?.generation, 1)
        XCTAssertFalse(t.applyIncoming([F.entry(F.ben, 0, 5, rev: 99)], as: F.ben.id), "edit from before the reset")
        var fresh = F.entry(F.ben, 0, 5, rev: 100)
        fresh.generation = 1
        XCTAssertTrue(t.applyIncoming([fresh], as: F.ben.id))
    }

    func testRemovingATasterDeletesTheirScores() {
        var t = F.scored()
        t.members = [Member(deviceID: UUID(), tokenHash: String(repeating: "a", count: 64), tasterID: F.cal.id)]
        t.removeTaster(F.cal.id)
        XCTAssertFalse(t.tasters.contains { $0.id == F.cal.id })
        XCTAssertFalse(t.entries.values.contains { $0.tasterID == F.cal.id })
        XCTAssertNil(t.members[0].tasterID)
        t.removeTaster(F.ana.id)
        XCTAssertTrue(t.tasters.contains { $0.id == F.ana.id }, "the host can't remove themself")
    }

    // MARK: What guests can see

    func testGuestSnapshotNeverContainsOtherPeoplesHiddenScores() {
        var t = F.scored()
        t.applyIncoming([F.entry(F.ben, 4, 2, notes: "secret")], as: F.ben.id)
        let snap = t.snapshot(for: F.cal.id)
        let hiddenPours = Set([F.pours[3].id, F.pours[4].id])
        let leaked = snap.entries.filter { hiddenPours.contains($0.pourID) && $0.tasterID != F.cal.id }
        XCTAssertTrue(leaked.isEmpty)
        XCTAssertEqual(Set(snap.statuses[F.pours[4].id]!.scoredBy), [F.ben.id], "who has scored is public")
    }

    func testGuestSnapshotIncludesTheirOwnHiddenEntry() {
        var t = F.scored()
        t.applyIncoming([F.entry(F.ben, 4, 2)], as: F.ben.id)
        let snap = t.snapshot(for: F.ben.id)
        XCTAssertTrue(snap.entries.contains { $0.tasterID == F.ben.id && $0.pourID == F.pours[4].id })
    }

    func testGuestKeepsUnsentEditsAcrossASnapshot() {
        let host = F.scored()
        var guest = Tasting(id: host.id, role: .guest, menu: host.menu)
        guest.applySnapshot(host.snapshot(for: F.ben.id))
        XCTAssertEqual(guest.me, F.ben.id)

        guest.editMine(F.pours[4].id) { $0.score = 3 }
        XCTAssertEqual(guest.dirty, [F.pours[4].id])
        guest.applySnapshot(host.snapshot(for: F.ben.id))
        XCTAssertEqual(guest.myEntry(F.pours[4].id)?.score, 3, "host hasn't seen it yet")
        XCTAssertEqual(guest.dirty, [F.pours[4].id])

        var h = host
        h.applyIncoming(guest.dirtyEntries(), as: F.ben.id)
        guest.applySnapshot(h.snapshot(for: F.ben.id))
        XCTAssertTrue(guest.dirty.isEmpty)
    }

    func testGuestDropsEditsMadeBeforeAHostReset() {
        var host = F.scored()
        var guest = Tasting(id: host.id, role: .guest, menu: host.menu)
        guest.applySnapshot(host.snapshot(for: F.ben.id))
        guest.editMine(F.pours[4].id) { $0.score = 5 }
        host.resetPours([F.pours[4].id])
        guest.applySnapshot(host.snapshot(for: F.ben.id))
        XCTAssertNil(guest.myEntry(F.pours[4].id))
        XCTAssertTrue(guest.dirty.isEmpty)
    }

    func testGuestIgnoresSnapshotsForAnotherTasting() {
        let host = F.scored()
        var guest = Tasting(role: .guest, menu: TastingMenu(title: "Other"))
        guest.applySnapshot(host.snapshot(for: F.ben.id))
        XCTAssertEqual(guest.menu.title, "Other")
    }

    func testClaimableExcludesHostAndBoundSeats() {
        var t = F.hosted()
        t.members = [Member(deviceID: UUID(), tokenHash: String(repeating: "b", count: 64), tasterID: F.ben.id)]
        XCTAssertEqual(t.claimableTasterIDs(), [F.cal.id])
    }

    func testMenuEditKeepsScoresForRenamedPours() {
        var t = F.scored()
        var menu = t.menu
        menu.flights[0].pours[0].name = "Renamed"
        menu.flights[0].pours.remove(at: 4)
        t.replaceMenu(menu)
        XCTAssertEqual(t.entry(F.ben.id, F.pours[0].id)?.score, 4)
        XCTAssertNil(t.statuses[F.pours[4].id])
        XCTAssertEqual(t.menuRevision, 1)
    }
}
