import Foundation

public struct PlatformContext: Sendable {
    public let sim: any SimAdapter
    public let network: any NetworkAdapter
    public let bearer: any BearerAdapter
    public let accessInfo: any AccessInfoAdapter

    public init(
        sim: any SimAdapter,
        network: any NetworkAdapter,
        bearer: any BearerAdapter,
        accessInfo: any AccessInfoAdapter
    ) {
        self.sim = sim
        self.network = network
        self.bearer = bearer
        self.accessInfo = accessInfo
    }

    public static func stubbed(profile: OperatorProfile) throws -> PlatformContext {
        return PlatformContext(
            sim: SimAdapterFactory.make(profile: profile),
            network: ProductionNetworkAdapter.forProfile(profile),
            bearer: StubBearerAdapter(),
            accessInfo: StubAccessInfoAdapter()
        )
    }
}
