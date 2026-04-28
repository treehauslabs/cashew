import ArrayTrie

public extension Volume {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        if paths.isEmpty && paths.get([]) == nil { return self }
        if let vaf = fetcher as? VolumeAwareFetcher {
            try await vaf.enterVolume(rootCID: rawCID, paths: paths)
            let result = try await resolvePaths(paths, fetcher: fetcher)
            await vaf.exitVolume(rootCID: rawCID)
            return result
        }
        return try await resolvePaths(paths, fetcher: fetcher)
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        if let vaf = fetcher as? VolumeAwareFetcher {
            var paths = ArrayTrie<ResolutionStrategy>()
            paths.set([], value: .recursive)
            try await vaf.enterVolume(rootCID: rawCID, paths: paths)
            let result = try await resolveAllNodes(fetcher: fetcher)
            await vaf.exitVolume(rootCID: rawCID)
            return result
        }
        return try await resolveAllNodes(fetcher: fetcher)
    }

    func resolve(fetcher: Fetcher) async throws -> Self {
        if let vaf = fetcher as? VolumeAwareFetcher {
            var paths = ArrayTrie<ResolutionStrategy>()
            paths.set([], value: .targeted)
            try await vaf.enterVolume(rootCID: rawCID, paths: paths)
        }
        return try await resolveNode(fetcher: fetcher)
    }
}
