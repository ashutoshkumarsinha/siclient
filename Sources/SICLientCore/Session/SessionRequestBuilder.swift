import Foundation

public enum SessionRequestBuilder {
    public static func makeInvite(
        profile: OperatorProfile,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        destinationURI: String,
        dialog: DialogContext,
        registration: RegistrationContext,
        sdp: SDPSessionDescription,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let requestURI = destinationURI
        let sdpBody = Data(sdp.serialize().utf8)

        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: "<\(destinationURI)>")
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) INVITE")
        headers.set("Contact", value: IMSHeaderBuilder.contact(impu: impu, expires: registration.expiresSec))
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("P-Preferred-Identity", value: impu)
        headers.set("P-Preferred-Service", value: IMSHeaderBuilder.preferredServiceMMTel())
        headers.set("Allow", value: IMSHeaderBuilder.allowRegistration())
        headers.set("Supported", value: supportedSession(profile: profile))
        if profile.preconditions.enabled {
            headers.set("Require", value: "precondition")
        }
        if let serviceRoute = registration.serviceRoute {
            headers.set("Route", value: serviceRoute)
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        headers.set("Content-Type", value: "application/sdp")

        return SIPRequest(method: SIPMethod.invite.rawValue, requestURI: requestURI, headers: headers, body: sdpBody)
    }

    public static func makeReInvite(
        profile: OperatorProfile,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        dialog: DialogContext,
        registration: RegistrationContext,
        sdp: SDPSessionDescription,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let requestURI = remoteRequestURI(dialog)
        let sdpBody = Data(sdp.serialize().utf8)

        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: dialogToHeader(dialog))
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) INVITE")
        headers.set("Contact", value: IMSHeaderBuilder.contact(impu: impu, expires: registration.expiresSec))
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("Supported", value: supportedSession(profile: profile))
        if !dialog.routeSet.isEmpty {
            headers.set("Route", value: dialog.routeSet.joined(separator: ", "))
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        headers.set("Content-Type", value: "application/sdp")
        return SIPRequest(method: SIPMethod.invite.rawValue, requestURI: requestURI, headers: headers, body: sdpBody)
    }

    private static func dialogToHeader(_ dialog: DialogContext) -> String {
        guard let target = dialog.remoteTarget, !target.isEmpty else {
            if let tag = dialog.remoteTag, !tag.isEmpty { return "<>;tag=\(tag)" }
            return "<>"
        }
        let bare = target.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        if let tag = dialog.remoteTag, !tag.isEmpty {
            return "<\(bare)>;tag=\(tag)"
        }
        return "<\(bare)>"
    }

    private static func remoteRequestURI(_ dialog: DialogContext) -> String {
        guard let target = dialog.remoteTarget, !target.isEmpty else { return "sip:invalid.invalid" }
        return target.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    public static func makePRACK(
        profile: OperatorProfile,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        dialog: DialogContext,
        rseq: String,
        cseq: String,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let remoteURI = remoteRequestURI(dialog)
        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: dialogToHeader(dialog))
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) PRACK")
        headers.set("RAck", value: "\(rseq) \(cseq)")
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("Supported", value: supportedSession(profile: profile))
        if !dialog.routeSet.isEmpty {
            headers.set("Route", value: dialog.routeSet.joined(separator: ", "))
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        return SIPRequest(method: SIPMethod.prack.rawValue, requestURI: remoteURI, headers: headers)
    }

    public static func makeUPDATE(
        profile: OperatorProfile,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        dialog: DialogContext,
        sdp: SDPSessionDescription,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let remoteURI = remoteRequestURI(dialog)
        let sdpBody = Data(sdp.serialize().utf8)
        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: dialogToHeader(dialog))
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) UPDATE")
        headers.set("Contact", value: "<\(impu)>")
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("Supported", value: supportedSession(profile: profile))
        if !dialog.routeSet.isEmpty {
            headers.set("Route", value: dialog.routeSet.joined(separator: ", "))
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        headers.set("Content-Type", value: "application/sdp")
        return SIPRequest(method: SIPMethod.update.rawValue, requestURI: remoteURI, headers: headers, body: sdpBody)
    }

    public static func makeACK(
        impu: String,
        localIP: String,
        localPort: Int,
        dialog: DialogContext
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let remoteURI = remoteRequestURI(dialog)
        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: dialogToHeader(dialog))
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) ACK")
        if !dialog.routeSet.isEmpty {
            headers.set("Route", value: dialog.routeSet.joined(separator: ", "))
        }
        return SIPRequest(method: SIPMethod.ack.rawValue, requestURI: remoteURI, headers: headers)
    }

    public static func makeCANCEL(
        invite: SIPRequest,
        pani: String,
        localIP: String,
        localPort: Int,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: invite.headers["From"] ?? "")
        headers.set("To", value: invite.headers["To"] ?? "")
        headers.set("Call-ID", value: invite.headers["Call-ID"] ?? "")
        if let cseq = invite.headers["CSeq"] {
            let number = cseq.split(separator: " ").first.map(String.init) ?? "1"
            headers.set("CSeq", value: "\(number) CANCEL")
        }
        headers.set("P-Access-Network-Info", value: pani)
        if let route = invite.headers["Route"] {
            headers.set("Route", value: route)
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        return SIPRequest(method: SIPMethod.cancel.rawValue, requestURI: invite.requestURI, headers: headers)
    }

    public static func makeBYE(
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        dialog: DialogContext,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let remoteURI = remoteRequestURI(dialog)
        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(dialog.localTag)")
        headers.set("To", value: dialogToHeader(dialog))
        headers.set("Call-ID", value: dialog.callID)
        headers.set("CSeq", value: "\(dialog.localCSeq) BYE")
        headers.set("P-Access-Network-Info", value: pani)
        if !dialog.routeSet.isEmpty {
            headers.set("Route", value: dialog.routeSet.joined(separator: ", "))
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }
        return SIPRequest(method: SIPMethod.bye.rawValue, requestURI: remoteURI, headers: headers)
    }

    public static func makeTrying(for invite: SIPRequest) -> SIPResponse {
        response(from: invite, statusCode: 100, reasonPhrase: "Trying")
    }

    public static func makeSessionProgress(
        for invite: SIPRequest,
        sdp: SDPSessionDescription,
        require100rel: Bool,
        localTag: String? = nil
    ) -> SIPResponse {
        var response = response(from: invite, statusCode: 183, reasonPhrase: "Session Progress")
        if let localTag {
            let to = invite.headers["To"] ?? ""
            if !to.contains("tag=") {
                response.headers.set("To", value: "\(to);tag=\(localTag)")
            }
        }
        if require100rel {
            response.headers.set("Require", value: "100rel")
            response.headers.set("RSeq", value: "1")
        }
        let body = Data(sdp.serialize().utf8)
        response.body = body
        response.headers.set("Content-Type", value: "application/sdp")
        return response
    }

    public static func makeOK(for request: SIPRequest, sdp: SDPSessionDescription? = nil) -> SIPResponse {
        var response = response(from: request, statusCode: 200, reasonPhrase: "OK")
        if let sdp {
            response.body = Data(sdp.serialize().utf8)
            response.headers.set("Content-Type", value: "application/sdp")
        }
        return response
    }

    private static func response(from request: SIPRequest, statusCode: Int, reasonPhrase: String) -> SIPResponse {
        var headers = SIPHeaders()
        headers.set("Via", value: request.headers["Via"] ?? "")
        headers.set("From", value: request.headers["From"] ?? "")
        let to = request.headers["To"] ?? ""
        headers.set("To", value: statusCode >= 200 && !to.contains("tag=") ? "\(to);tag=\(UUID().uuidString.prefix(8))" : to)
        headers.set("Call-ID", value: request.headers["Call-ID"] ?? "")
        headers.set("CSeq", value: request.headers["CSeq"] ?? "")
        return SIPResponse(statusCode: statusCode, reasonPhrase: reasonPhrase, headers: headers)
    }

    private static func supportedSession(profile: OperatorProfile) -> String {
        var values = ["100rel", "timer", "replaces"]
        if profile.preconditions.enabled {
            values.insert("precondition", at: 0)
        }
        return values.joined(separator: ", ")
    }
}
