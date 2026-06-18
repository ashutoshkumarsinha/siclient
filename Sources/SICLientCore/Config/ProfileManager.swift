import Foundation

// MARK: - File overview
//
// Holds the active OperatorProfile in memory and supports hot-reloading when the
// JSON file on disk changes. Security-sensitive fields are not special-cased here;
// the whole profile is replaced on reload.

/// Actor that owns the current operator profile and can reload it from disk.
public actor ProfileManager {
    private var profile: OperatorProfile
    private let profileURL: URL

    /// Starts with an in-memory profile and remembers the file URL for reloads.
    public init(profile: OperatorProfile, profileURL: URL) {
        self.profile = profile
        self.profileURL = profileURL
    }

    /// Returns the profile currently held in memory.
    public func currentProfile() -> OperatorProfile {
        profile
    }

    /// Reloads from disk if the file changed; returns true when the profile was updated.
    public func reloadIfChanged() throws -> Bool {
        let loaded = try ProfileLoader.load(from: profileURL)
        guard loaded != profile else { return false }
        profile = loaded
        return true
    }

    /// Replaces the in-memory profile without reading from disk.
    public func updateProfile(_ newProfile: OperatorProfile) {
        profile = newProfile
    }
}
