import ArrayTrie

public extension Header {
    func resolve(paths: [[String]: ResolutionStrategy], fetcher: Fetcher) async throws -> Self {
        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for (path, strategy) in paths {
            pathTrie.set(path, value: strategy)
        }
        return try await resolve(paths: pathTrie, fetcher: fetcher)
    }

    // MARK: - Base resolution methods (shared by Volume)

    func resolvePaths(_ paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        if paths.isEmpty && paths.get([]) == nil { return self }
        if let node = node {
            let resolvedNode = try await node.resolve(paths: paths, fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        } else {
            let newNode = try await fetchAndDecodeNode(fetcher: fetcher)
            let resolvedNode = try await newNode.resolve(paths: paths, fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
    }

    func resolveAllNodes(fetcher: Fetcher) async throws -> Self {
        if let node = node {
            let resolvedNode = try await node.resolveRecursive(fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        } else {
            let newNode = try await fetchAndDecodeNode(fetcher: fetcher)
            let resolvedNode = try await newNode.resolveRecursive(fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
    }

    func resolveNode(fetcher: Fetcher) async throws -> Self {
        if node != nil {
            return self
        } else {
            let newNode = try await fetchAndDecodeNode(fetcher: fetcher)
            return Self(rawCID: rawCID, node: newNode, encryptionInfo: encryptionInfo)
        }
    }

    // MARK: - Default resolve implementations

    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        try await resolvePaths(paths, fetcher: fetcher)
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        try await resolveAllNodes(fetcher: fetcher)
    }

    func resolve(fetcher: Fetcher) async throws -> Self {
        try await resolveNode(fetcher: fetcher)
    }
}

