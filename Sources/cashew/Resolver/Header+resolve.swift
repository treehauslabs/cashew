import ArrayTrie

public extension Header {
    func resolve(paths: [[String]: ResolutionStrategy], fetcher: Fetcher) async throws -> Self {
        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for (path, strategy) in paths {
            pathTrie.set(path, value: strategy)
        }
        return try await resolve(paths: pathTrie, fetcher: fetcher)
    }

    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        if paths.isEmpty && paths.get([]) == nil { return self }
        if let node = node {
            let resolvedNode = try await node.resolve(paths: paths, fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
        else {
            let fetchedData = try await fetcher.fetch(rawCid: rawCID)
            let decrypted = try decryptIfNeeded(data: fetchedData, fetcher: fetcher)
            guard let newNode = NodeType(data: decrypted) else { throw CashewDecodingError.decodeFromDataError }
            let resolvedNode = try await newNode.resolve(paths: paths, fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        if let node = node {
            let resolvedNode = try await node.resolveRecursive(fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
        else {
            let fetchedData = try await fetcher.fetch(rawCid: rawCID)
            let decrypted = try decryptIfNeeded(data: fetchedData, fetcher: fetcher)
            guard let newNode = NodeType(data: decrypted) else { throw CashewDecodingError.decodeFromDataError }
            let resolvedNode = try await newNode.resolveRecursive(fetcher: fetcher)
            return Self(rawCID: rawCID, node: resolvedNode, encryptionInfo: encryptionInfo)
        }
    }

    func resolve(fetcher: Fetcher) async throws -> Self {
        if node != nil {
            return self
        }
        else {
            let fetchedData = try await fetcher.fetch(rawCid: rawCID)
            let decrypted = try decryptIfNeeded(data: fetchedData, fetcher: fetcher)
            guard let newNode = NodeType(data: decrypted) else { throw CashewDecodingError.decodeFromDataError }
            return Self(rawCID: rawCID, node: newNode, encryptionInfo: encryptionInfo)
        }
    }
}

