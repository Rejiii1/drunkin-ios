import Foundation
import MultipeerConnectivity

struct NearbyHost: Identifiable, Equatable {
    var peer: MCPeerID
    var tastingID: UUID
    var title: String
    var hostName: String
    var id: MCPeerID { peer }
}

enum GuestLink: Equatable {
    case idle
    case searching
    case connecting(UUID)
    case connected(UUID)
    case failed(String)
}

/// Runs on a guest's phone: finds nearby hosts, joins with a code or a saved
/// rejoin token, and only ever talks to the one host it invited.
@MainActor
final class GuestService: NSObject {
    weak var model: AppModel?

    private let myPeer = MCPeerID(displayName: "Drunkin")
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private var hostPeer: MCPeerID?
    private var target: UUID?
    private var usedCode = false
    private var nearbyByPeer: [MCPeerID: NearbyHost] = [:]
    private var retryWork: DispatchWorkItem?
    private var rejoinFailures = 0
    private var welcomed = false

    /// The tasting this phone should reconnect to on its own.
    var autoRejoin: UUID? {
        didSet {
            if autoRejoin != oldValue {
                rejoinFailures = 0
                tryRejoin()
            }
        }
    }

    var nearby: [NearbyHost] { nearbyByPeer.values.sorted { $0.title < $1.title } }

    func startBrowsing() {
        guard browser == nil else { return }
        let b = MCNearbyServiceBrowser(peer: myPeer, serviceType: Wire.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        if case .idle = model?.guestLink { model?.guestLink = .searching }
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        disconnect()
        nearbyByPeer = [:]
        model?.guestLink = .idle
        model?.nearbyChanged()
    }

    func disconnect() {
        retryWork?.cancel()
        session?.delegate = nil
        session?.disconnect()
        session = nil
        hostPeer = nil
        target = nil
    }

    func join(_ host: NearbyHost, code: String, deviceID: UUID) {
        let digits = code.filter(\.isASCIIDigit)
        guard digits.count == 6 else {
            model?.guestLink = .failed("The join code is 6 digits.")
            return
        }
        invite(host, request: JoinRequest(tastingID: host.tastingID, deviceID: deviceID, code: String(digits)))
        usedCode = true
    }

    func send(_ msg: GuestMessage) {
        guard let session, let hostPeer, session.connectedPeers.contains(hostPeer),
              let data = WireCodec.encode(msg) else { return }
        try? session.send(data, toPeers: [hostPeer], with: .reliable)
    }

    var isConnected: Bool {
        guard let session, let hostPeer else { return false }
        return session.connectedPeers.contains(hostPeer)
    }

    var connectedTastingID: UUID? { isConnected ? target : nil }

    private func invite(_ host: NearbyHost, request: JoinRequest) {
        disconnect()
        guard let browser, let ctx = try? JSONEncoder().encode(request) else { return }
        let s = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        hostPeer = host.peer
        target = host.tastingID
        usedCode = false
        welcomed = false
        model?.guestLink = .connecting(host.tastingID)
        browser.invitePeer(host.peer, to: s, withContext: ctx, timeout: 20)
    }

    private func tryRejoin() {
        guard let id = autoRejoin, browser != nil, !isConnected, rejoinFailures < 4,
              session == nil || target != id,
              let host = nearbyByPeer.values.first(where: { $0.tastingID == id }),
              let token = Keychain.get(id.uuidString),
              let deviceID = model?.deviceID else { return }
        invite(host, request: JoinRequest(tastingID: id, deviceID: deviceID, token: token))
    }

    private func scheduleRetry() {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.session == nil else { return }
                self.tryRejoin()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func stateChanged(_ peer: MCPeerID, _ state: MCSessionState, _ s: MCSession) {
        guard s === session, peer == hostPeer, let target else { return }
        switch state {
        case .connected:
            model?.guestLink = .connected(target)
        case .notConnected:
            let wasCode = usedCode
            let wasWelcomed = welcomed
            session?.delegate = nil
            session = nil
            hostPeer = nil
            self.target = nil
            if wasCode, case .connecting = model?.guestLink {
                model?.guestLink = .failed("Couldn't join. Check the code with the host and try again.")
            } else {
                if wasWelcomed { rejoinFailures = 0 } else { rejoinFailures += 1 }
                model?.guestDisconnected(target)
                if rejoinFailures >= 4 {
                    model?.guestLink = .failed("The host's phone didn't let this one back in. Ask the host for the join code.")
                } else {
                    model?.guestLink = .searching
                    scheduleRetry()
                }
            }
        default:
            break
        }
    }

    private func received(_ data: Data, from peer: MCPeerID) {
        guard peer == hostPeer, let target else { return }
        switch WireCodec.decode(HostMessage.self, from: data) {
        case .success(let msg):
            usedCode = false
            welcomed = true
            rejoinFailures = 0
            model?.guestHandle(msg, tastingID: target)
        case .failure(.incompatible):
            model?.guestLink = .failed("The host is on a different version of Drunkin. Update both phones from the App Store.")
            disconnect()
        case .failure:
            break
        }
    }

    private func found(_ peer: MCPeerID, info: [String: String]?) {
        guard let info, let raw = info["id"], let id = UUID(uuidString: raw) else { return }
        nearbyByPeer[peer] = NearbyHost(
            peer: peer,
            tastingID: id,
            title: WireCodec.discoveryValue(info["t"] ?? "Tasting"),
            hostName: WireCodec.discoveryValue(info["h"] ?? peer.displayName)
        )
        model?.nearbyChanged()
        if id == autoRejoin { tryRejoin() }
    }

    private func lost(_ peer: MCPeerID) {
        nearbyByPeer[peer] = nil
        model?.nearbyChanged()
    }
}

extension GuestService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.found(peerID, info: info) } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.lost(peerID) } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.model?.guestLink = .failed("Can't look for nearby phones. Check that Local Network is on for Drunkin in Settings.")
            }
        }
    }
}

extension GuestService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.stateChanged(peerID, state, session) } }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= Limits.messageBytes else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard session === self.session else { return }
                self.received(data, from: peerID)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { certificateHandler(session === self.session && peerID == self.hostPeer) }
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
