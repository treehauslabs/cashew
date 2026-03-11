import ArrayTrie

public extension RadixNode {
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        guard let traversedPrefix = paths.traverse(path: prefix) else {
            let values = paths.allValues()
            if values.contains(.deletion) || values.contains(.mutation) { throw ProofErrors.invalidProofType("deletion/mutation proof on non-existent prefix '\(prefix)'") }
            return self
        }
        let values = Set(paths.valuesExcludingPrefix(prefix))
        if values.contains(.deletion) || values.contains(.mutation) { throw ProofErrors.invalidProofType("deletion/mutation proof outside prefix '\(prefix)'") }
        guard let proofAtNode = traversedPrefix.get([""]) else {
            return try await proofForChildren(paths: traversedPrefix, fetcher: fetcher)
        }
        switch proofAtNode {
        case .mutation:
            if value == nil { throw ProofErrors.invalidProofType("mutation proof on nil value at prefix '\(prefix)'") }
        case .existence:
            break
        case .insertion:
            if value != nil { throw ProofErrors.invalidProofType("insertion proof on existing value at prefix '\(prefix)'") }
        case .deletion:
            if traversedPrefix.childKeys().count == 0 { return try await resolveGrandchildren(fetcher: fetcher) }
            return try await resolveGrandchildren(fetcher: fetcher).proofForChildren(paths: traversedPrefix, fetcher: fetcher)
        }
        return try await proofForChildren(paths: traversedPrefix, fetcher: fetcher)
    }

    func proofForChildren(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        let allChildCharacters = Set(children.keys).union(paths.childCharacters())
        let box = SendableBox(paths)
        let newChildren = try await withThrowingTaskGroup(of: (Character, ChildType)?.self) { group in
            for childKey in allChildCharacters {
                group.addTask {
                    let paths = box.value
                    guard let child = children[childKey] else {
                        guard let childPath = paths.traverseChild(childKey) else { return nil }
                        let allChildValues = Set(childPath.allValues())
                        if allChildValues.contains(.deletion) || allChildValues.contains(.mutation) { throw ProofErrors.invalidProofType("deletion/mutation proof on non-existent child '\(childKey)'") }
                        return nil
                    }
                    guard let childTraversal = paths.traverseChild(childKey) else {
                        return (childKey, child)
                    }
                    if childTraversal.isEmpty {
                        return (childKey, child)
                    }
                    return (childKey, try await child.proof(paths: childTraversal, fetcher: fetcher))
                }
            }
            var result = [Character: ChildType]()
            for try await pair in group {
                if let (key, value) = pair {
                    result[key] = value
                }
            }
            return result
        }
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    func resolveGrandchildren(fetcher: Fetcher) async throws -> Self {
        let newChildren = try await withThrowingTaskGroup(of: (Character, ChildType).self) { group in
            for (childKey, child) in children {
                group.addTask {
                    return (childKey, try await child.resolveChildren(fetcher: fetcher))
                }
            }
            var result = [Character: ChildType]()
            for try await (key, value) in group {
                result[key] = value
            }
            return result
        }
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    func resolveChildren(fetcher: Fetcher) async throws -> Self {
        let newChildren = try await withThrowingTaskGroup(of: (Character, ChildType).self) { group in
            for (childKey, child) in children {
                group.addTask {
                    return (childKey, try await child.resolve(fetcher: fetcher))
                }
            }
            var result = [Character: ChildType]()
            for try await (key, value) in group {
                result[key] = value
            }
            return result
        }
        return Self(prefix: prefix, value: value, children: newChildren)
    }
}
