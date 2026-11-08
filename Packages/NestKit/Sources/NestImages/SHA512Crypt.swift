// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import CryptoKit
import Foundation
import Security

/// SHA-512-crypt (`$6$`), the password hash format of Linux `/etc/shadow`.
///
/// Used so a machine’s password never appears in plain text in its cloud-init seed. Implements
/// Ulrich Drepper’s published specification; verified against its reference vectors and OpenSSL.
public enum SHA512Crypt {
    static let alphabet = Array("./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    static let defaultRounds = 5000

    /// Hashes a password with a fresh random 16-character salt.
    public static func hash(_ password: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let salt = String(bytes: bytes.map { alphabet[Int($0) % alphabet.count] }, encoding: .ascii) ?? ""
        return hash(password, salt: salt)
    }

    /// Hashes with a given salt specification: `salt` or `rounds=N$salt` (salt is cut to 16 characters).
    public static func hash(_ password: String, salt saltSpec: String) -> String {
        var rounds = defaultRounds
        var customRounds = false
        var saltPart = Substring(saltSpec)
        if saltPart.hasPrefix("rounds="), let dollar = saltPart.firstIndex(of: "$"),
           let value = Int(saltPart[saltPart.index(saltPart.startIndex, offsetBy: 7) ..< dollar])
        {
            rounds = min(max(value, 1000), 999_999_999)
            customRounds = true
            saltPart = saltPart[saltPart.index(after: dollar)...]
        }
        let salt = Array(saltPart.prefix(16).utf8)
        let key = Array(password.utf8)

        // Digest B
        let digestB = sha512(key + salt + key)
        // Digest A
        var contextA = key + salt + repeated(digestB, toLength: key.count)
        var length = key.count
        while length > 0 {
            contextA += length & 1 != 0 ? digestB : key
            length >>= 1
        }
        let digestA = sha512(contextA)
        // P and S sequences
        let digestDP = sha512(Array(repeating: key, count: key.count).flatMap(\.self))
        let sequenceP = repeated(digestDP, toLength: key.count)
        let digestDS = sha512(Array(repeating: salt, count: 16 + Int(digestA[0])).flatMap(\.self))
        let sequenceS = repeated(digestDS, toLength: salt.count)

        var current = digestA
        for round in 0 ..< rounds {
            var context: [UInt8] = round & 1 != 0 ? sequenceP : current
            if !round.isMultiple(of: 3) {
                context += sequenceS
            }
            if !round.isMultiple(of: 7) {
                context += sequenceP
            }
            context += round & 1 != 0 ? current : sequenceP
            current = sha512(context)
        }

        let prefix = customRounds ? "$6$rounds=\(rounds)$" : "$6$"
        return prefix + (String(bytes: salt, encoding: .utf8) ?? "") + "$" + encode(current)
    }

    // MARK: - Helpers

    private static func sha512(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA512.hash(data: bytes))
    }

    /// The digest repeated (and cut) to the given length.
    private static func repeated(_ digest: [UInt8], toLength length: Int) -> [UInt8] {
        (0 ..< length).map { digest[$0 % digest.count] }
    }

    /// The specification’s custom base-64 with its fixed byte permutation.
    static func encode(_ digest: [UInt8]) -> String {
        // Each group of three digest bytes becomes four characters.
        let groups: [[Int]] = [
            [0, 21, 42], [22, 43, 1], [44, 2, 23], [3, 24, 45], [25, 46, 4], [47, 5, 26], [6, 27, 48],
            [28, 49, 7], [50, 8, 29], [9, 30, 51], [31, 52, 10], [53, 11, 32], [12, 33, 54], [34, 55, 13],
            [56, 14, 35], [15, 36, 57], [37, 58, 16], [59, 17, 38], [18, 39, 60], [40, 61, 19], [62, 20, 41],
        ]
        var output: [UInt8] = []
        func append(_ value: Int, characters: Int) {
            var value = value
            for _ in 0 ..< characters {
                output.append(alphabet[value & 0x3F])
                value >>= 6
            }
        }
        for group in groups {
            append(Int(digest[group[0]]) << 16 | Int(digest[group[1]]) << 8 | Int(digest[group[2]]), characters: 4)
        }
        append(Int(digest[63]), characters: 2)
        return String(bytes: output, encoding: .ascii) ?? ""
    }
}
