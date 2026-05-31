import ArrayTrie

/// A stable, serializable query shape for resolving part of a content-addressed
/// data structure.
///
/// The CID names the data object. `ResolutionPaths` names which part of that
/// object should be hydrated. Internally, resolvers execute these paths as an
/// `ArrayTrie<ResolutionStrategy>`, but the public value object keeps the query
/// shape enumerable and suitable for network transport.
public struct ResolutionPath: Codable, Equatable, Hashable, Sendable {
    public let components: [String]
    public let strategy: ResolutionStrategy

    public init(_ components: [String], strategy: ResolutionStrategy) {
        self.components = components
        self.strategy = strategy
    }
}

public struct ResolutionPaths: Codable, Equatable, Hashable, Sendable {
    public let entries: [ResolutionPath]

    public init(_ entries: [ResolutionPath] = []) {
        self.entries = Self.canonicalize(entries)
    }

    public init(_ paths: [[String]: ResolutionStrategy]) {
        self.init(paths.map { ResolutionPath($0.key, strategy: $0.value) })
    }

    public var isEmpty: Bool { entries.isEmpty }

    public static var empty: ResolutionPaths { ResolutionPaths() }

    public static var targetedRoot: ResolutionPaths {
        ResolutionPaths([ResolutionPath([], strategy: .targeted)])
    }

    public static var recursiveRoot: ResolutionPaths {
        ResolutionPaths([ResolutionPath([], strategy: .recursive)])
    }

    public func asTrie() -> ArrayTrie<ResolutionStrategy> {
        var trie = ArrayTrie<ResolutionStrategy>()
        for entry in entries {
            trie.set(entry.components, value: entry.strategy)
        }
        return trie
    }

    private static func canonicalize(_ entries: [ResolutionPath]) -> [ResolutionPath] {
        var byPath: [[String]: ResolutionStrategy] = [:]
        for entry in entries {
            if let existing = byPath[entry.components] {
                byPath[entry.components] = ResolutionStrategy.merge(existing, entry.strategy)
            } else {
                byPath[entry.components] = entry.strategy
            }
        }
        return byPath.map { ResolutionPath($0.key, strategy: $0.value) }.sorted()
    }
}

extension ResolutionPath: Comparable {
    public static func < (lhs: ResolutionPath, rhs: ResolutionPath) -> Bool {
        if lhs.components != rhs.components {
            return lhs.components.lexicographicallyPrecedes(rhs.components)
        }
        return lhs.strategy.sortKey < rhs.strategy.sortKey
    }
}

private extension ResolutionStrategy {
    var sortKey: String {
        switch self {
        case .targeted:
            return "0"
        case .recursive:
            return "1"
        case .list:
            return "2"
        case .range(let after, let limit):
            if let after {
                return "3:1:\(after):\(limit)"
            }
            return "3:0:\(limit)"
        }
    }
}
