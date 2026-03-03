import ArrayTrie
import Crypto

public extension MerkleDictionary {
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self {
        if let rootStrategy = encryption.get([""]) {
            switch rootStrategy {
            case .recursive(let key):
                return try encryptRecursive(key: key, overrides: encryption)
            case .list(let key):
                return try encryptList(key: key, overrides: encryption)
            case .targeted(let key):
                return try encryptTargeted(key: key, overrides: encryption)
            }
        }
        var newChildren = children
        for (char, child) in children {
            if let childEnc = encryption.traverseChild(char) {
                newChildren[char] = try child.encrypt(encryption: childEnc)
            }
        }
        return Self(children: newChildren, count: count)
    }

    func encryptRecursive(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides.traverseChild(char)
            if let childOverrides = childOverrides, !childOverrides.getAllValues().isEmpty {
                newChildren[char] = try child.encryptRecursiveWithOverrides(key: key, overrides: childOverrides)
            } else {
                newChildren[char] = try child.encryptRecursive(key: key, overrides: childOverrides)
            }
        }
        return Self(children: newChildren, count: count)
    }

    func encryptList(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides.traverseChild(char)
            newChildren[char] = try child.encryptList(key: key, overrides: childOverrides)
        }
        return Self(children: newChildren, count: count)
    }

    func encryptTargeted(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides.traverseChild(char)
            newChildren[char] = try child.encryptTargeted(key: key, overrides: childOverrides)
        }
        return Self(children: newChildren, count: count)
    }
}
