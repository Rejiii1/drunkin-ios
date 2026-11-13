import Foundation
@preconcurrency import MultipeerConnectivity

/// Runs on the host's phone while a hosted tasting is open. Advertises the
/// tasting to nearby phones over Multipeer Connectivity (Bluetooth / Wi-Fi,
/// no internet needed), admits phones that know the join code or hold a
/// rejoin token, and sends each one only what it is allowed to see.
@MainActor
final class HostService: NSObject {
    weak var model: AppModel?

    private(set) var tastingID: UUID?
    private var myPeer: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var sessions: [MCSession] = []

    private struct Pending { var deviceID: UUID; var issueToken: Bool; var session: MCSession }
    private var pending: [MCPeerID: Pending] = [:]
    private var connected: [MCPeerID: (deviceID: UUID, session: MCSession)] = [:]
    private var failedCodes: [Date] = []
    private var broadcastWork: DispatchWorkItem?

    var connectedDeviceIDs: Set<UUID> { Set(connected.values.map { $0.deviceID }) }
    var isRunning: Bool { advertiser != nil }

    func start(_ t: Tasting) {
        guard t.role == .host else { return }
        if tastingID == t.id, advertiser != nil { return }
        stop()
        tastingID = t.id
        let peer = MCPeerID(displayName: WireCodec.peerName(t.name(of: t.me)))
        myPeer = peer
        let info = [
            "id": t.id.uuidString,
            "t": WireCodec.discoveryValue(t.menu.title),
            "h": WireCodec.discoveryValue(t.name(of: t.me)),
        ]
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Wire.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        model?.hostStatusChanged()
    }

    func stop(notifyEnded: Bool = false) {
        if notifyEnded, let data = WireCodec.encode(HostMessage.ended) {
            for (peer, c) in connected { try? c.session.send(data, toPeers: [peer], with: .reliable) }
        }
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        for s in sessions {
            s.delegate = nil
            s.disconnect()
        }
        sessions = []
        pending = [:]
        connected = [:]
        broadcastWork?.cancel()
        tastingID = nil
        myPeer = nil
        model?.hostStatusChanged()
    }

    // MARK: Sending

    func send(_ msg: HostMessage, to peer: MCPeerID) {
        guard let c = connected[peer], let data = WireCodec.encode(msg) else { return }
        try? c.session.send(data, toPeers: [peer], with: .reliable)
    }

    func peers(for deviceID: UUID) -> [MCPeerID] {
        connected.filter { $0.value.deviceID == deviceID }.map { $0.key }
    }

    /// Sends every connected phone its own view of the table. Coalesces
    /// bursts of edits into one round of messages.
    func scheduleBroadcast() {
        broadcastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.broadcastNow() }
        }
        broadcastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func broadcastNow() {
        guard let id = tastingID, let t = model?.tastings[id] else { return }
        for (peer, c) in connected {
            let tasterID = t.members.first { $0.deviceID == c.deviceID }?.tasterID
            send(.snapshot(t.snapshot(for: tasterID)), to: peer)
        }
    }

    func broadcast(_ msg: HostMessage) {
        for peer in connected.keys { send(msg, to: peer) }
    }

    // MARK: Admission

    private func session() -> MCSession {
        if let s = sessions.first(where: { s in
            s.connectedPeers.count + pending.values.filter { $0.session === s }.count < kMCSessionMaximumNumberOfPeers - 1
        }) { return s }
        let s = MCSession(peer: myPeer!, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        sessions.append(s)
        return s
    }

    private func handleInvitation(from peer: MCPeerID, context: Data?, reply: (Bool, MCSession?) -> Void) {
        guard let model, let id = tastingID, var t = model.tastings[id], t.role == .host,
              let req = WireCodec.joinRequest(from: context), req.tastingID == id else {
            reply(false, nil)
            return
        }
        let now = Date()
        failedCodes = failedCodes.filter { now.timeIntervalSince($0) < 300 }

        if let token = req.token,
           let member = t.members.first(where: { $0.deviceID == req.deviceID }),
           Secrets.equal(Secrets.sha256(token), member.tokenHash) {
            let s = session()
            pending[peer] = Pending(deviceID: req.deviceID, issueToken: false, session: s)
            reply(true, s)
            return
        }

        guard let code = req.code, let joinCode = t.joinCode else {
            reply(false, nil)
            return
        }
        guard failedCodes.count < 8 else {
            reply(false, nil)
            model.hostNotice("Too many wrong join codes. Joining is paused for a few minutes.")
            return
        }
        guard Secrets.equal(code, joinCode) else {
            failedCodes.append(now)
            reply(false, nil)
            return
        }
        // A phone joining with the code starts fresh: if it reuses a device
        // id it must claim its name again, so nobody can take over a seat
        // just by knowing another phone's id.
        if let i = t.members.firstIndex(where: { $0.deviceID == req.deviceID }) {
            t.members[i].tasterID = nil
            model.replaceTasting(t)
        }
        let s = session()
        pending[peer] = Pending(deviceID: req.deviceID, issueToken: true, session: s)
        reply(true, s)
    }

    private func peerConnected(_ peer: MCPeerID, in session: MCSession) {
        guard let p = pending.removeValue(forKey: peer), p.session === session,
              let model, let id = tastingID, var t = model.tastings[id] else {
            session.cancelConnectPeer(peer)
            return
        }
        var token: String?
        if p.issueToken {
            let fresh = Secrets.token()
            token = fresh
            if let i = t.members.firstIndex(where: { $0.deviceID == p.deviceID }) {
                t.members[i].tokenHash = Secrets.sha256(fresh)
            } else {
                t.members.append(Member(deviceID: p.deviceID, tokenHash: Secrets.sha256(fresh), tasterID: nil))
            }
            model.replaceTasting(t)
        }
        connected[peer] = (p.deviceID, session)
        let tasterID = t.members.first { $0.deviceID == p.deviceID }?.tasterID
        send(.welcome(Welcome(token: token, snapshot: t.snapshot(for: tasterID), avatars: t.avatars)), to: peer)
        model.hostStatusChanged()
    }

    private func peerDisconnected(_ peer: MCPeerID) {
        pending[peer] = nil
        connected[peer] = nil
        model?.hostStatusChanged()
    }

    private func received(_ data: Data, from peer: MCPeerID) {
        guard let c = connected[peer] else { return }
        switch WireCodec.decode(GuestMessage.self, from: data) {
        case .success(let msg):
            model?.hostHandle(msg, deviceID: c.deviceID, peer: peer)
        case .failure(.incompatible):
            send(.notice("This phone and the host's are on different versions of Drunkin. Update both from the App Store."), to: peer)
        case .failure:
            break
        }
    }

    private func isKnown(_ peer: MCPeerID) -> Bool { pending[peer] != nil || connected[peer] != nil }
}

extension HostService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handleInvitation(from: peerID, context: context, reply: invitationHandler)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.model?.hostNotice("Can't reach nearby phones. Check that Local Network is on for Drunkin in Settings.")
            }
        }
    }
}

extension HostService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.sessions.contains(where: { $0 === session }) else { return }
                switch state {
                case .connected: self.peerConnected(peerID, in: session)
                case .notConnected: self.peerDisconnected(peerID)
                default: break
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= Limits.messageBytes else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.received(data, from: peerID) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { certificateHandler(self.isKnown(peerID)) }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel()
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let localURL { try? FileManager.default.removeItem(at: localURL) }
    }
}
