/**
 * Resolution strategies define how MerkleDictionary data structures should be resolved
 * when fetching content from storage during deserialization operations.
 *
 * **Invariants:**
 * - `.targeted` fetches exactly one Header (CID → node), no recursion.
 * - `.recursive` transitively resolves every reachable Header in the subtree.
 * - `.list` resolves the radix trie structure so keys are enumerable, but leaf
 *   Header values keep `node == nil` (lazy). Combining `.list` with per-key
 *   overrides lets callers selectively hydrate specific entries.
 * - `.range` behaves like `.list` but only materializes keys in the given
 *   cursor window, skipping children whose leading character precedes `after`.
 */
public enum ResolutionStrategy: Codable, Equatable, Hashable, Sendable {
    /// Fetches the Header at this path (CID → node) without descending further.
    case targeted

    /// Transitively resolves every reachable Header in the subtree.
    case recursive

    /// Resolves the radix trie structure so keys are enumerable, but leaf Header
    /// values remain unresolved (`node == nil`) until explicitly fetched.
    ///
    /// Useful for directory listings, pagination, and lazy hydration patterns.
    case list

    /// Resolves a sorted range of keys with list-like behavior. Loads tree structure
    /// for up to `limit` keys after the cursor without resolving nested addresses.
    case range(after: String?, limit: Int)
}

public extension ResolutionStrategy {
    /// Merge two strategies for the same exact resolution path.
    ///
    /// Broader strategies subsume narrower ones: recursive resolves everything,
    /// list resolves enumerable structure, range resolves a list window, and
    /// targeted resolves one header/value.
    static func merge(_ lhs: Self, _ rhs: Self) -> Self {
        if lhs == rhs { return lhs }
        if lhs == .recursive || rhs == .recursive { return .recursive }
        if lhs == .list || rhs == .list { return .list }
        if case .range = lhs { return lhs }
        if case .range = rhs { return rhs }
        return .targeted
    }
}
