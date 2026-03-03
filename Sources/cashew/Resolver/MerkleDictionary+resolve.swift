import ArrayTrie

public extension MerkleDictionary {
    func resolve(paths: [[String]: ResolutionStrategy], fetcher: Fetcher) async throws -> Self {
        if paths.isEmpty { return self }
        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for (path, strategy) in paths {
            pathTrie.set(path, value: strategy)
        }
        return try await resolve(paths: pathTrie, fetcher: fetcher)
    }
    
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        if paths.get([""]) == .recursive {
            return try await resolveRecursive(fetcher: fetcher)
        }
        let newProperties = ThreadSafeDictionary<Character, ChildType>()
        if paths.get([""]) == .list {
            try await properties().concurrentForEach { property in
                if let childPath = paths.traverseChild(property.first!) {
                    await newProperties.set(property.first!, value: try await children[property.first!]!.resolveList(paths: childPath, fetcher: fetcher))
                }
                else {
                    await newProperties.set(property.first!, value: try await children[property.first!]!.resolveList(paths: ArrayTrie(), fetcher: fetcher))
                }
            }
            return await Self(children: newProperties.allKeyValuePairs(), count: count)
        }
        else {
            try await properties().concurrentForEach { property in
                if let childPath = paths.traverseChild(property.first!) {
                    await newProperties.set(property.first!, value: try await children[property.first!]!.resolve(paths: childPath, fetcher: fetcher))
                }
                else {
                    await newProperties.set(property.first!, value: children[property.first!]!)
                }
            }
        }
        return await Self(children: newProperties.allKeyValuePairs(), count: count)
    }
    
    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<PathSegment, Address>()
        
        try await properties().concurrentForEach { property in
            if let address = get(property: property) {
                let resolvedAddress = try await address.resolveRecursive(fetcher: fetcher)
                await newProperties.set(property, value: resolvedAddress)
            }
        }
        
        return set(properties: await newProperties.allKeyValuePairs())
    }
    
    func resolveList(fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<Character, ChildType>()

        try await properties().concurrentForEach { property in
            await newProperties.set(property.first!, value: try await children[property.first!]!.resolveList(paths: ArrayTrie(), fetcher: fetcher))
        }
        return await Self(children: newProperties.allKeyValuePairs(), count: count)
    }
    
    func resolve(fetcher: Fetcher) async throws -> Self {
        return self
    }
}
