import Foundation

// MARK: - File overview
//
// Securely stores AKA (Authentication and Key Agreement) key material (IK and CK)
// in memory and zeroizes it on wipe or deinit. Prevents sensitive keys from lingering
// in heap memory after logout or deregistration.

/// Holds sensitive AKA key material and zeroizes on deinit (P6.10).
public final class SecureAKAContext: @unchecked Sendable {
    private var ik: Data?
    private var ck: Data?
    private let lock = NSLock()

    /// Creates an empty or pre-filled AKA key context.
    public init(ik: Data? = nil, ck: Data? = nil) {
        self.ik = ik
        self.ck = ck
    }

    /// Replaces stored IK (integrity key) and CK (cipher key) after a successful AKA run.
    public func store(ik: Data, ck: Data) {
        lock.withLock {
            zeroize(&self.ik)
            zeroize(&self.ck)
            self.ik = ik
            self.ck = ck
        }
    }

    /// Overwrites and clears all stored key bytes immediately.
    public func wipe() {
        lock.withLock {
            zeroize(&ik)
            zeroize(&ck)
        }
    }

    deinit {
        wipe()
    }

    /// Fills the buffer with zeros before releasing the reference.
    private func zeroize(_ data: inout Data?) {
        guard var buffer = data else { return }
        buffer.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                memset(base, 0, raw.count)
            }
        }
        data = nil
    }
}
