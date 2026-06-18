import Foundation

// MARK: - File overview
//
// Loads and validates operator profile JSON files. An operator profile describes
// how this IMS (IP Multimedia Subsystem) client connects to a carrier network:
// P-CSCF (Proxy Call Session Control Function) address, security, codecs, and timers.

/// Errors that can occur while loading a profile from disk.
public enum ProfileLoaderError: Error, Sendable, CustomStringConvertible {
    case fileNotFound(String)
    case readFailed(String, underlying: Error)
    case decodeFailed(String, underlying: Error)
    case validationFailed(String, underlying: ProfileValidationError)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Profile not found: \(path)"
        case .readFailed(let path, let underlying):
            return "Failed to read profile at \(path): \(underlying)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode profile at \(path): \(underlying)"
        case .validationFailed(let path, let underlying):
            return "Profile validation failed for \(path): \(underlying)"
        }
    }
}

/// Reads operator profile JSON from a file URL, decodes it, and validates fields.
public enum ProfileLoader {
    /// Loads, decodes, and validates a profile from a file URL.
    public static func load(from url: URL) throws -> OperatorProfile {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProfileLoaderError.fileNotFound(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProfileLoaderError.readFailed(path, underlying: error)
        }

        let decoder = JSONDecoder()
        let profile: OperatorProfile
        do {
            profile = try decoder.decode(OperatorProfile.self, from: data)
        } catch {
            throw ProfileLoaderError.decodeFailed(path, underlying: error)
        }

        do {
            try ProfileValidator.validate(profile)
        } catch let error as ProfileValidationError {
            throw ProfileLoaderError.validationFailed(path, underlying: error)
        }

        return profile
    }

    /// Convenience loader that accepts a filesystem path string.
    public static func load(fromPath path: String) throws -> OperatorProfile {
        let url = URL(fileURLWithPath: path)
        return try load(from: url)
    }
}
