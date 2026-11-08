// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Testing
@testable import NestImages

@Suite("SHA-512-crypt")
struct SHA512CryptTests {
    /// Reference values: the first two are from the specification; all three were reproduced with
    /// `openssl passwd -6 -salt <salt> <password>` (OpenSSL 3.6).
    @Test("matches the reference vectors", arguments: [
        (
            "Hello world!", "saltstring",
            "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1"
        ),
        (
            "Hello world!", "rounds=10000$saltstringsaltstring",
            "$6$rounds=10000$saltstringsaltst$"
                + "OW1/O6BYHV6BcXZu8QVeXbDWra3Oeqh0sbHbbMCVNSnCM/UrjmM0Dp8vOuZeHBy/YTBmSK6H9qs/y3RnOaw5v."
        ),
        (
            "Grüße aus dem Nest – ein langes Passwort mit über 64 Zeichen, damit mehrere Blöcke nötig sind!",
            "NestSuite1234567",
            "$6$NestSuite1234567$D/2COkmoSzllkz9kPkIOqb65KbFxzNHdqU0Pm7uSdzgnlx7H/KAQcggg2NL0TI/Ncd5R71cjEy.ac3yC4xNRU1"
        ),
    ])
    func vectors(password: String, salt: String, expected: String) {
        #expect(SHA512Crypt.hash(password, salt: salt) == expected)
    }

    @Test("random salts differ and never contain the password")
    func randomSalt() {
        let first = SHA512Crypt.hash("secret")
        let second = SHA512Crypt.hash("secret")
        #expect(first != second)
        #expect(first.hasPrefix("$6$"))
        #expect(!first.contains("secret"))
    }
}
