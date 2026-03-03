import ArrayTrie

public extension RadixNode {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let pathValuesAndTries = paths.valuesAlongPath(prefix)
        if pathValuesAndTries.map({ $0.1 }).contains(.recursive) {
            return try await resolveRecursive(fetcher: fetcher)
        }
        let listTries = pathValuesAndTries.filter { $0.1 == .list }.map { $0.0 }
        if listTries.isEmpty {
            let newProperties = ThreadSafeDictionary<Character, ChildType>()
            guard let traversalPaths = paths.traverse(path: prefix) else { return self }
            try await properties().concurrentForEach { property in
                if let propertyTraversal = traversalPaths.traverseChild(property.first!) {
                    let childValue = try await getChild(property: property).resolve(paths: propertyTraversal, fetcher: fetcher)
                    await newProperties.set(property.first!, value: childValue)
                }
                else {
                    await newProperties.set(property.first!, value: getChild(property: property))
                }
            }
            let resolved = await set(properties: newProperties.allKeyValuePairs())
            if let value = value as? Address {
                if let downstreamPaths = paths.traverse([prefix]) {
                    guard let resolvedValue = try await value.resolve(paths: downstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
                    return Self(prefix: resolved.prefix, value: resolvedValue, children: resolved.children)
                }
                if paths.get([prefix]) == .targeted {
                    guard let resolvedValue = try await value.resolve(fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
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
        if let value = value as? Address {
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
                guard let newValue = try await value.resolve(paths: mergedDownstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
                return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
            }
            guard let newValue = try await value.resolve(paths: traversalTrie, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }
    
    func resolveRecursiveCommon(fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<Character, ChildType>()
        
        try await properties().concurrentForEach { property in
            let childValue = try await getChild(property: property).resolveRecursive(fetcher: fetcher)
            await newProperties.set(property.first!, value: childValue)
        }
        
        return set(properties: await newProperties.allKeyValuePairs())
    }
    
    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        let resolved = try await resolveRecursiveCommon(fetcher: fetcher)
        if let value = value as? Address {
            guard let newValue = try await value.resolveRecursive(fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }
    
    func resolveList(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        return try await resolveList(paths: paths, nextPaths: ArrayTrie(), fetcher: fetcher)
    }
    
    func resolveList(paths: ArrayTrie<ResolutionStrategy>?, nextPaths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let newProperties = ThreadSafeDictionary<Character, ChildType>()
        
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
        
        try await properties().concurrentForEach { property in
            let childValue = try await getChild(property: property).resolveList(paths: traversalPaths?.traverseChild(property.first!), nextPaths: finalNextPaths, fetcher: fetcher)
            await newProperties.set(property.first!, value: childValue)
        }
        
        let resolved = await set(properties: newProperties.allKeyValuePairs())
        if let value = value as? Address {
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
                guard let newValue = try await value.resolve(paths: downstreamPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
                return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
            }
            guard let newValue = try await value.resolve(paths: finalNextPaths, fetcher: fetcher) as? ValueType else { throw ResolutionErrors.TypeError }
            return Self(prefix: resolved.prefix, value: newValue, children: resolved.children)
        }
        return resolved
    }
}
