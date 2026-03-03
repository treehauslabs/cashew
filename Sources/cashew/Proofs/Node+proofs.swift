import ArrayTrie

public extension Node {
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<PathSegment, Address>()
        
        let rootValue = paths.get([])
        if rootValue != nil && rootValue != .mutation && rootValue != .existence { throw ProofErrors.invalidProofType }
        if paths.getAllChildCharacters().count == 0 { return self }
        
        let allProperties = Set().union(paths.getAllChildKeys()).union(properties())
        let childKeys = paths.getAllChildKeys()
        
        try await allProperties.concurrentForEach { property in
            guard let address = get(property: property) else {
                if childKeys.contains(property) { throw ProofErrors.invalidProofType }
                return
            }
            let valueAtPaths = paths.get([property])
            if valueAtPaths != nil && valueAtPaths != .mutation && valueAtPaths != .existence { throw ProofErrors.invalidProofType }
            guard let nextPaths = paths.traverse([property]) else {
                await newProperties.set(property, value: address)
                return
            }
            if nextPaths.isEmpty() {
                await newProperties.set(property, value: address)
                return
            }
            let resolvedAddress = try await address.proof(paths: nextPaths, fetcher: fetcher)
            await newProperties.set(property, value: resolvedAddress)
        }
        return set(properties: await newProperties.allKeyValuePairs())
    }
}
