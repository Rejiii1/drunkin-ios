import XCTest
@testable import Drunkin

final class ResultsTests: XCTestCase {
    typealias F = Fixture

    func testFlightResultsRankRevealedPoursAndIgnoreHiddenOnes() {
        let r = Results.flight(F.flight, F.scored())
        XCTAssertEqual(r.ranked.count, 3)
        XCTAssertEqual(r.hiddenCount, 2)
    }

    func testTiesForPourOfTheFlightAreAllWinners() {
        let r = Results.flight(F.flight, F.scored())
        XCTAssertEqual(Set(r.winners.map(\.pour.id)), [F.pours[1].id, F.pours[2].id])
    }

    func testFavoritesAndBiggestDisagreement() {
        let r = Results.flight(F.flight, F.scored())
        let ben = r.favorites.first { $0.tasterID == F.ben.id }!.favorite
        XCTAssertEqual(ben.score, 5)
        XCTAssertEqual(ben.pours.map(\.id), [F.pours[1].id])
        XCTAssertEqual(r.disagreement?.pour.id, F.pours[0].id)
        XCTAssertEqual(r.high?.tasterID, F.ben.id)
        XCTAssertEqual(r.low?.tasterID, F.cal.id)
    }

    func testHiddenScoresNeverReachTheLeaderboard() {
        let rows = Results.leaderboard(F.scored())
        XCTAssertFalse(rows.contains { $0.pour.id == F.pours[3].id })
    }

    func testAwards() {
        let a = Dictionary(uniqueKeysWithValues: Results.awards(F.scored()).map { ($0.key, $0) })
        XCTAssertEqual(Set(a["tough"]!.ids), [F.cal.id, F.ana.id])
        XCTAssertEqual(a["soft"]!.ids, [F.ben.id])
        XCTAssertEqual(a["poet"]!.ids, [F.cal.id])
        XCTAssertNil(a["water"], "nobody added water")
    }

    func testShareTextListsRankedPoursAndHidesTheRest() {
        let text = Results.shareText(F.flight, F.scored())
        XCTAssertTrue(text.contains("Test Night · Age & Proof"))
        XCTAssertTrue(text.contains("1. Pour 2 4.3") || text.contains("1. Pour 3 4.3"))
        XCTAssertTrue(text.contains("(2 still hidden)"))
        XCTAssertFalse(text.contains("Pour 4 "))
    }

    func testProofFormatting() {
        XCTAssertEqual(Results.fmtProof(90), "90")
        XCTAssertEqual(Results.fmtProof(126.9), "126.9")
    }
}
