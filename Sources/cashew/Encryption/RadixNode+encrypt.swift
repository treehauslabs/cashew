import ArrayTrie
import Crypto

public extension RadixNode {
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self {
        if let strategy = encryption.get([prefix]) {
            let remaining = encryption.traverse(path: prefix)
            switch strategy {
            case .recursive(let key):
                return try encryptRecursive(key: key, overrides: remaining)
            case .list(let key):
                return try encryptList(key: key, overrides: remaining)
            case .targeted(let key):
                return try encryptTargeted(key: key, overrides: remaining)
            }
        }

        let pathValuesAndTries = encryption.valuesAlongPath(prefix)
        if let (_, lastStrategy) = pathValuesAndTries.last {
            let remaining = encryption.traverse(path: prefix)
            switch lastStrategy {
            case .recursive(let key):
                return try encryptRecursive(key: key, overrides: remaining)
            case .list(let key):
                return try encryptList(key: key, overrides: remaining)
            case .targeted(let key):
                return try encryptTargeted(key: key, overrides: remaining)
            }
        }

        guard let traversed = encryption.traverse(path: prefix) else { return self }
        var newChildren = children
        for (char, child) in children {
            if let childEnc = traversed.traverseChild(char) {
                newChildren[char] = try child.encrypt(encryption: childEnc)
            }
        }
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    func encryptRecursive(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides?.traverseChild(char)
            if let childOverrides = childOverrides, !childOverrides.allValues().isEmpty {
                newChildren[char] = try child.encryptRecursiveWithOverrides(key: key, overrides: childOverrides)
            } else {
                newChildren[char] = try child.encryptRecursive(key: key, overrides: nil)
            }
        }

        if let value = value as? Address {
            let valueOverrides = overrides?.traverse([""])
            if let valueOverrides = valueOverrides, !valueOverrides.isEmpty {
                guard let encrypted = try value.encrypt(encryption: valueOverrides).encryptSelf(key: key) as? ValueType else {
                    throw DataErrors.encryptionFailed
                }
                return Self(prefix: prefix, value: encrypted, children: newChildren)
            }
            guard let encrypted = try value.encryptSelf(key: key) as? ValueType else {
                throw DataErrors.encryptionFailed
            }
            return Self(prefix: prefix, value: encrypted, children: newChildren)
        }

        return Self(prefix: prefix, value: value, children: newChildren)
    }

    func encryptList(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides?.traverseChild(char)
            newChildren[char] = try child.encryptList(key: key, overrides: childOverrides)
        }
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    func encryptTargeted(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>?) throws -> Self {
        var newChildren = [Character: ChildType]()
        for (char, child) in children {
            let childOverrides = overrides?.traverseChild(char)
            if let childOverrides = childOverrides, !childOverrides.allValues().isEmpty {
                newChildren[char] = try child.encryptRecursiveWithOverrides(key: key, overrides: childOverrides)
            } else {
                newChildren[char] = try child.encryptTargeted(key: key, overrides: nil)
            }
        }

        let valueStrategy = overrides?.get([""])
        if valueStrategy != nil, let value = value as? Address {
            guard let encrypted = try value.encryptSelf(key: key) as? ValueType else {
                throw DataErrors.encryptionFailed
            }
            return Self(prefix: prefix, value: encrypted, children: newChildren)
        }

        return Self(prefix: prefix, value: value, children: newChildren)
    }
}

extension RadixHeader {
    func encryptRecursiveWithOverrides(key: SymmetricKey, overrides: ArrayTrie<EncryptionStrategy>) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }

        if let override = overrides.get([node.prefix]) {
            let remaining = overrides.traverse(path: node.prefix)
            switch override {
            case .recursive(let overrideKey):
                let encryptedNode = try node.encryptRecursive(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            case .targeted(let overrideKey):
                let encryptedNode = try node.encryptTargeted(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            case .list(let overrideKey):
                let encryptedNode = try node.encryptList(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            }
        }

        let pathValues = overrides.valuesAlongPath(node.prefix)
        if let (_, override) = pathValues.last {
            let remaining = overrides.traverse(path: node.prefix)
            switch override {
            case .recursive(let overrideKey):
                let encryptedNode = try node.encryptRecursive(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            case .targeted(let overrideKey):
                let encryptedNode = try node.encryptTargeted(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            case .list(let overrideKey):
                let encryptedNode = try node.encryptList(key: overrideKey, overrides: remaining)
                return try Self(node: encryptedNode, key: overrideKey)
            }
        }

        let encryptedNode: NodeType
        if let traversed = overrides.traverse(path: node.prefix) {
            let childPathValues = traversed.allValues()
            if !childPathValues.isEmpty {
                encryptedNode = try node.encryptRecursive(key: key, overrides: traversed)
            } else {
                encryptedNode = try node.encryptRecursive(key: key, overrides: nil)
            }
        } else {
            encryptedNode = try node.encryptRecursive(key: key, overrides: nil)
        }
        return try Self(node: encryptedNode, key: key)
    }
}
