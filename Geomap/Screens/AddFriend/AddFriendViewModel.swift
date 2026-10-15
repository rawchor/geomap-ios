import Foundation

enum AddFriendState: Equatable {
    case starting
    /// We hold our own code and are waiting for the other phone.
    case searching
    case lookingUp
    case confirming(UserProfileResponse)
    case waitingForOther(UserProfileResponse)
    case success(UserProfileResponse)
    case alreadyFriends(UserProfileResponse)
    /// A code expired (ours, theirs) or the other side didn't confirm in time.
    case expired
    case failed(String)
}

@MainActor
final class AddFriendViewModel: ObservableObject {
    @Published private(set) var state: AddFriendState = .starting

    private let apiClient: APIClient
    private let peer: PeerSessionProtocol
    private let pollInterval: TimeInterval
    private let pendingTimeout: TimeInterval

    private var myToken: String?
    private var theirToken: String?
    private var peerConfirmedEarly = false
    private var renewTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(
        apiClient: APIClient = .shared,
        peer: PeerSessionProtocol? = nil,
        pollInterval: TimeInterval = 3,
        pendingTimeout: TimeInterval = 300
    ) {
        self.apiClient = apiClient
        self.peer = peer ?? MultipeerPeerSession()
        self.pollInterval = pollInterval
        self.pendingTimeout = pendingTimeout
    }

    func start() async {
        reset()
        state = .starting
        do {
            let issued = try await apiClient.issueEncounterToken()
            myToken = issued.token
            state = .searching
            peer.start { [weak self] event in self?.handle(event) }
            scheduleRenewal(at: issued.expiresAt)
        } catch let error as APIError {
            state = .failed(error.displayMessage)
        } catch {
            state = .failed("Something went wrong. Please try again.")
        }
    }

    func retry() async {
        await start()
    }

    func confirm() async {
        guard case .confirming(let profile) = state, let theirToken else { return }
        do {
            let result = try await apiClient.confirmEncounter(token: theirToken)
            switch result.status {
            case .confirmed:
                finishSuccess(result.profile)
                peer.send(.confirmed)
            case .pending:
                if peerConfirmedEarly {
                    // They said they confirmed but the server still says
                    // pending — the server is authoritative, keep polling.
                }
                state = .waitingForOther(profile)
                startPolling(for: profile.userId)
            }
        } catch let error as APIError {
            state = error.isGone ? .expired : .failed(error.displayMessage)
        } catch {
            state = .failed("Something went wrong. Please try again.")
        }
    }

    /// Cancel tapped or screen closed. Withdraws any pending confirmation.
    func cancel() async {
        let profile: UserProfileResponse?
        switch state {
        case .confirming(let p), .waitingForOther(let p): profile = p
        default: profile = nil
        }
        let wasFinished: Bool
        if case .success = state { wasFinished = true } else { wasFinished = false }
        reset()
        if let profile, !wasFinished {
            try? await apiClient.cancelPendingFriend(userId: profile.userId)
        }
    }

    // MARK: - Peer events

    private func handle(_ event: PeerEvent) {
        switch event {
        case .peerConnected:
            if let myToken { peer.send(.token(myToken)) }
        case .peerDisconnected:
            switch state {
            case .lookingUp, .confirming:
                theirToken = nil
                state = .searching
            default:
                break
            }
        case .message(.token(let token)):
            guard state == .searching, theirToken == nil else { return }
            theirToken = token
            Task { await self.lookup(token: token) }
        case .message(.confirmed):
            if case .waitingForOther(let profile) = state {
                finishSuccess(profile)
            } else {
                peerConfirmedEarly = true
            }
        }
    }

    private func lookup(token: String) async {
        state = .lookingUp
        do {
            let profile = try await apiClient.lookupEncounter(token: token)
            // Confirming someone who is already a friend returns CONFIRMED
            // too, so check first to show an accurate message.
            if let friends = try? await apiClient.friends(), friends.contains(where: { $0.userId == profile.userId }) {
                state = .alreadyFriends(profile)
                return
            }
            state = .confirming(profile)
        } catch let error as APIError {
            state = error.isGone ? .expired : .failed(error.displayMessage)
        } catch {
            state = .failed("Something went wrong. Please try again.")
        }
    }

    // MARK: - Completion, polling, renewal

    private func finishSuccess(_ profile: UserProfileResponse) {
        pollTask?.cancel()
        renewTask?.cancel()
        state = .success(profile)
    }

    /// GET /friends is the authoritative fallback for "the other side
    /// confirmed" if the peer-to-peer message never arrives.
    private func startPolling(for userId: UUID) {
        pollTask?.cancel()
        let started = Date()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let friends = try? await self.apiClient.friends(), friends.contains(where: { $0.userId == userId }) {
                    if case .waitingForOther(let profile) = self.state { self.finishSuccess(profile) }
                    return
                }
                if Date().timeIntervalSince(started) >= self.pendingTimeout {
                    if case .waitingForOther = self.state { self.state = .expired }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// Our code lasts 5 minutes; while still searching, swap in a fresh one
    /// shortly before it lapses and re-send it if a peer is connected.
    private func scheduleRenewal(at expiresAt: Date) {
        renewTask?.cancel()
        let delay = max(expiresAt.timeIntervalSinceNow - 10, 1)
        renewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.state == .searching else { return }
            if let issued = try? await self.apiClient.issueEncounterToken() {
                self.myToken = issued.token
                self.peer.send(.token(issued.token))
                self.scheduleRenewal(at: issued.expiresAt)
            }
        }
    }

    private func reset() {
        renewTask?.cancel()
        pollTask?.cancel()
        renewTask = nil
        pollTask = nil
        peer.stop()
        myToken = nil
        theirToken = nil
        peerConfirmedEarly = false
    }
}
