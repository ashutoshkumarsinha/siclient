import Foundation

public final class MockIMSState: @unchecked Sendable {
    public let pcscf = MockPCSCFState()
    public var lastInvite: SIPRequest?
    public var prackCount = 0
    public var updateCount = 0
    public var byeCount = 0

    public init() {}
}

public enum MockIMSResponder {
    public static func responses(
        for requestData: Data,
        profile: OperatorProfile,
        state: MockIMSState
    ) -> [Data] {
        guard case .request(let request) = try? SIPParser.parse(requestData) else { return [] }

        switch request.method {
        case SIPMethod.register.rawValue:
            guard let data = MockPCSCFResponder.response(for: requestData, profile: profile, state: state.pcscf) else {
                return []
            }
            return [data]
        case SIPMethod.invite.rawValue:
            return handleInvite(request, profile: profile, state: state)
        case SIPMethod.prack.rawValue:
            return handlePRACK(request, profile: profile, state: state)
        case SIPMethod.update.rawValue:
            return handleUPDATE(request, profile: profile, state: state)
        case SIPMethod.cancel.rawValue:
            return [SIPSerializer.serialize(.response(SessionRequestBuilder.makeOK(for: request)))]
        case SIPMethod.bye.rawValue:
            state.byeCount += 1
            return [SIPSerializer.serialize(.response(SessionRequestBuilder.makeOK(for: request)))]
        case SIPMethod.ack.rawValue:
            return []
        default:
            return []
        }
    }

    private static func handleInvite(_ request: SIPRequest, profile: OperatorProfile, state: MockIMSState) -> [Data] {
        if request.headers["To"]?.contains("tag=") == true {
            return handleReInvite(request, profile: profile)
        }

        state.lastInvite = request
        let localIP = "10.0.0.2"
        let offered = request.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
            .map { SDPParser.offeredAudioCodecs($0) } ?? []
        let answer = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 50000,
            offeredCodecs: offered,
            preconditionState: PreconditionState(local: .none, remote: .none)
        )
        let progress = SessionRequestBuilder.makeSessionProgress(
            for: request,
            sdp: answer,
            require100rel: true
        )
        return [SIPSerializer.serialize(.response(progress))]
    }

    private static func handlePRACK(_ request: SIPRequest, profile: OperatorProfile, state: MockIMSState) -> [Data] {
        state.prackCount += 1
        guard let invite = state.lastInvite else {
            return [SIPSerializer.serialize(.response(SIPResponse(statusCode: 481, reasonPhrase: "Call/Transaction Does Not Exist")))]
        }

        let prackOK = SessionRequestBuilder.makeOK(for: request)
        let localIP = "10.0.0.2"
        let offered = invite.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
            .map { SDPParser.offeredAudioCodecs($0) } ?? []
        let pendingSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 50000,
            offeredCodecs: offered,
            preconditionState: PreconditionState(local: .sendrecv, remote: .none)
        )
        let inviteOK = SessionRequestBuilder.makeOK(for: invite, sdp: pendingSDP)
        return [
            SIPSerializer.serialize(.response(prackOK)),
            SIPSerializer.serialize(.response(inviteOK)),
        ]
    }

    private static func handleUPDATE(_ request: SIPRequest, profile: OperatorProfile, state: MockIMSState) -> [Data] {
        state.updateCount += 1
        guard let invite = state.lastInvite else {
            return [SIPSerializer.serialize(.response(SIPResponse(statusCode: 481, reasonPhrase: "Call/Transaction Does Not Exist")))]
        }

        let localIP = "10.0.0.2"
        let offered = invite.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
            .map { SDPParser.offeredAudioCodecs($0) } ?? []
        let metSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 50000,
            offeredCodecs: offered,
            preconditionState: PreconditionState(local: .sendrecv, remote: .sendrecv)
        )
        let updateOK = SessionRequestBuilder.makeOK(for: request, sdp: metSDP)
        return [SIPSerializer.serialize(.response(updateOK))]
    }

    private static func handleReInvite(_ request: SIPRequest, profile: OperatorProfile) -> [Data] {
        let offeredSDP = request.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
        let offeredCodecs = offeredSDP.map { SDPParser.offeredAudioCodecs($0) } ?? []
        let direction = offeredSDP.map { SDPMediaParser.mediaDirection(from: $0) } ?? .sendrecv
        let answer = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: "10.0.0.2",
            audioPort: 50000,
            offeredCodecs: offeredCodecs,
            preconditionState: PreconditionState(local: .sendrecv, remote: .sendrecv),
            direction: direction
        )
        return [SIPSerializer.serialize(.response(SessionRequestBuilder.makeOK(for: request, sdp: answer)))]
    }
}
