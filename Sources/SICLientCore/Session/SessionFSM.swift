import Foundation

public actor SessionFSM {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger
    private let mediaTransportFactory: (@Sendable () -> any RTPTransport)?

    private var activeSession: SessionContext?
    private var pendingInvite: SIPRequest?
    private var activeMedia: MediaSession?

    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger,
        mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil
    ) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
        self.mediaTransportFactory = mediaTransportFactory
    }

    public func activeSessionContext() -> SessionContext? { activeSession }

    public func mediaStats() async -> RTPStreamStats {
        await activeMedia?.stats() ?? RTPStreamStats()
    }

    public func cancelPendingInvite(registration: RegistrationContext) async throws {
        guard let invite = pendingInvite else { throw SessionError.noPendingInvite }
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let cancel = SessionRequestBuilder.makeCANCEL(
            invite: invite,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            securityAssociation: registration.securityAssociation
        )
        try await transport.send(SIPSerializer.serialize(.request(cancel)))

        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if let data = try await transport.receive(timeout: .milliseconds(200)) {
                if case .response(let response) = try? SIPParser.parse(data),
                   response.headers["Call-ID"] == invite.headers["Call-ID"],
                   response.statusCode == 200,
                   response.headers["CSeq"]?.localizedCaseInsensitiveContains("CANCEL") == true {
                    break
                }
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
            }
        }

        if var session = activeSession {
            await cleanupSession(&session)
            activeSession = nil
        }
        pendingInvite = nil
        throw SessionError.inviteCancelled
    }

    public func originateCall(
        to destinationURI: String,
        registration: RegistrationContext
    ) async throws -> SessionContext {
        guard registration.serviceRoute != nil || registration.defaultIMPU != nil else {
            throw SessionError.notRegistered
        }
        guard destinationURI.hasPrefix("sip:") || destinationURI.hasPrefix("tel:") else {
            throw SessionError.invalidDestination
        }

        let impus = try platform.sim.getIMPUList()
        guard let impu = registration.defaultIMPU ?? impus.first else {
            throw SessionError.notRegistered
        }

        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let bearer = try platform.bearer.requestDedicatedBearer(qci: .voice)

        var preconditionState = PreconditionState()
        if profile.preconditions.enabled {
            preconditionState.local = .none
        }

        var dialog = DialogContext()
        dialog.localCSeq = 1
        var session = SessionContext(
            dialog: dialog,
            state: .inviting,
            remoteURI: destinationURI,
            localURI: impu,
            preconditionState: preconditionState,
            bearerHandle: bearer,
            localAudioPort: 40000
        )
        activeSession = session

        let offer = SDPSessionBuilder.voLTEOffer(
            profile: profile,
            localIP: localIP,
            audioPort: 40000,
            preconditionState: preconditionState
        )

        let invite = SessionRequestBuilder.makeInvite(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            destinationURI: destinationURI,
            dialog: dialog,
            registration: registration,
            sdp: offer,
            securityAssociation: registration.securityAssociation
        )
        pendingInvite = invite

        let transaction = InviteClientTransaction(transport: transport, logger: logger)
        let inviteDialog = dialog
        let result = try await transaction.sendInvite(invite) { [profile] provisional in
            guard let rseq = provisional.headers["RSeq"],
                  let cseq = provisional.headers["CSeq"] else { return nil }
            var prackDialog = inviteDialog
            prackDialog.remoteTag = provisional.headers["To"]?.components(separatedBy: "tag=").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
            prackDialog.remoteTarget = destinationURI
            prackDialog.localCSeq = 2
            return SessionRequestBuilder.makePRACK(
                profile: profile,
                impu: impu,
                pani: pani,
                localIP: localIP,
                localPort: 5060,
                dialog: prackDialog,
                rseq: rseq,
                cseq: cseq,
                securityAssociation: registration.securityAssociation
            )
        }

        pendingInvite = nil
        dialog.localCSeq = 2
        session.dialog = dialog
        session.state = .proceeding
        for provisional in result.provisionals where provisional.body != nil {
            let answer = SDPParser.parse(String(decoding: provisional.body!, as: UTF8.self))
            session.preconditionState.remote = answer.preconditionState.remote
            session.negotiatedCodec = SDPParser.offeredAudioCodecs(answer).first(where: { $0 != .telephoneEvent })
        }

        guard (200 ... 299).contains(result.final.statusCode) else {
            await cleanupSession(&session)
            activeSession = nil
            throw SessionError.unexpectedResponse(result.final.statusCode)
        }

        if let body = result.final.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            session.preconditionState = answer.preconditionState
            if session.negotiatedCodec == nil {
                session.negotiatedCodec = SDPParser.offeredAudioCodecs(answer).first(where: { $0 != .telephoneEvent })
            }
        }

        session.dialog.remoteTag = result.final.headers["To"]?.components(separatedBy: "tag=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
        session.dialog.remoteTarget = destinationURI
        session.dialog.recordRoute = result.final.headers.allValues("Record-Route")
        if !session.dialog.recordRoute.isEmpty {
            session.dialog.routeSet = session.dialog.recordRoute.reversed()
        }

        if profile.preconditions.enabled, !session.preconditionState.allMet {
            try await fulfillPreconditionsMO(
                session: &session,
                impu: impu,
                pani: pani,
                localIP: localIP,
                registration: registration
            )
        }

        session.dialog.localCSeq = 1
        let ack = SessionRequestBuilder.makeACK(
            impu: impu, localIP: localIP, localPort: 5060, dialog: session.dialog
        )
        try await transaction.sendAck(ack)

        session.state = .established
        if let body = result.final.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            try await startMedia(session: &session, remoteSDP: answer, localIP: localIP)
        }
        activeSession = session
        logger.info(
            "MO call established",
            fields: [
                "destination": destinationURI,
                "codec": session.negotiatedCodec?.rawValue ?? "",
                "preconditions_met": String(session.preconditionState.allMet),
                "media_started": String(session.remoteMedia != nil),
            ]
        )
        return session
    }

    public func holdActiveCall(registration: RegistrationContext) async throws {
        try await renegotiateMedia(direction: .sendonly, registration: registration)
    }

    public func resumeActiveCall(registration: RegistrationContext) async throws {
        try await renegotiateMedia(direction: .sendrecv, registration: registration)
    }

    private func renegotiateMedia(direction: MediaDirection, registration: RegistrationContext) async throws {
        guard var session = activeSession, session.state == .established else {
            throw SessionError.holdNotAllowed
        }
        let impu = session.localURI
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let codec = session.negotiatedCodec ?? .amrWB
        let port = session.localAudioPort ?? 40000
        session.dialog.localCSeq = session.dialog.nextCSeq()

        let sdp = SDPSessionBuilder.voLTEMediaSDP(
            profile: profile,
            localIP: localIP,
            audioPort: port,
            codec: codec,
            direction: direction,
            preconditionState: session.preconditionState
        )
        let reinvite = SessionRequestBuilder.makeReInvite(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            registration: registration,
            sdp: sdp,
            securityAssociation: registration.securityAssociation
        )

        let transaction = ClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.send(reinvite)
        guard (200 ... 299).contains(response.statusCode) else {
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        session.mediaDirection = direction
        await activeMedia?.setDirection(direction)
        activeSession = session
        logger.info("Call media direction updated", fields: ["direction": direction.rawValue])
    }

    private func startMedia(session: inout SessionContext, remoteSDP: SDPSessionDescription, localIP: String) async throws {
        guard let factory = mediaTransportFactory else { return }
        guard let remote = SDPMediaParser.audioEndpoint(
            from: remoteSDP,
            preferred: AudioCodec.fromProfile(profile.codecs.audio)
        ) else { return }

        let localPort = session.localAudioPort ?? 40000
        let codec = session.negotiatedCodec ?? remote.codec
        let engine = LabAMRCodecEngine(codec: codec)
        let media = MediaSession(transport: factory(), codecEngine: engine)
        do {
            try await media.start(localPort: localPort, remote: remote, direction: session.mediaDirection)
        } catch {
            throw SessionError.mediaFailed(error.localizedDescription)
        }
        activeMedia = media
        session.remoteMedia = remote
    }

    private func fulfillPreconditionsMO(
        session: inout SessionContext,
        impu: String,
        pani: String,
        localIP: String,
        registration: RegistrationContext
    ) async throws {
        session.state = .preconditionWait
        session.preconditionState.local = .sendrecv
        session.dialog.localCSeq = 3

        let updateSDP = SDPSessionBuilder.voLTEOffer(
            profile: profile,
            localIP: localIP,
            audioPort: 40000,
            preconditionState: session.preconditionState
        )
        let update = SessionRequestBuilder.makeUPDATE(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            sdp: updateSDP,
            securityAssociation: registration.securityAssociation
        )

        let transaction = ClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.send(update)
        guard (200 ... 299).contains(response.statusCode) else {
            await cleanupSession(&session)
            activeSession = nil
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        if let body = response.body {
            let answer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            session.preconditionState.remote = answer.preconditionState.local
        }

        guard session.preconditionState.allMet else {
            await cleanupSession(&session)
            activeSession = nil
            throw SessionError.preconditionTimeout
        }
    }

    public func terminateActiveCall(registration: RegistrationContext) async throws {
        guard var session = activeSession else { throw SessionError.noActiveSession }
        try await terminate(session: &session, registration: registration)
        activeSession = nil
    }

    public func handleIncomingInvite(
        _ invite: SIPRequest,
        registration: RegistrationContext
    ) async throws -> SessionContext {
        let localIP = try platform.network.localIPAddress()
        let impu = registration.defaultIMPU ?? invite.headers["To"] ?? ""
        let caller = invite.headers["P-Asserted-Identity"] ?? invite.headers["From"] ?? ""

        let bearer = try platform.bearer.requestDedicatedBearer(qci: .voice)
        var preconditionState = PreconditionState(local: .none, remote: .none)

        if let body = invite.body {
            let offer = SDPParser.parse(String(decoding: body, as: UTF8.self))
            preconditionState.remote = offer.preconditionState.local
        }

        let remoteTag = invite.headers["From"]?.components(separatedBy: "tag=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: ">; "))
        var dialog = DialogContext(
            callID: invite.headers["Call-ID"] ?? UUID().uuidString,
            localTag: String(UUID().uuidString.prefix(8)),
            remoteTag: remoteTag,
            localCSeq: 1,
            remoteCSeq: Int(invite.headers["CSeq"]?.split(separator: " ").first ?? "0"),
            remoteTarget: caller
        )

        var session = SessionContext(
            dialog: dialog,
            state: .proceeding,
            remoteURI: caller,
            localURI: impu,
            preconditionState: preconditionState,
            bearerHandle: bearer
        )
        activeSession = session

        let serverTxn = InviteServerTransaction(transport: transport, logger: logger)
        try await serverTxn.sendResponse(SessionRequestBuilder.makeTrying(for: invite))

        let offered = invite.body.map { SDPParser.parse(String(decoding: $0, as: UTF8.self)) }
            .map { SDPParser.offeredAudioCodecs($0) } ?? []
        let progressSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 40002,
            offeredCodecs: offered,
            preconditionState: preconditionState
        )
        let progress = SessionRequestBuilder.makeSessionProgress(
            for: invite,
            sdp: progressSDP,
            require100rel: profile.preconditions.enabled,
            localTag: dialog.localTag
        )
        try await serverTxn.sendResponse(progress)

        if profile.preconditions.enabled {
            let callID = dialog.callID
            let prack = try await serverTxn.waitForRequest(method: SIPMethod.prack.rawValue, callID: callID)
            try await serverTxn.sendResponse(SessionRequestBuilder.makeOK(for: prack))

            preconditionState.local = .sendrecv
            session.preconditionState = preconditionState

            let update = try await serverTxn.waitForRequest(method: SIPMethod.update.rawValue, callID: callID)
            if let body = update.body {
                let remoteSDP = SDPParser.parse(String(decoding: body, as: UTF8.self))
                preconditionState.remote = remoteSDP.preconditionState.local
            }
            session.preconditionState = preconditionState

            let updateAnswer = SDPSessionBuilder.voLTEAnswer(
                profile: profile,
                localIP: localIP,
                audioPort: 40002,
                offeredCodecs: offered,
                preconditionState: preconditionState
            )
            try await serverTxn.sendResponse(SessionRequestBuilder.makeOK(for: update, sdp: updateAnswer))

            guard session.preconditionState.allMet else {
                await cleanupSession(&session)
                activeSession = nil
                throw SessionError.preconditionTimeout
            }
        }

        let finalSDP = SDPSessionBuilder.voLTEAnswer(
            profile: profile,
            localIP: localIP,
            audioPort: 40002,
            offeredCodecs: offered,
            preconditionState: session.preconditionState
        )
        let ok = SessionRequestBuilder.makeOK(for: invite, sdp: finalSDP)
        try await serverTxn.sendResponse(ok)

        dialog.remoteTarget = caller
        session.dialog = dialog
        session.negotiatedCodec = SDPParser.offeredAudioCodecs(finalSDP).first(where: { $0 != .telephoneEvent })

        _ = try await serverTxn.waitForRequest(method: SIPMethod.ack.rawValue, callID: dialog.callID, timeout: .seconds(2))

        session.state = .established
        session.localAudioPort = 40002
        if let offerBody = invite.body {
            let offerSDP = SDPParser.parse(String(decoding: offerBody, as: UTF8.self))
            try await startMedia(session: &session, remoteSDP: offerSDP, localIP: localIP)
        }
        activeSession = session

        logger.info(
            "MT call established",
            fields: [
                "caller": caller,
                "codec": session.negotiatedCodec?.rawValue ?? "",
                "preconditions_met": String(session.preconditionState.allMet),
            ]
        )
        return session
    }

    private func terminate(session: inout SessionContext, registration: RegistrationContext) async throws {
        session.state = .terminating
        let impu = session.localURI
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        session.dialog.localCSeq = 3

        let bye = SessionRequestBuilder.makeBYE(
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            dialog: session.dialog,
            securityAssociation: registration.securityAssociation
        )

        let transaction = InviteClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.sendRequest(bye)
        guard (200 ... 299).contains(response.statusCode) else {
            throw SessionError.unexpectedResponse(response.statusCode)
        }

        await cleanupSession(&session)
        session.state = .terminated
        logger.info("Call terminated", fields: ["call_id": session.dialog.callID])
    }

    private func cleanupSession(_ session: inout SessionContext) async {
        if let media = activeMedia {
            await media.stop()
            activeMedia = nil
        }
        if let bearer = session.bearerHandle {
            try? platform.bearer.releaseBearer(bearer)
            session.bearerHandle = nil
        }
        session.state = .terminated
    }
}
