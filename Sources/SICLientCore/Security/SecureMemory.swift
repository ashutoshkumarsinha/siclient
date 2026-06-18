import Foundation

/// Holds sensitive AKA key material and zeroizes on deinit (P6.10).
public final class SecureAKAContext: @unchecked Sendable {
    private var ik: Data?
    private var ck: Data?
    private let lock = NSLock()

    public init(ik: Data? = nil, ck: Data? = nil) {
        self.ik = ik
        self.ck = ck
    }

    public func store(ik: Data, ck: Data) {
        lock.withLock {
            zeroize(&self.ik)
            zeroize(&self.ck)
            self.ik = ik
            self.ck = ck
        }
    }

    public func wipe() {
        lock.withLock {
            zeroize(&ik)
            zeroize(&ck)
        }
    }

    deinit {
        wipe()
    }

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
