import Foundation

enum Wire {
    static let version = 1
    /// Bonjour service type. Must match NSBonjourServices in Info.plist.
    static let serviceType = "drunkin-tst"
    static let maxContextBytes = 2_048
    static let maxDiscoveryValue = 60
}

/// Sent with the Multipeer invitation. A new phone proves it's at the table
/// with the host's 6-digit join code; a returning phone uses the secret token
/// the host gave it the first time.
struct JoinRequest: Codable {
    var v = Wire.version
    var tastingID: UUID
    var deviceID: UUID
    var code: String?
    var token: String?
}

enum GuestMessage: Codable {
    case entries([Entry])
    case claim(UUID)
    case newTaster(String)
    case avatar(Data)
}

struct Welcome: Codable {
    var token: String?
    var snapshot: GuestSnapshot
    var avatars: [UUID: Data]
}

enum HostMessage: Codable {
    case welcome(Welcome)
    case snapshot(GuestSnapshot)
    case avatars([UUID: Data])
    case notice(String)
    case ended
}

private struct Envelope<Body: Codable>: Codable {
    var v: Int
    var body: Body
}

private struct VersionProbe: Codable { var v: Int }

enum WireError: Error, Equatable {
    case tooLarge, malformed, incompatible(Int)
}

enum WireCodec {
    static func encode<T: Codable>(_ body: T) -> Data? {
        try? JSONEncoder().encode(Envelope(v: Wire.version, body: body))
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) -> Result<T, WireError> {
        guard data.count <= Limits.messageBytes else { return .failure(.tooLarge) }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .failure(.malformed) }
        guard probe.v == Wire.version else { return .failure(.incompatible(probe.v)) }
        guard let env = try? decoder.decode(Envelope<T>.self, from: data) else { return .failure(.malformed) }
        return .success(env.body)
    }

    static func joinRequest(from data: Data?) -> JoinRequest? {
        guard let data, data.count <= Wire.maxContextBytes,
              let req = try? JSONDecoder().decode(JoinRequest.self, from: data),
              req.v == Wire.version else { return nil }
        if let code = req.code, code.count > 12 { return nil }
        if let token = req.token, token.count > 128 { return nil }
        return req
    }

    static func peerName(_ s: String) -> String {
        var out = ""
        for ch in Sanitize.line(s, max: Limits.name) {
            if (out + String(ch)).utf8.count > 60 { break }
            out.append(ch)
        }
        return out.isEmpty ? "Drunkin" : out
    }

    static func discoveryValue(_ s: String) -> String {
        var out = ""
        for ch in Sanitize.line(s) {
            if (out + String(ch)).utf8.count > Wire.maxDiscoveryValue { break }
            out.append(ch)
        }
        return out
    }
}
