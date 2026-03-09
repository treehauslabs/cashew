import ArrayTrie

public extension MerkleArray {
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self {
        let encryptedBacking = try backing.encrypt(encryption: encryption)
        return Self(backing: encryptedBacking, count: count)
    }
}
