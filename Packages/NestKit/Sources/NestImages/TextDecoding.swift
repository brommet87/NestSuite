// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

extension Data {
    /// Decodes UTF-8, replacing invalid sequences instead of failing. Server listings, tool output and
    /// guest console logs can contain stray bytes; one bad byte must not make the whole text unreadable.
    var lossyUTF8: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: self, as: UTF8.self)
    }
}
