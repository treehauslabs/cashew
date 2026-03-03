import ArrayTrie

public extension Node {
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
    
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<PathSegment, Address>()
        
        try await properties().concurrentForEach { property in
            guard let address = get(property: property) else { return }
            
            if paths.get([property]) == .recursive {
                let resolvedAddress = try await address.resolveRecursive(fetcher: fetcher)
                await newProperties.set(property, value: resolvedAddress)
            }
            else if let nextPaths = paths.traverse([property]) {
                if (!nextPaths.isEmpty()) {
                    let resolvedAddress = try await address.resolve(paths: nextPaths, fetcher: fetcher)
                    await newProperties.set(property, value: resolvedAddress)
                }
                else if paths.get([property]) == .targeted {
                    let resolvedAddress = try await address.resolve(fetcher: fetcher)
                    await newProperties.set(property, value: resolvedAddress)
                }
                else {
                    await newProperties.set(property, value: address)
                }
            }
            else {
                await newProperties.set(property, value: address)
            }
        }
        
        return set(properties: await newProperties.allKeyValuePairs())
    }
}
