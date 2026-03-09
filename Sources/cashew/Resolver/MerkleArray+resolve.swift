import ArrayTrie

public extension MerkleArray {
    func resolve(range: Range<Int>, fetcher: Fetcher) async throws -> Self {
        let clampedLower = max(range.lowerBound, 0)
        let clampedUpper = min(range.upperBound, count)
        guard clampedLower < clampedUpper else { return self }

        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for i in clampedLower..<clampedUpper {
            pathTrie.set([Self.binaryKey(i)], value: .targeted)
        }
        let resolvedBacking = try await backing.resolve(paths: pathTrie, fetcher: fetcher)
        return Self(backing: resolvedBacking, count: count)
    }

    func resolve(range: Range<Int>, innerStrategy: ResolutionStrategy, fetcher: Fetcher) async throws -> Self {
        let clampedLower = max(range.lowerBound, 0)
        let clampedUpper = min(range.upperBound, count)
        guard clampedLower < clampedUpper else { return self }

        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for i in clampedLower..<clampedUpper {
            pathTrie.set([Self.binaryKey(i)], value: innerStrategy)
        }
        let resolvedBacking = try await backing.resolve(paths: pathTrie, fetcher: fetcher)
        return Self(backing: resolvedBacking, count: count)
    }

    func resolve(range: Range<Int>, innerRange: Range<Int>, fetcher: Fetcher) async throws -> Self where Element: Header, Element.NodeType: MerkleArray {
        let clampedLower = max(range.lowerBound, 0)
        let clampedUpper = min(range.upperBound, count)
        guard clampedLower < clampedUpper else { return self }

        var pathTrie = ArrayTrie<ResolutionStrategy>()
        for i in clampedLower..<clampedUpper {
            let outerKey = Self.binaryKey(i)
            pathTrie.set([outerKey], value: .targeted)
            for j in innerRange {
                let innerKey = Element.NodeType.binaryKey(j)
                pathTrie.set([outerKey, innerKey], value: .targeted)
            }
        }
        let resolvedBacking = try await backing.resolve(paths: pathTrie, fetcher: fetcher)
        return Self(backing: resolvedBacking, count: count)
    }

    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let resolvedBacking = try await backing.resolve(paths: paths, fetcher: fetcher)
        return Self(backing: resolvedBacking, count: count)
    }

    func resolveRecursive(fetcher: Fetcher) async throws -> Self {
        let resolvedBacking = try await backing.resolveRecursive(fetcher: fetcher)
        return Self(backing: resolvedBacking, count: count)
    }

    func storeRecursively(storer: Storer) throws {
        try backing.storeRecursively(storer: storer)
    }
}
