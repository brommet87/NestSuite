// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// An exclusive, advisory lock on a VM bundle, held while the machine runs.
///
/// Two processes (the app and `nestctl`, or two terminals) running the same machine would write to the
/// same disk image and corrupt it. `flock(2)` locks are released by the kernel when the process exits,
/// even after a crash, so a stale lock can never block a machine forever.
public final class BundleLock: @unchecked Sendable {
    // @unchecked: the file descriptor is only touched in init and `release()`, which is idempotent.
    public enum LockError: Error, Equatable, Sendable {
        case alreadyInUse
        case cannotOpen(errno: Int32)
    }

    private var descriptor: Int32

    /// Acquires the lock or throws ``LockError/alreadyInUse`` immediately (never blocks).
    public init(bundle: VirtualMachineBundle) throws {
        let path = bundle.url.appending(path: ".lock").path(percentEncoded: false)
        descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw LockError.cannotOpen(errno: errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            descriptor = -1
            throw LockError.alreadyInUse
        }
    }

    /// Whether another process currently holds the lock (i.e. the machine is running elsewhere).
    public static func isLocked(_ bundle: VirtualMachineBundle) -> Bool {
        guard let probe = try? BundleLock(bundle: bundle) else { return true }
        probe.release()
        return false
    }

    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
