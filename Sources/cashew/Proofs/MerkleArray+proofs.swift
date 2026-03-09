import ArrayTrie

public extension MerkleArray {
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self {
        let proofBacking = try await backing.proof(paths: paths, fetcher: fetcher)
        return Self(backing: proofBacking, count: count)
    }
}
