import ArrayTrie

/// A ``Fetcher`` that receives context when resolution enters and leaves a ``Volume``.
///
/// Before resolving child blocks within a volume, the resolver calls
/// ``provide(rootCID:paths:)`` so the fetcher can locate a peer that stores
/// the child blocks under that CID contiguously. After resolution of that
/// volume completes, the resolver calls ``leave(rootCID:)`` so the fetcher
/// can release the boundary's cached entries.
public protocol VolumeAwareFetcher: Fetcher {
    func enterVolume(rootCID: String, paths: ArrayTrie<ResolutionStrategy>) async throws
    func exitVolume(rootCID: String) async
}

public extension VolumeAwareFetcher {
    func exitVolume(rootCID: String) async {}
}
