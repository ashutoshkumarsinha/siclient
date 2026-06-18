import Foundation

public enum EmergencyRequestBuilder {
    public static func makeEmergencyRegister(
        profile: OperatorProfile,
        impi: String,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        context: RegistrationContext,
        credentials: DigestCredentials? = nil,
        expires: Int = 3600
    ) -> SIPRequest {
        var request = RegisterRequestBuilder.makeRegister(
            profile: profile,
            impi: impi,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: localPort,
            context: context,
            credentials: credentials,
            expires: expires,
            securityAssociation: context.securityAssociation
        )

        let sosURI = profile.services.emergency.sosURI
        let registrar = sosURI.hasPrefix("sip:") ? sosURI : "sip:sos@\(profile.homeDomain)"
        request.requestURI = registrar
        request.headers.set("Contact", value: emergencyContact(impu: impu, expires: expires))
        request.headers.set("Priority", value: "emergency")
        request.headers.set("Resource-Priority", value: "wps.4")
        request.headers.set("P-Emergency-Info", value: "urn:service:sos")
        return request
    }

    public static func makeEmergencyInvite(
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
        var invite = SessionRequestBuilder.makeInvite(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: localPort,
            destinationURI: destinationURI,
            dialog: dialog,
            registration: registration,
            sdp: sdp,
            securityAssociation: securityAssociation
        )
        invite.headers.set("Priority", value: "emergency")
        invite.headers.set("Resource-Priority", value: "wps.4")
        invite.headers.set("P-Emergency-Info", value: "urn:service:sos")
        return invite
    }

    private static func emergencyContact(impu: String, expires: Int) -> String {
        "<\(impu)>;expires=\(expires);+g.3gpp.emergency;+g.3gpp.icsi-ref=\"\(IMSHeaderBuilder.preferredServiceMMTel())\""
    }
}
