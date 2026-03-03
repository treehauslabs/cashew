import ArrayTrie
import Crypto

public extension RadixHeader {
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        let encryptedNode = try node.encrypt(encryption: encryption)
        return Self(node: encryptedNode)
    }

    func encryptRecursive(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        let encryptedNode = try node.encryptRecursive(key: key, overrides: overrides)
        return try Self(node: encryptedNode, key: key)
    }

    func encryptList(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        let encryptedNode = try node.encryptList(key: key, overrides: overrides)
        return try Self(node: encryptedNode, key: key)
    }

    func encryptTargeted(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        let encryptedNode = try node.encryptTargeted(key: key, overrides: overrides)
        return try Self(node: encryptedNode, key: key)
    }
}
