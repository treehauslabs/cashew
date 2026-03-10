import ArrayTrie

public extension MerkleArray {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self {
        let expanded = Self.expandRangePaths(paths, count: count)
        return try await resolvePaths(expanded, fetcher: fetcher)
    }

    static func rangePaths(_ range: Range<Int>) -> ArrayTrie<ResolutionStrategy> {
        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set([], value: .range(range))
        return paths
    }

    static func rangePaths(_ range: Range<Int>, innerStrategy: ResolutionStrategy) -> ArrayTrie<ResolutionStrategy> {
        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set([], value: .range(range))
        for i in range {
            paths.set([binaryKey(i)], value: innerStrategy)
        }
        return paths
    }

    private static func expandRangePaths(_ paths: ArrayTrie<ResolutionStrategy>, count: Int) -> ArrayTrie<ResolutionStrategy> {
        var expanded = paths
        if case .range(let range) = paths.get([]) {
            expanded = expanded.deleting(path: [])
            let clampedLower = max(range.lowerBound, 0)
            let clampedUpper = min(range.upperBound, count)
            guard clampedLower < clampedUpper else { return expanded }
            for i in clampedLower..<clampedUpper {
                let key = binaryKey(i)
                if expanded.get([key]) == nil {
                    expanded.set([key], value: .targeted)
                }
            }
        }
        return expanded
    }
}
