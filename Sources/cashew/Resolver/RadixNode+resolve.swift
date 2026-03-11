import ArrayTrie

public extension RadixNode {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let pathValuesAndTries = paths.valuesAlongPath(prefix)
        if pathValuesAndTries.map({ $0.1 }).contains(.recursive) {
            return try await resolveRecursive(fetcher: fetcher)
        }
        let listTries = pathValuesAndTries.filter { $0.1 == .list }.map { $0.0 }
        if listTries.isEmpty {
            guard let traversalPaths = paths.traverse(path: prefix) else { return self }
            let newProperties = try await resolveChildrenConcurrently { property in
                if let propertyTraversal = traversalPaths.traverseChild(property.first!) {
                    return try await getChild(property: property).resolve(paths: propertyTraversal, fetcher: fetcher)
                } else {
                    return getChild(property: property)
                }
            }
            let resolved = set(properties: newProperties)
            if let value = value as? any Header {
                if let downstreamPaths = paths.traverse([prefix]) {
                    guard let resolvedValue = try await value.resolve(paths: downstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("resolved value type mismatch at prefix '\(prefix)'") }
                    return Self(prefix: resolved.prefix, value: resolvedValue, children: resolved.children)
                }
                if paths.get([prefix]) == .targeted {
                    guard let resolvedValue = try await value.resolve(fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("targeted resolve type mismatch at prefix '\(prefix)'") }
                    return Self(prefix: resolved.prefix, value: resolvedValue, children: resolved.children)
                }
            }
            return resolved
        }
        let traversalTrie = ArrayTrie<ResolutionStrategy>.mergeAll(tries: listTries) { leftStrategy, rightStrategy in
            if leftStrategy == .recursive || rightStrategy == .recursive {
                return .recursive
            }
            if leftStrategy == .list || rightStrategy == .list {
                return .list
            }
            return .targeted
        }
        let resolved = try await resolveList(paths: paths.traverse(path: prefix), nextPaths: traversalTrie, fetcher: fetcher)
        if let value = value as? any Header {
            if let downstreamPaths = paths.traverse([prefix]) {
                let mergedDownstreamPaths = traversalTrie.merging(with: downstreamPaths, mergeRule: { leftStrategy, rightStrategy in
                    if leftStrategy == .recursive || rightStrategy == .recursive {
                        return .recursive
                    }
                    if leftStrategy == .list || rightStrategy == .list {
                        return .list
                    }
                    return .targeted
                })
                guard let newValue = try await value.resolve(paths: mergedDownstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("list resolve type mismatch at prefix '\(prefix)'") }
                return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
            }
            guard let newValue = try await value.resolve(paths: traversalTrie, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("list resolve type mismatch at prefix '\(prefix)'") }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }

    func resolveRecursiveCommon(fetcher: Fetcher) async throws -> Self {
        let newProperties = try await resolveChildrenConcurrently { property in
            try await getChild(property: property).resolveRecursive(fetcher: fetcher)
        }
        return set(properties: newProperties)
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        let resolved = try await resolveRecursiveCommon(fetcher: fetcher)
        if let value = value as? any Header {
            guard let newValue = try await value.resolveRecursive(fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("recursive resolve type mismatch at prefix '\(prefix)'") }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }

    func resolveList(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        return try await resolveList(paths: paths, nextPaths: ArrayTrie(), fetcher: fetcher)
    }

    func resolveList(paths: ArrayTrie<ResolutionStrategy>?, nextPaths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        var traversalPaths: ArrayTrie<ResolutionStrategy>?
        var finalNextPaths = nextPaths

        if let paths = paths {
            let pathValuesAndTries = paths.valuesAlongPath(prefix)
            if pathValuesAndTries.map({ $0.1 }).contains(.recursive) {
                return try await resolveRecursive(fetcher: fetcher)
            }
            let listTries = pathValuesAndTries.filter { $0.1 == .list }.map { $0.0 }
            if !listTries.isEmpty {
                finalNextPaths = ArrayTrie<ResolutionStrategy>.mergeAll(tries: listTries + [nextPaths]) { leftStrategy, rightStrategy in
                    if leftStrategy == .recursive || rightStrategy == .recursive {
                        return .recursive
                    }
                    if leftStrategy == .list || rightStrategy == .list {
                        return .list
                    }
                    return .targeted
                }
            }
            traversalPaths = paths.traverse(path: prefix)
        }

        let capturedTraversalPaths = traversalPaths
        let capturedFinalNextPaths = finalNextPaths
        let newProperties = try await resolveChildrenConcurrently { property in
            try await getChild(property: property).resolveList(paths: capturedTraversalPaths?.traverseChild(property.first!), nextPaths: capturedFinalNextPaths, fetcher: fetcher)
        }

        let resolved = set(properties: newProperties)
        if let value = value as? any Header {
            if let newTraversalPaths = traversalPaths?.traverse([""]) {
                let downstreamPaths = newTraversalPaths.merging(with: finalNextPaths, mergeRule: { leftStrategy, rightStrategy in
                    if leftStrategy == .recursive || rightStrategy == .recursive {
                        return .recursive
                    }
                    if leftStrategy == .list || rightStrategy == .list {
                        return .list
                    }
                    return .targeted
                })
                guard let newValue = try await value.resolve(paths: downstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("resolveList value type mismatch at prefix '\(prefix)'") }
                return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
            }
            guard let newValue = try await value.resolve(paths: finalNextPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.typeError("resolveList value type mismatch at prefix '\(prefix)'") }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }

    private func resolveChildrenConcurrently(_ resolve: @Sendable @escaping (PathSegment) async throws -> ChildType) async throws -> [Character: ChildType] {
        try await withThrowingTaskGroup(of: (Character, ChildType).self) { group in
            for property in properties() {
                group.addTask {
                    let resolved = try await resolve(property)
                    return (property.first!, resolved)
                }
            }
            var result = [Character: ChildType]()
            for try await (key, value) in group {
                result[key] = value
            }
            return result
        }
    }
}
