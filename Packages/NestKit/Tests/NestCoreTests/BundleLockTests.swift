// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestCore

@Suite("BundleLock")
struct BundleLockTests {
    let directory: TemporaryDirectory
    let bundle: VirtualMachineBundle

    init() throws {
        directory = try TemporaryDirectory()
        bundle = try VirtualMachineLibrary(rootURL: directory.url).createBundle(for: .fixture())
    }

    @Test("a second lock on the same bundle fails immediately")
    func exclusive() throws {
        let first = try BundleLock(bundle: bundle)
        #expect(throws: BundleLock.LockError.alreadyInUse) { try BundleLock(bundle: bundle) }
        #expect(BundleLock.isLocked(bundle))
        first.release()
        #expect(!BundleLock.isLocked(bundle))
    }

    @Test("releasing is idempotent and deinit releases too")
    func release() throws {
        do {
            let lock = try BundleLock(bundle: bundle)
            lock.release()
            lock.release()
        }
        do {
            _ = try BundleLock(bundle: bundle)
        }
        #expect(!BundleLock.isLocked(bundle))
    }
}
