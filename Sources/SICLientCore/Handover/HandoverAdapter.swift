import Foundation

public enum HandoverEvent: Sendable, Equatable {
    case esrvccStarted(callID: String)
    case esrvccCompleted(callID: String)
    case esrvccFailed(callID: String, reason: String)
}

public protocol HandoverAdapter: Sendable {
    func notifyHandover(_ event: HandoverEvent) async
}

public final class StubHandoverAdapter: HandoverAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HandoverEvent] = []

    public init() {}

    public func notifyHandover(_ event: HandoverEvent) async {
        lock.withLock {
            events.append(event)
        }
    }

    public func snapshot() -> [HandoverEvent] {
        lock.withLock { events }
    }
}

public enum STIRSHAKPolicy {
    public static func identityHeader(for profile: OperatorProfile) -> String? {
        guard profile.services.handover.stirShakEnabled else { return nil }
        return profile.services.handover.labIdentityHeader
    }

    public static func attachIdentity(to headers: inout SIPHeaders, profile: OperatorProfile) {
        guard let identity = identityHeader(for: profile) else { return }
        headers.set("Identity", value: identity)
    }
}

public actor ESRVCCCoordinator {
    private let profile: OperatorProfile
    private let handoverAdapter: any HandoverAdapter
    private let logger: Logger

    public init(profile: OperatorProfile, handoverAdapter: any HandoverAdapter, logger: Logger) {
        self.profile = profile
        self.handoverAdapter = handoverAdapter
        self.logger = logger
    }

    public func beginHandover(callID: String) async {
        guard profile.services.handover.esrvccEnabled else { return }
        await handoverAdapter.notifyHandover(.esrvccStarted(callID: callID))
        logger.info("eSRVCC handover started", fields: ["call_id": callID])
    }

    public func completeHandover(callID: String) async {
        guard profile.services.handover.esrvccEnabled else { return }
        await handoverAdapter.notifyHandover(.esrvccCompleted(callID: callID))
        logger.info("eSRVCC handover completed", fields: ["call_id": callID])
    }
}
