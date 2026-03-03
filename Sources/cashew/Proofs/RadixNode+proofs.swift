import ArrayTrie

public extension RadixNode {
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        guard let traversedPrefix = paths.traverse(path: prefix) else {
            let values = paths.getAllValues()
            if values.contains(.deletion) || values.contains(.mutation) { throw ProofErrors.invalidProofType }
            return self
        }
        let values = Set(paths.getValuesOfKeysThatDontStartWith(key: prefix))
        if values.contains(.deletion) || values.contains(.mutation) { throw ProofErrors.invalidProofType }
        guard let proofAtNode = traversedPrefix.get([""]) else {
            return try await proofForChildren(paths: traversedPrefix, fetcher: fetcher)
        }
        switch proofAtNode {
        case .mutation:
            if value == nil { throw ProofErrors.invalidProofType }
        case .existence:
            break
        case .insertion:
            if value != nil { throw ProofErrors.invalidProofType }
        case .deletion:
            if traversedPrefix.getAllChildKeys().count == 0 { return try await resolveGrandchildren(fetcher: fetcher) }
            return try await resolveGrandchildren(fetcher: fetcher).proofForChildren(paths: traversedPrefix, fetcher: fetcher)
        }
        return try await proofForChildren(paths: traversedPrefix, fetcher: fetcher)
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
        return await Self(prefix: prefix, value: value, children: newChildren.allKeyValuePairs())
    }
        
    func resolveGrandchildren(fetcher: Fetcher) async throws -> Self {
        let newChildren = ThreadSafeDictionary<Character, ChildType>()
        try await children.concurrentForEach { (childKey, child) in
            await newChildren.set(childKey, value: try child.resolveChildren(fetcher: fetcher))
        }
        return await Self(prefix: prefix, value: value, children: newChildren.allKeyValuePairs())
    }
    
    func resolveChildren(fetcher: Fetcher) async throws -> Self {
        let newChildren = ThreadSafeDictionary<Character, ChildType>()
        try await children.concurrentForEach { (childKey, child) in
            await newChildren.set(childKey, value: try child.resolve(fetcher: fetcher))
        }
        return await Self(prefix: prefix, value: value, children: newChildren.allKeyValuePairs())
    }
}
