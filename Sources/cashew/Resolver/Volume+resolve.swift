import ArrayTrie

public extension Volume {
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
