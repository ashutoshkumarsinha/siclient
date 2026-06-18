import Foundation
import Testing
@testable import SICLientCore

@Test func moCallWithPreconditionsAgainstMockIMS() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
    }

    let collector = LineCollector()
    let logger = Logger(
        correlationID: CorrelationID(prefix: "mo"),
        output: { collector.append($0) }
    )
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(profile: profile, platform: platform, transport: transport, logger: logger, enableMedia: false)

    try await service.register(expires: 60)
    let destination = "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org"
    let session = try await service.placeCall(to: destination)

    #expect(session.state == .established)
    #expect(session.preconditionState.allMet)
    #expect(session.negotiatedCodec == .amrWB)
    #expect(state.prackCount == 1)
    #expect(state.updateCount == 1)

    let bearer = platform.bearer as? StubBearerAdapter
    #expect(bearer?.activeBearerCount == 1)

    try await service.hangUp()
    #expect(state.byeCount == 1)
    #expect(bearer?.activeBearerCount == 0)

    let logs = collector.snapshot.joined()
    #expect(logs.contains("MO call established"))
    #expect(logs.contains("preconditions_met"))
    #expect(logs.contains("Call terminated"))
}

@Test func callServiceRegistersWithMockIMS() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(profile: profile, platform: platform, transport: transport, logger: logger, enableMedia: false)
    try await service.register(expires: 60)
    #expect(await service.registrationState() == .registered)
}

@Test func mtIncomingInviteHandling() async throws {
    let profile = try loadFixtureProfile()
    let offer = SDPSessionBuilder.voLTEOffer(
        profile: profile,
        localIP: "10.0.0.3",
        audioPort: 40100,
        preconditionState: PreconditionState(local: .sendrecv, remote: .none)
    )
    var inviteHeaders = SIPHeaders()
    inviteHeaders.set("Via", value: "SIP/2.0/UDP 10.0.0.3:5060;branch=z9hG4bK-mt")
    inviteHeaders.set("From", value: "<sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org>;tag=mtcaller")
    inviteHeaders.set("To", value: "<sip:001010123456789@ims.mnc001.mcc001.3gppnetwork.org>")
    inviteHeaders.set("Call-ID", value: "mt-call-1")
    inviteHeaders.set("CSeq", value: "1 INVITE")
    inviteHeaders.set("P-Asserted-Identity", value: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    let invite = SIPRequest(
        method: SIPMethod.invite.rawValue,
        requestURI: "sip:001010123456789@ims.mnc001.mcc001.3gppnetwork.org",
        headers: inviteHeaders,
        body: Data(offer.serialize().utf8)
    )

    let transport = LoopbackSIPTransport { sentData in
        MTNetworkLoopback.replies(to: sentData, invite: invite, profile: profile)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let sessionFSM = SessionFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    let registration = RegistrationContext(
        serviceRoute: "<sip:pcscf.ims.mnc001.mcc001.3gppnetwork.org;lr>",
        defaultIMPU: "sip:001010123456789@ims.mnc001.mcc001.3gppnetwork.org",
        expiresSec: 3600
    )

    let session = try await sessionFSM.handleIncomingInvite(invite, registration: registration)
    #expect(session.state == .established)
    #expect(session.preconditionState.allMet)
}

@Test func inviteTransactionRequiresPRACKFor183() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
    }

    let registration = RegistrationContext(
        serviceRoute: "<sip:pcscf.ims.mnc001.mcc001.3gppnetwork.org;lr>",
        defaultIMPU: "sip:001010123456789@ims.mnc001.mcc001.3gppnetwork.org"
    )
    let platform = try PlatformContext.stubbed(profile: profile)
    let impu = try platform.sim.getIMPUList().first!
    let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
    let localIP = try platform.network.localIPAddress()
    let dialog = DialogContext()
    let offer = SDPSessionBuilder.voLTEOffer(profile: profile, localIP: localIP, audioPort: 40000)

    let invite = SessionRequestBuilder.makeInvite(
        profile: profile,
        impu: impu,
        pani: pani,
        localIP: localIP,
        localPort: 5060,
        destinationURI: "sip:callee@ims.mnc001.mcc001.3gppnetwork.org",
        dialog: dialog,
        registration: registration,
        sdp: offer
    )

    let txn = InviteClientTransaction(transport: transport)
    let result = try await txn.sendInvite(invite) { provisional in
        guard let rseq = provisional.headers["RSeq"], let cseq = provisional.headers["CSeq"] else { return nil }
        var prackDialog = dialog
        prackDialog.localCSeq = 2
        prackDialog.remoteTarget = "sip:callee@ims.mnc001.mcc001.3gppnetwork.org"
        return SessionRequestBuilder.makePRACK(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: prackDialog,
            rseq: rseq,
            cseq: cseq
        )
    }

    #expect(result.provisionals.contains(where: { $0.statusCode == 183 }))
    #expect(result.final.statusCode == 200)
    #expect(state.prackCount == 1)
}

@Test func cancelPendingInvite() async throws {
    let profile = try loadFixtureProfile()
    final class CancelState: @unchecked Sendable {
        var lastInvite: SIPRequest?
    }
    let cancelState = CancelState()

    let transport = LoopbackSIPTransport { data in
        guard case .request(let request) = try? SIPParser.parse(data) else { return [] }
        switch request.method {
        case SIPMethod.register.rawValue:
            return MockIMSResponder.responses(for: data, profile: profile, state: MockIMSState())
        case SIPMethod.invite.rawValue:
            cancelState.lastInvite = request
            return []
        case SIPMethod.cancel.rawValue:
            var responses: [Data] = [
                SIPSerializer.serialize(.response(SessionRequestBuilder.makeOK(for: request))),
            ]
            if let invite = cancelState.lastInvite {
                let terminated = SIPResponse(
                    statusCode: 487,
                    reasonPhrase: "Request Terminated",
                    headers: invite.headers
                )
                responses.append(SIPSerializer.serialize(.response(terminated)))
            }
            return responses
        default:
            return []
        }
    }

    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        enableMedia: false
    )
    try await service.register(expires: 60)

    let callTask = Task {
        try await service.placeCall(to: "sip:callee@ims.mnc001.mcc001.3gppnetwork.org")
    }

    try await Task.sleep(for: .milliseconds(30))

    do {
        try await service.cancelCall()
        Issue.record("Expected inviteCancelled")
    } catch SessionError.inviteCancelled {
        // expected
    }

    let result = await callTask.result
    if case .failure(let error as SessionError) = result {
        switch error {
        case .unexpectedResponse(487), .inviteCancelled:
            break
        default:
            Issue.record("Unexpected SessionError: \(error)")
        }
    } else if case .failure(let error as ClientTransactionError) = result {
        if case .timeout = error { /* acceptable race */ } else {
            Issue.record("Unexpected ClientTransactionError: \(error)")
        }
    } else if case .success = result {
        Issue.record("placeCall should not succeed after cancel")
    }
}

@Test func holdActiveCallSignaling() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let bridge = LoopbackRTPBridge()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        mediaTransportFactory: MediaBootstrap.sharedLoopbackFactory(bridge: bridge)
    )

    try await service.register(expires: 60)
    _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")

    try await service.hold()
    #expect(await service.activeSession()?.mediaDirection == .sendonly)

    try await service.resume()
    #expect(await service.activeSession()?.mediaDirection == .sendrecv)

    try await service.hangUp()
}

private enum MTNetworkLoopback {
    static func replies(to sentData: Data, invite: SIPRequest, profile: OperatorProfile) -> [Data] {
        guard case .response(let response) = try? SIPParser.parse(sentData) else { return [] }

        if response.statusCode == 183 {
            guard let rseq = response.headers["RSeq"],
                  let cseq = invite.headers["CSeq"] else { return [] }
            var dialog = DialogContext(
                callID: invite.headers["Call-ID"] ?? "",
                localTag: "net-uac",
                remoteTag: response.headers["To"]?.components(separatedBy: "tag=").last?
                    .trimmingCharacters(in: CharacterSet(charactersIn: ">; ")),
                localCSeq: 2,
                remoteTarget: invite.headers["From"] ?? ""
            )
            let prack = SessionRequestBuilder.makePRACK(
                profile: profile,
                impu: invite.headers["From"] ?? "",
                pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=234150999010203",
                localIP: "10.0.0.3",
                localPort: 5060,
                dialog: dialog,
                rseq: rseq,
                cseq: cseq
            )
            return [SIPSerializer.serialize(.request(prack))]
        }

        if response.statusCode == 200,
           response.headers["CSeq"]?.localizedCaseInsensitiveContains("PRACK") == true {
            var dialog = DialogContext(
                callID: invite.headers["Call-ID"] ?? "",
                localTag: "net-uac",
                remoteTag: response.headers["To"]?.components(separatedBy: "tag=").last?
                    .trimmingCharacters(in: CharacterSet(charactersIn: ">; ")),
                localCSeq: 3,
                remoteTarget: invite.headers["From"] ?? ""
            )
            let updateSDP = SDPSessionBuilder.voLTEOffer(
                profile: profile,
                localIP: "10.0.0.3",
                audioPort: 40100,
                preconditionState: PreconditionState(local: .sendrecv, remote: .none)
            )
            let update = SessionRequestBuilder.makeUPDATE(
                profile: profile,
                impu: invite.headers["From"] ?? "",
                pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=234150999010203",
                localIP: "10.0.0.3",
                localPort: 5060,
                dialog: dialog,
                sdp: updateSDP
            )
            return [SIPSerializer.serialize(.request(update))]
        }

        if response.statusCode == 200,
           response.headers["CSeq"]?.localizedCaseInsensitiveContains("INVITE") == true {
            var ackHeaders = SIPHeaders()
            ackHeaders.set("Via", value: "SIP/2.0/UDP 10.0.0.3:5060;branch=z9hG4bK-ack")
            ackHeaders.set("From", value: invite.headers["From"] ?? "")
            ackHeaders.set("To", value: response.headers["To"] ?? "")
            ackHeaders.set("Call-ID", value: invite.headers["Call-ID"] ?? "")
            ackHeaders.set("CSeq", value: "1 ACK")
            let ack = SIPRequest(
                method: SIPMethod.ack.rawValue,
                requestURI: invite.requestURI,
                headers: ackHeaders
            )
            return [SIPSerializer.serialize(.request(ack))]
        }

        return []
    }
}
