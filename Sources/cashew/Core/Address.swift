import ArrayTrie
import Crypto

public protocol Address: Sendable {
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self
    func resolveRecursive(fetcher: Fetcher) async throws -> Self
    func resolve(fetcher: Fetcher) async throws -> Self
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self
    func transform(transforms: ArrayTrie<Transform>) throws -> Self?
    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self?
    func storeRecursively(storer: Storer) throws
    func removingNode() -> Self
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self
    func encryptSelf(key: SymmetricKey) throws -> Self
}

public extension Address {
    func transform(transforms: ArrayTrie<Transform>) throws -> Self? {
        return try transform(transforms: transforms, keyProvider: nil)
    }
}
