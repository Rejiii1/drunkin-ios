import XCTest
@testable import Drunkin

final class SharingTests: XCTestCase {
    typealias F = Fixture

    func testResultsFileLeavesOutHiddenScoresAndSecrets() throws {
        var t = F.scored()
        t.applyIncoming([F.entry(F.ben, 4, 2, notes: "secret")], as: F.ben.id)
        t.members = [Member(deviceID: UUID(), tokenHash: String(repeating: "c", count: 64), tasterID: F.ben.id)]
        let data = try TastingFile.results(of: t).encoded()
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("123456"), "join code")
        XCTAssertFalse(json.contains(String(repeating: "c", count: 64)), "token hash")

        let back = try TastingFile.decode(data)
        XCTAssertEqual(back.kind, .results)
        XCTAssertEqual(back.tasting.role, .archive)
        XCTAssertNil(back.tasting.entry(F.ana.id, F.pours[3].id), "Ana's hidden score")
        XCTAssertEqual(back.tasting.entry(F.ben.id, F.pours[0].id)?.score, 4)
        XCTAssertEqual(Results.leaderboard(back.tasting).count, 3)
    }

    func testHandoffKeepsEverythingForTheNextHost() throws {
        var t = F.scored()
        t.members = [Member(deviceID: UUID(), tokenHash: String(repeating: "d", count: 64), tasterID: F.ben.id)]
        let back = try TastingFile.decode(try TastingFile.handoff(of: t).encoded())
        XCTAssertEqual(back.tasting.role, .host)
        XCTAssertEqual(back.tasting.entry(F.ana.id, F.pours[3].id)?.score, 5)
        XCTAssertEqual(back.tasting.members.count, 1)
        XCTAssertEqual(back.tasting.joinCode, "123456")
    }

    func testImportRejectsJunk() {
        XCTAssertThrowsError(try TastingFile.decode(Data("{}".utf8))) { XCTAssertEqual($0 as? ImportError, .notATasting) }
        XCTAssertThrowsError(try TastingFile.decode(Data("not json".utf8)))
        var big = Data(count: Limits.fileBytes + 1)
        big[0] = 0x7B
        XCTAssertThrowsError(try TastingFile.decode(big)) { XCTAssertEqual($0 as? ImportError, .tooLarge) }
    }

    func testImportRejectsNewerFormat() throws {
        var file = TastingFile.results(of: F.scored())
        file.version = 99
        XCTAssertThrowsError(try TastingFile.decode(try file.encoded())) { XCTAssertEqual($0 as? ImportError, .newerVersion) }
    }

    func testImportSanitizesHostileContent() throws {
        var t = F.scored()
        t.menu.title = "Evil\u{0000}\u{202E}Night" + String(repeating: "x", count: 500)
        t.tasters[1].name = String(repeating: "B", count: 500)
        t.entries["junk"] = Entry(tasterID: UUID(), pourID: UUID(), score: 3)
        t.members = [Member(deviceID: UUID(), tokenHash: "not-a-hash", tasterID: nil)]
        t.avatars[F.ana.id] = Data("not an image".utf8)
        let back = try TastingFile.decode(try TastingFile.handoff(of: t).encoded()).tasting
        XCTAssertFalse(back.menu.title.contains("\u{0000}"))
        XCTAssertFalse(back.menu.title.contains("\u{202E}"))
        XCTAssertLessThanOrEqual(back.menu.title.count, Limits.title)
        XCTAssertLessThanOrEqual(back.tasters[1].name.count, Limits.name)
        XCTAssertNil(back.entries["junk"])
        XCTAssertTrue(back.members.isEmpty)
        XCTAssertNil(back.avatars[F.ana.id])
    }

    func testWireRoundTripAndVersionCheck() {
        let msg = GuestMessage.entries([F.entry(F.ben, 0, 4)])
        let data = WireCodec.encode(msg)!
        guard case .success(.entries(let list)) = WireCodec.decode(GuestMessage.self, from: data) else { return XCTFail() }
        XCTAssertEqual(list.first?.score, 4)

        let future = Data(#"{"v":2,"body":{}}"#.utf8)
        guard case .failure(.incompatible(2)) = WireCodec.decode(GuestMessage.self, from: future) else { return XCTFail() }
        guard case .failure(.malformed) = WireCodec.decode(GuestMessage.self, from: Data("x".utf8)) else { return XCTFail() }
    }

    func testJoinRequestLimits() throws {
        let ok = JoinRequest(tastingID: UUID(), deviceID: UUID(), code: "123456")
        XCTAssertNotNil(WireCodec.joinRequest(from: try JSONEncoder().encode(ok)))
        let long = JoinRequest(tastingID: UUID(), deviceID: UUID(), code: String(repeating: "1", count: 50))
        XCTAssertNil(WireCodec.joinRequest(from: try JSONEncoder().encode(long)))
        XCTAssertNil(WireCodec.joinRequest(from: Data(count: Wire.maxContextBytes + 1)))
        XCTAssertNil(WireCodec.joinRequest(from: nil))
    }

    func testSecrets() {
        XCTAssertEqual(Secrets.joinCode().count, 6)
        XCTAssertTrue(Secrets.joinCode().allSatisfy(\.isASCIIDigit))
        let a = Secrets.token(), b = Secrets.token()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 40)
        XCTAssertTrue(Secrets.equal("123456", "123456"))
        XCTAssertFalse(Secrets.equal("123456", "123457"))
        XCTAssertEqual(Secrets.sha256("x").count, 64)
    }

    func testPeerNamesFitMultipeerLimits() {
        XCTAssertLessThanOrEqual(WireCodec.peerName(String(repeating: "🥃", count: 40)).utf8.count, 63)
        XCTAssertEqual(WireCodec.peerName(""), "Drunkin")
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TastingStore(directory: dir)
        let t = F.scored()
        try store.save(t)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].entries.count, t.entries.count)
        store.delete(t.id)
        XCTAssertTrue(store.loadAll().isEmpty)
        store.deleteAll()
    }
}
