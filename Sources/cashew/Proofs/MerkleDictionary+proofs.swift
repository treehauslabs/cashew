import ArrayTrie

public extension MerkleDictionary {
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        return try await proofForChildren(paths: paths, fetcher: fetcher)
    }
    
    func proofForChildren(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        let newChildren = ThreadSafeDictionary<Character, ChildType>()
        let allChildCharacters = Set().union(children.keys).union(paths.getAllChildCharacters())
        try await allChildCharacters.concurrentForEach { childKey in
            guard let child = children[childKey] else {
                guard let childPath = paths.traverseChild(childKey) else { return }
                let allChildValues = Set(childPath.getAllValues())
                if allChildValues.contains(.deletion) || allChildValues.contains(.mutation) { throw ProofErrors.invalidProofType }
                return
            }
            guard let childTraversal = paths.traverseChild(childKey) else {
                await newChildren.set(childKey, value: child)
                return
            }
            if childTraversal.isEmpty() {
                await newChildren.set(childKey, value: child)
                return
            }
            await newChildren.set(childKey, value: try child.proof(paths: childTraversal, fetcher: fetcher))
        }
        return await Self(children: newChildren.allKeyValuePairs(), count: count)
    }
}
