import Foundation

public actor ProfileManager {
    private var profile: OperatorProfile
    private let profileURL: URL

    public init(profile: OperatorProfile, profileURL: URL) {
        self.profile = profile
        self.profileURL = profileURL
    }

    public func currentProfile() -> OperatorProfile {
        profile
    }

    /// Reload non-security profile fields from disk (P6.10).
    public func reloadIfChanged() throws -> Bool {
        let loaded = try ProfileLoader.load(from: profileURL)
        guard loaded != profile else { return false }
        profile = loaded
        return true
    }

    public func updateProfile(_ newProfile: OperatorProfile) {
        profile = newProfile
    }
}
