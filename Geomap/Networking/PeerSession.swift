import Foundation
import MultipeerConnectivity

/// The only things ever sent between the two phones. A user id or display
/// name is deliberately not part of this — the server resolves the name
/// from the code, so a modified peer can't claim to be someone else.
enum PeerMessage: Equatable {
    case token(String)
    case confirmed

    private struct Wire: Codable {
        let type: String
        let token: String?
    }

    var data: Data {
        let wire: Wire
        switch self {
        case .token(let token): wire = Wire(type: "token", token: token)
        case .confirmed: wire = Wire(type: "confirmed", token: nil)
        }
        return (try? JSONEncoder().encode(wire)) ?? Data()
    }

    init?(data: Data) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        switch wire.type {
        case "token":
            guard let token = wire.token, !token.isEmpty, token.count <= 256 else { return nil }
            self = .token(token)
        case "confirmed":
            self = .confirmed
        default:
            return nil
        }
    }
}

enum PeerEvent: Equatable {
    case peerConnected
    case peerDisconnected
    case message(PeerMessage)
}

@MainActor
protocol PeerSessionProtocol: AnyObject {
    func start(onEvent: @escaping @MainActor (PeerEvent) -> Void)
    func send(_ message: PeerMessage)
    func stop()
}

/// MultipeerConnectivity advertiser + browser on the same service type, so
/// two phones that both opened Add Friend find each other. Only the side
/// with the lexicographically smaller (random, anonymous) peer name invites,
/// to avoid both sides inviting simultaneously.
@MainActor
final class MultipeerPeerSession: NSObject, PeerSessionProtocol {
    private static let serviceType = "geomap-friend"

    private let myPeerID = MCPeerID(displayName: String(UUID().uuidString.prefix(8)))
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var connectedPeer: MCPeerID?
    private var onEvent: (@MainActor (PeerEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (PeerEvent) -> Void) {
        stop()
        self.onEvent = onEvent

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func send(_ message: PeerMessage) {
        guard let session, let peer = connectedPeer else { return }
        try? session.send(message.data, toPeers: [peer], with: .reliable)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        connectedPeer = nil
        onEvent = nil
    }
}

extension MultipeerPeerSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                guard self.connectedPeer == nil else { return }
                self.connectedPeer = peerID
                self.onEvent?(.peerConnected)
            case .notConnected:
                guard self.connectedPeer == peerID else { return }
                self.connectedPeer = nil
                self.onEvent?(.peerDisconnected)
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = PeerMessage(data: data) else { return }
        Task { @MainActor in
            guard self.connectedPeer == peerID else { return }
            self.onEvent?(.message(message))
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerPeerSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        nonisolated(unsafe) let handler = invitationHandler
        Task { @MainActor in
            // One counterpart at a time.
            if self.connectedPeer == nil, let session = self.session {
                handler(true, session)
            } else {
                handler(false, nil)
            }
        }
    }
}

extension MultipeerPeerSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard self.connectedPeer == nil,
                  let session = self.session,
                  self.myPeerID.displayName < peerID.displayName else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
