import ArrayTrie

/// A ``Fetcher`` that receives context when resolution enters a ``Volume``.
///
/// Before resolving child blocks within a volume, the resolver calls
/// ``provide(rootCID:paths:)`` so the fetcher can locate a peer that stores
/// the child blocks under that CID contiguously.
public protocol VolumeAwareFetcher: Fetcher {
    /// Called before resolving child blocks within a ``Volume``.
    ///
    /// - Parameters:
    ///   - rootCID: The CID of the volume point being resolved into.
    ///   - paths: The resolution paths about to be traversed within the volume.
    func provide(rootCID: String, paths: ArrayTrie<ResolutionStrategy>) async throws
}
