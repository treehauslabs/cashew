import ArrayTrie

/// Disambiguates ``Header``'s `resolve` requirement for ``VolumeRadixHeader``.
///
/// Both ``Volume`` and ``RadixHeader`` provide default `resolve` implementations
/// — equally specific, so Swift can't synthesize conformance without an explicit
/// tiebreaker. These forwarders pick Volume's behavior (fire
/// ``VolumeAwareFetcher/provide`` at the boundary, then do the same descent
/// that RadixHeader would do via `resolvePaths`/`resolveAllNodes`/`resolveNode`
/// on ``Header``). The effect is that every trie-internal node acts as its own
/// Volume boundary with no behavior change to the descent itself.
public extension VolumeRadixHeader {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        if paths.isEmpty && paths.get([]) == nil { return self }
        if let volumeAware = fetcher as? VolumeAwareFetcher {
            try await volumeAware.provide(rootCID: rawCID, paths: paths)
        }
        return try await resolvePaths(paths, fetcher: fetcher)
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        if let volumeAware = fetcher as? VolumeAwareFetcher {
            var paths = ArrayTrie<ResolutionStrategy>()
            paths.set([], value: .recursive)
            try await volumeAware.provide(rootCID: rawCID, paths: paths)
        }
        return try await resolveAllNodes(fetcher: fetcher)
    }

    func resolve(fetcher: Fetcher) async throws -> Self {
        if let volumeAware = fetcher as? VolumeAwareFetcher {
            var paths = ArrayTrie<ResolutionStrategy>()
            paths.set([], value: .targeted)
            try await volumeAware.provide(rootCID: rawCID, paths: paths)
        }
        return try await resolveNode(fetcher: fetcher)
    }
}
