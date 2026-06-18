import Foundation
import Testing
@testable import SICLientCore

@Test func sdpOfferIncludesPreconditions() throws {
    let profile = try loadFixtureProfile()
    let offer = SDPSessionBuilder.voLTEOffer(
        profile: profile,
        localIP: "127.0.0.1",
        audioPort: 40000,
        preconditionState: PreconditionState(local: .none, remote: .none)
    )
    let text = offer.serialize()
    #expect(text.contains("m=audio 40000 RTP/AVP"))
    #expect(text.contains("a=rtpmap:103 AMR-WB/16000"))
    #expect(text.contains("a=curr:qos local none"))
    #expect(text.contains("a=des:qos mandatory local sendrecv"))
    #expect(text.contains("a=conf:qos remote sendrecv"))
}

@Test func sdpRoundTripPreservesPreconditionState() throws {
    let profile = try loadFixtureProfile()
    let original = SDPSessionBuilder.voLTEAnswer(
        profile: profile,
        localIP: "10.0.0.2",
        audioPort: 50000,
        offeredCodecs: [.amrWB, .telephoneEvent],
        preconditionState: PreconditionState(local: .sendrecv, remote: .sendrecv)
    )
    let parsed = SDPParser.parse(original.serialize())
    #expect(parsed.preconditionState.allMet)
    #expect(SDPParser.offeredAudioCodecs(parsed).contains(.amrWB))
}

@Test func preconditionStateParsing() {
    let attrs = [
        "a=curr:qos local sendrecv",
        "a=curr:qos remote none",
        "a=des:qos mandatory local sendrecv",
    ]
    let state = PreconditionState.parse(from: attrs)
    #expect(state.local.isMet)
    #expect(!state.remote.isMet)
    #expect(!state.allMet)
}
