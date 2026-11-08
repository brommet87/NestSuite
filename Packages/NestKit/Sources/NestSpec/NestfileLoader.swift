// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Yams

/// A problem in a Nestfile, located by key path and line so editors and CI logs point to the spot.
public struct NestfileError: Error, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case syntax(String)
        case unsupportedVersion(Int)
        case missingKey(String)
        case unknownKey(String, suggestion: String?)
        case typeMismatch(expected: String)
        case invalidValue(String)
    }

    /// Dotted key path, e.g. `machines.dev.memory`.
    public let path: String
    /// 1-based line in the file, when known.
    public let line: Int?
    public let kind: Kind

    public init(path: String, line: Int?, kind: Kind) {
        self.path = path
        self.line = line
        self.kind = kind
    }
}

extension NestfileError: CustomStringConvertible {
    public var description: String {
        let location = [path.isEmpty ? nil : path, line.map { "line \($0)" }].compactMap(\.self).joined(separator: ", ")
        let prefix = location.isEmpty ? "" : "\(location): "
        return prefix + message
    }

    public var message: String {
        switch kind {
        case let .syntax(detail): "invalid YAML — \(detail)"
        case let .unsupportedVersion(version):
            "version \(version) is not supported; this nestctl reads version \(Nestfile.supportedVersion)"
        case let .missingKey(key): "missing required key “\(key)”"
        case let .unknownKey(key, suggestion):
            "unknown key “\(key)”" + (suggestion.map { " — did you mean “\($0)”?" } ?? "")
        case let .typeMismatch(expected): "expected \(expected)"
        case let .invalidValue(reason): reason
        }
    }
}

/// Reads `Nestfile.yml` files. Strict on purpose: unknown keys are errors (with suggestions), so a
/// typo like `memroy` never silently falls back to a default.
public enum NestfileLoader {
    /// Finds a Nestfile in `directory` using the default file names.
    public static func locate(in directory: URL, fileManager: FileManager = .default) -> URL? {
        Nestfile.defaultFileNames
            .map { directory.appending(path: $0) }
            .first { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    public static func load(contentsOf url: URL) throws -> Nestfile {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text, url: url)
    }

    public static func parse(_ text: String, url: URL) throws(NestfileError) -> Nestfile {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: text) else {
                throw NestfileError(path: "", line: nil, kind: .missingKey("version"))
            }
            root = node
        } catch let error as NestfileError {
            throw error
        } catch {
            throw NestfileError(path: "", line: nil, kind: .syntax(String(describing: error)))
        }

        let reader = NodeReader(baseURL: url.deletingLastPathComponent())
        let top = try reader.mapping(root, path: "", allowed: ["version", "machines"])

        let versionNode = try reader.required(top, "version", path: "")
        let version = try reader.int(versionNode, path: "version")
        guard version == Nestfile.supportedVersion else {
            throw NestfileError(path: "version", line: versionNode.line, kind: .unsupportedVersion(version))
        }

        let machinesNode = try reader.required(top, "machines", path: "")
        guard case let .mapping(machinesMapping) = machinesNode, !machinesMapping.isEmpty else {
            throw NestfileError(
                path: "machines", line: machinesNode.line,
                kind: .typeMismatch(expected: "a mapping of machine names to definitions")
            )
        }

        var machines: [MachineSpec] = []
        for (keyNode, valueNode) in machinesMapping {
            let name = try reader.string(keyNode, path: "machines")
            try machines.append(reader.machine(named: name, node: valueNode))
        }
        return Nestfile(url: url, version: version, machines: machines)
    }
}

// MARK: - Node reading

private struct NodeReader {
    let baseURL: URL

    static let machineKeys = [
        "guest", "image", "cpus", "memory", "disk", "rosetta", "clipboard", "network",
        "shares", "ports", "provision", "hooks",
    ]

    func machine(named name: String, node: Node) throws(NestfileError) -> MachineSpec {
        let path = "machines.\(name)"
        try validateMachineName(name, path: path, line: node.line)
        let map = try mapping(node, path: path, allowed: Self.machineKeys)

        let guestNode = try required(map, "guest", path: path)
        let guestText = try string(guestNode, path: "\(path).guest")
        guard let guest = GuestOperatingSystem(rawValue: guestText) else {
            throw NestfileError(
                path: "\(path).guest", line: guestNode.line,
                kind: .invalidValue("“\(guestText)” is not a supported guest; use “linux” or “macOS”")
            )
        }

        var spec = MachineSpec(name: name, guest: guest, line: node.line)
        try readResources(map, path: path, into: &spec)
        try readIntegration(map, path: path, into: &spec)
        return spec
    }

    // MARK: Sections

    func readResources(_ map: [String: Node], path: String, into spec: inout MachineSpec) throws(NestfileError) {
        if let image = map["image"] {
            spec.image = try string(image, path: "\(path).image")
        }
        if let cpus = map["cpus"] {
            spec.cpus = try amount(cpus, path: "\(path).cpus", parse: positiveInt)
        }
        if let memory = map["memory"] {
            spec.memory = try amount(memory, path: "\(path).memory", parse: size)
        }
        if let disk = map["disk"] {
            spec.disk = try amount(disk, path: "\(path).disk", parse: size)
        }
        if let rosetta = map["rosetta"] {
            spec.rosetta = try bool(rosetta, path: "\(path).rosetta")
        }
    }

    func readIntegration(_ map: [String: Node], path: String, into spec: inout MachineSpec) throws(NestfileError) {
        if let clipboard = map["clipboard"] {
            spec.clipboard = try bool(clipboard, path: "\(path).clipboard")
        }
        if let network = map["network"] {
            spec.network = try networkMode(network, path: "\(path).network")
        }
        if let shares = map["shares"] {
            spec.shares = try self.shares(shares, path: "\(path).shares")
        }
        if let ports = map["ports"] {
            spec.ports = try self.ports(ports, path: "\(path).ports")
        }
        if let provision = map["provision"] {
            spec.provision = try self.provision(provision, path: "\(path).provision")
        }
        if let hooks = map["hooks"] {
            spec.hooks = try self.hooks(hooks, path: "\(path).hooks")
        }
    }

    func shares(_ node: Node, path: String) throws(NestfileError) -> [ShareSpec] {
        try sequence(node, path: path).enumerated().map { index, item throws(NestfileError) in
            let itemPath = "\(path)[\(index)]"
            let map = try mapping(item, path: itemPath, allowed: ["host", "tag", "readOnly"])
            let hostURL = try fileURL(required(map, "host", path: itemPath), path: "\(itemPath).host")
            let tag: String = if let tagNode = map["tag"] {
                try string(tagNode, path: "\(itemPath).tag")
            } else {
                hostURL.lastPathComponent.isEmpty ? "share\(index)" : hostURL.lastPathComponent
            }
            let readOnly = try map["readOnly"].map { node throws(NestfileError) in
                try bool(node, path: "\(itemPath).readOnly")
            } ?? false
            return ShareSpec(hostURL: hostURL, tag: tag, readOnly: readOnly)
        }
    }

    /// Accepts `3000`, `"8080:80"`, `"5353:53/udp"` or `{host: 8080, guest: 80, protocol: udp}`.
    func ports(_ node: Node, path: String) throws(NestfileError) -> [PortForward] {
        try sequence(node, path: path).enumerated().map { index, item throws(NestfileError) in
            let itemPath = "\(path)[\(index)]"
            if case .mapping = item {
                let map = try mapping(item, path: itemPath, allowed: ["host", "guest", "protocol"])
                let guestPort = try port(required(map, "guest", path: itemPath), path: "\(itemPath).guest")
                let hostPort = try map["host"].map { node throws(NestfileError) in
                    try port(node, path: "\(itemPath).host")
                } ?? guestPort
                let transport = try map["protocol"].map { node throws(NestfileError) in
                    try transportProtocol(node, path: "\(itemPath).protocol")
                } ?? .tcp
                return PortForward(hostPort: hostPort, guestPort: guestPort, transport: transport)
            }
            return try shortPort(item, path: itemPath)
        }
    }

    func provision(_ node: Node, path: String) throws(NestfileError) -> ProvisionSpec {
        let map = try mapping(node, path: path, allowed: ["cloudInit"])
        let cloudInit = try map["cloudInit"].map { node throws(NestfileError) in
            try fileURL(node, path: "\(path).cloudInit")
        }
        return ProvisionSpec(cloudInit: cloudInit)
    }

    func hooks(_ node: Node, path: String) throws(NestfileError) -> HooksSpec {
        let map = try mapping(node, path: path, allowed: ["preStart", "postStart", "postProvision", "preStop"])
        func url(_ key: String) throws(NestfileError) -> URL? {
            try map[key].map { node throws(NestfileError) in try fileURL(node, path: "\(path).\(key)") }
        }
        return try HooksSpec(
            preStart: url("preStart"), postStart: url("postStart"),
            postProvision: url("postProvision"), preStop: url("preStop")
        )
    }

    // MARK: Primitive readers

    func mapping(_ node: Node, path: String, allowed: [String]) throws(NestfileError) -> [String: Node] {
        guard case let .mapping(mapping) = node else {
            throw NestfileError(path: path, line: node.line, kind: .typeMismatch(expected: "a mapping"))
        }
        var result: [String: Node] = [:]
        for (keyNode, value) in mapping {
            let key = try string(keyNode, path: path)
            guard allowed.contains(key) else {
                throw NestfileError(
                    path: path.isEmpty ? key : "\(path).\(key)", line: keyNode.line,
                    kind: .unknownKey(key, suggestion: closestMatch(to: key, in: allowed))
                )
            }
            result[key] = value
        }
        return result
    }

    func sequence(_ node: Node, path: String) throws(NestfileError) -> [Node] {
        guard case let .sequence(sequence) = node else {
            throw NestfileError(path: path, line: node.line, kind: .typeMismatch(expected: "a list"))
        }
        return Array(sequence)
    }

    func required(_ map: [String: Node], _ key: String, path: String) throws(NestfileError) -> Node {
        guard let node = map[key] else {
            throw NestfileError(path: path, line: nil, kind: .missingKey(key))
        }
        return node
    }

    func string(_ node: Node, path: String) throws(NestfileError) -> String {
        guard case let .scalar(scalar) = node, !scalar.string.isEmpty else {
            throw NestfileError(path: path, line: node.line, kind: .typeMismatch(expected: "a text value"))
        }
        return scalar.string
    }

    func int(_ node: Node, path: String) throws(NestfileError) -> Int {
        guard case let .scalar(scalar) = node, let value = Int(scalar.string) else {
            throw NestfileError(path: path, line: node.line, kind: .typeMismatch(expected: "a whole number"))
        }
        return value
    }

    func positiveInt(_ node: Node, path: String) throws(NestfileError) -> Int {
        let value = try int(node, path: path)
        guard value > 0 else {
            throw NestfileError(path: path, line: node.line, kind: .invalidValue("must be at least 1"))
        }
        return value
    }

    func bool(_ node: Node, path: String) throws(NestfileError) -> Bool {
        guard let value = node.bool else {
            throw NestfileError(path: path, line: node.line, kind: .typeMismatch(expected: "true or false"))
        }
        return value
    }

    func size(_ node: Node, path: String) throws(NestfileError) -> ByteCount {
        let text = try string(node, path: path)
        do {
            return try ByteSize.parse(text)
        } catch {
            throw NestfileError(path: path, line: node.line, kind: .invalidValue(error.description))
        }
    }

    func amount<Value>(
        _ node: Node,
        path: String,
        parse: (Node, String) throws(NestfileError) -> Value
    ) throws(NestfileError) -> Amount<Value> {
        if case let .scalar(scalar) = node, scalar.string == "auto" {
            return .auto
        }
        return try .fixed(parse(node, path))
    }

    func networkMode(_ node: Node, path: String) throws(NestfileError) -> NetworkMode {
        let text = try string(node, path: path)
        switch text {
        case "nat", "shared": return .nat
        case "none", "disconnected": return .disconnected
        default:
            throw NestfileError(
                path: path, line: node.line,
                kind: .invalidValue("“\(text)” is not a network mode; use “nat” or “none”")
            )
        }
    }

    func port(_ node: Node, path: String) throws(NestfileError) -> Int {
        let value = try int(node, path: path)
        guard (1 ... 65535).contains(value) else {
            throw NestfileError(path: path, line: node.line, kind: .invalidValue("\(value) is not a port (1–65535)"))
        }
        return value
    }

    func transportProtocol(_ node: Node, path: String) throws(NestfileError) -> PortForward.TransportProtocol {
        let text = try string(node, path: path)
        guard let value = PortForward.TransportProtocol(rawValue: text.lowercased()) else {
            throw NestfileError(path: path, line: node.line, kind: .invalidValue("“\(text)” must be “tcp” or “udp”"))
        }
        return value
    }

    func shortPort(_ node: Node, path: String) throws(NestfileError) -> PortForward {
        let text = try string(node, path: path)
        var body = Substring(text)
        var transport = PortForward.TransportProtocol.tcp
        if let slash = body.lastIndex(of: "/") {
            let suffix = body[body.index(after: slash)...]
            guard let parsed = PortForward.TransportProtocol(rawValue: suffix.lowercased()) else {
                throw NestfileError(
                    path: path,
                    line: node.line,
                    kind: .invalidValue("“\(suffix)” must be “tcp” or “udp”")
                )
            }
            transport = parsed
            body = body[..<slash]
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        let numbers = parts.compactMap(\.self)
        guard numbers.count == parts.count, (1 ... 2).contains(numbers.count),
              numbers.allSatisfy({ (1 ... 65535).contains($0) })
        else {
            throw NestfileError(
                path: path, line: node.line,
                kind: .invalidValue("“\(text)” is not a port forward; write “3000” or “8080:80”")
            )
        }
        return PortForward(hostPort: numbers[0], guestPort: numbers.last ?? numbers[0], transport: transport)
    }

    func fileURL(_ node: Node, path: String) throws(NestfileError) -> URL {
        let text = try string(node, path: path)
        let expanded = (text as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(filePath: expanded)
            : baseURL.appending(path: expanded)
        // One canonical form (no trailing slash), so "." and "./" compare equal.
        let standardized = url.standardizedFileURL.path(percentEncoded: false)
        let trimmed = standardized.count > 1 && standardized
            .hasSuffix("/") ? String(standardized.dropLast()) : standardized
        return URL(filePath: trimmed, directoryHint: .inferFromPath)
    }

    func validateMachineName(_ name: String, path: String, line: Int?) throws(NestfileError) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard name.count <= ConfigurationValidator.maximumNameLength,
              name.unicodeScalars.allSatisfy(allowed.contains),
              name.first?.isLetter == true || name.first?.isNumber == true
        else {
            throw NestfileError(
                path: path, line: line,
                kind: .invalidValue("“\(name)” is not a valid machine name; use letters, digits, “-”, “_” or “.”")
            )
        }
    }

    /// The allowed key with the smallest edit distance, if it is close enough to be a likely typo.
    func closestMatch(to key: String, in candidates: [String]) -> String? {
        candidates
            .map { ($0, levenshtein(key.lowercased(), $0.lowercased())) }
            .filter { $0.1 <= max(2, key.count / 3) }
            .min { $0.1 < $1.1 }?
            .0
    }
}

func levenshtein(_ lhs: String, _ rhs: String) -> Int {
    let source = Array(lhs), target = Array(rhs)
    guard !source.isEmpty else { return target.count }
    guard !target.isEmpty else { return source.count }
    var previous = Array(0 ... target.count)
    for row in 1 ... source.count {
        var current = [row] + Array(repeating: 0, count: target.count)
        for column in 1 ... target.count {
            let substitution = previous[column - 1] + (source[row - 1] == target[column - 1] ? 0 : 1)
            current[column] = min(previous[column] + 1, current[column - 1] + 1, substitution)
        }
        previous = current
    }
    return previous[target.count]
}

private extension Node {
    var line: Int? {
        mark?.line
    }
}
