import ArrayTrie

public extension RadixNode {
    func collapsed(prefix pfx: String, children: [Character: ChildType]) throws -> Self? {
        if children.isEmpty { return nil }
        if children.count == 1 {
            guard let child = children.first?.value.node else { throw TransformErrors.transformFailed }
            return Self(prefix: pfx + child.prefix, value: child.value, children: child.children)
        }
        return Self(prefix: pfx, value: nil, children: children)
    }

    static func insertAll(childChar: Character, transforms: ArrayTrie<Transform>) throws -> Self {
        guard let childPrefix = transforms.childPrefix(for: childChar) else { throw TransformErrors.transformFailed }
        guard let traversedTransforms = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
        var newProperties = [Character: ChildType]()
        for childChar in traversedTransforms.childCharacters() {
            guard let traversedChild = traversedTransforms.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if traversedChild.isEmpty { throw TransformErrors.transformFailed }
            newProperties[childChar] = ChildType(node: try insertAll(childChar: childChar, transforms: traversedChild))
        }
        if case .insert(let newValue) = traversedTransforms.get([""]) {
            guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
            return Self(prefix: childPrefix, value: newValue, children: newProperties)
        } else if traversedTransforms.get([""]) != nil {
            throw TransformErrors.transformFailed
        }
        return Self(prefix: childPrefix, value: nil, children: newProperties)
    }

    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        guard let childPrefix = transforms.childPrefix(for: prefix.first!) else { throw TransformErrors.transformFailed }
        let childPrefixSlice = ArraySlice(childPrefix)
        let prefixSlice = ArraySlice(prefix)
        let comparison = compareSlices(childPrefixSlice, prefixSlice)

        switch comparison {
        case 0:
            return try transformExactMatch(transforms: transforms, childPrefix: childPrefix, keyProvider: keyProvider)
        case 1:
            return try transformChildLonger(transforms: transforms, childPrefixSlice: childPrefixSlice, keyProvider: keyProvider)
        case 2:
            return try transformPrefixLonger(transforms: transforms, childPrefix: childPrefix, prefixSlice: prefixSlice, keyProvider: keyProvider)
        default:
            return try transformDivergent(transforms: transforms, prefixSlice: prefixSlice, childPrefixSlice: childPrefixSlice, keyProvider: keyProvider)
        }
    }

    private func transformExactMatch(transforms: ArrayTrie<Transform>, childPrefix: String, keyProvider: KeyProvider?) throws -> Self? {
        guard let traversedChild = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }

        if let transform = traversedChild.get([""]) {
            switch transform {
            case .update(let newValue):
                let newChildren = try transformChildren(transforms: traversedChild, keyProvider: keyProvider)
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: prefix, value: newValue, children: newChildren)
            case .delete:
                if value == nil { throw TransformErrors.transformFailed }
                let newChildren = try transformChildren(transforms: traversedChild, keyProvider: keyProvider)
                return try collapsed(prefix: prefix, children: newChildren)
            case .insert(let newValue):
                if value != nil { throw TransformErrors.transformFailed }
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: prefix, value: newValue, children: children)
            }
        }

        let newChildren = traversedChild.isEmpty ? children : try transformChildren(transforms: traversedChild, keyProvider: keyProvider)

        if let traversedNext = transforms.traverse([childPrefix]), !traversedNext.isEmpty {
            guard let address = value as? Address else {
                if value != nil { throw TransformErrors.invalidKey }
                return try collapsed(prefix: prefix, children: newChildren)
            }
            guard let newValue = try address.transform(transforms: traversedNext, keyProvider: keyProvider) else {
                return try collapsed(prefix: prefix, children: newChildren)
            }
            guard let typedValue = newValue as? ValueType else { throw TransformErrors.transformFailed }
            return Self(prefix: prefix, value: typedValue, children: newChildren)
        }

        if value != nil {
            return Self(prefix: prefix, value: value, children: newChildren)
        }
        return try collapsed(prefix: prefix, children: newChildren)
    }

    private func transformChildLonger(transforms: ArrayTrie<Transform>, childPrefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let remainingChildPrefix = childPrefixSlice.dropFirst(prefix.count)
        guard let traversedChild = transforms.traverse(path: prefix) else { throw TransformErrors.transformFailed }
        let childChar = remainingChildPrefix.first!

        guard let child = children[childChar] else {
            let newChild = try Self.insertAll(childChar: childChar, transforms: traversedChild)
            var newChildren = children
            newChildren[childChar] = ChildType(node: newChild)
            return Self(prefix: prefix, value: value, children: newChildren)
        }

        guard let childNode = child.node else { throw TransformErrors.missingData }
        guard let newChild = try childNode.transform(transforms: traversedChild, keyProvider: keyProvider) else {
            var newChildren = children
            newChildren.removeValue(forKey: childChar)
            if value != nil {
                return Self(prefix: prefix, value: value, children: newChildren)
            }
            return try collapsed(prefix: prefix, children: newChildren)
        }

        var newChildren = children
        newChildren[childChar] = try child.reEncryptIfNeeded(node: newChild, keyProvider: keyProvider)
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    private func transformPrefixLonger(transforms: ArrayTrie<Transform>, childPrefix: String, prefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let remainingPrefix = prefixSlice.dropFirst(childPrefix.count)
        guard let existingNodeChar = remainingPrefix.first else { throw TransformErrors.transformFailed }
        guard let traversedChild = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
        var newChildren = [Character: ChildType]()
        var existingNodeHandled = false

        for childChar in traversedChild.childCharacters() {
            guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if childChar == existingNodeChar {
                existingNodeHandled = true
                if let newChild = try Self(prefix: String(remainingPrefix), value: value, children: children).transform(transforms: childTransform, keyProvider: keyProvider) {
                    newChildren[childChar] = ChildType(node: newChild)
                }
            } else {
                newChildren[childChar] = ChildType(node: try Self.insertAll(childChar: childChar, transforms: childTransform))
            }
        }

        if !existingNodeHandled {
            newChildren[existingNodeChar] = ChildType(node: Self(prefix: String(remainingPrefix), value: value, children: children))
        }

        if case .insert(let newValue) = traversedChild.get([""]) {
            guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
            return Self(prefix: childPrefix, value: newValue, children: newChildren)
        } else if traversedChild.get([""]) != nil {
            throw TransformErrors.transformFailed
        }

        return try collapsed(prefix: childPrefix, children: newChildren)
    }

    private func transformDivergent(transforms: ArrayTrie<Transform>, prefixSlice: ArraySlice<Character>, childPrefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let common = commonPrefixString(prefixSlice, childPrefixSlice)
        let prefixRemainder = String(prefixSlice.dropFirst(common.count))
        let childPrefixRemainder = String(childPrefixSlice.dropFirst(common.count))
        guard let childTransforms = transforms.traverse(path: common)?.traverseChild(childPrefixRemainder.first!) else { throw TransformErrors.transformFailed }
        let newChild = try Self.insertAll(childChar: childPrefixRemainder.first!, transforms: childTransforms)
        return Self(prefix: common, value: nil, children: [
            childPrefixRemainder.first!: ChildType(node: newChild),
            prefixRemainder.first!: ChildType(node: Self(prefix: prefixRemainder, value: value, children: children))
        ])
    }

    func transformChildren(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> [Character: ChildType] {
        var newChildren = [Character: ChildType]()
        for childChar in Set(transforms.childCharacters()).union(children.keys) {
            guard let transformChild = transforms.traverseChild(childChar) else {
                guard let currentChild = children[childChar] else { throw TransformErrors.transformFailed }
                newChildren[childChar] = currentChild
                continue
            }
            guard let currentChild = children[childChar] else {
                newChildren[childChar] = ChildType(node: try Self.insertAll(childChar: childChar, transforms: transformChild))
                continue
            }
            if let transformedChild = try currentChild.transform(transforms: transformChild, keyProvider: keyProvider) {
                newChildren[childChar] = transformedChild
            }
        }
        return newChildren
    }

    func get(key: ArraySlice<Character>) throws -> ValueType? {
        let prefixSlice = ArraySlice(prefix)
        if key.elementsEqual(prefixSlice) { return value }
        guard key.starts(with: prefixSlice) else { return nil }
        let newKey = key.dropFirst(prefixSlice.count)
        guard let childChar = newKey.first else { return value }
        guard let child = children[childChar] else { return nil }
        guard let childNode = child.node else { throw TransformErrors.missingData }
        return try childNode.get(key: newKey)
    }

    func deleting(key: ArraySlice<Character>) throws -> Self? {
        let prefixSlice = ArraySlice(prefix)
        let comparison = compareSlices(key, prefixSlice)
        switch comparison {
        case 0:
            return try collapsed(prefix: prefix, children: children)
        case 1:
            let newKey = key.dropFirst(prefixSlice.count)
            let childChar = newKey.first!
            guard let child = children[childChar] else { throw TransformErrors.invalidKey }
            if let newChild = try child.deleting(key: newKey) {
                var newChildren = children
                newChildren[childChar] = newChild
                return Self(prefix: prefix, value: value, children: newChildren)
            }
            if children.count == 1 && value == nil { return nil }
            var newChildren = children
            newChildren.removeValue(forKey: childChar)
            if newChildren.count == 1 && value == nil {
                guard let childNode = newChildren.first?.value.node else { throw TransformErrors.missingData }
                return Self(prefix: prefix + childNode.prefix, value: childNode.value, children: childNode.children)
            }
            return Self(prefix: prefix, value: value, children: newChildren)
        default:
            throw TransformErrors.invalidKey
        }
    }

    func mutating(key: ArraySlice<Character>, value: ValueType) throws -> Self {
        let selfPathSlice = ArraySlice(prefix)
        let comparison = compareSlices(key, selfPathSlice)
        switch comparison {
        case 0:
            if self.value == nil { throw TransformErrors.invalidKey }
            return Self(prefix: prefix, value: value, children: children)
        case 1:
            let keyRemainder = key.dropFirst(selfPathSlice.count)
            let keyChar = keyRemainder.first!
            guard let child = children[keyChar] else { throw TransformErrors.invalidKey }
            let updatedChild = try child.mutating(key: keyRemainder, value: value)
            var newChildren = children
            newChildren[keyChar] = updatedChild
            return Self(prefix: prefix, value: self.value, children: newChildren)
        default:
            throw TransformErrors.invalidKey
        }
    }

    func inserting(key: ArraySlice<Character>, value: ValueType) throws -> Self {
        let selfPathSlice = ArraySlice(prefix)
        let comparison = compareSlices(key, selfPathSlice)
        switch comparison {
        case 0:
            if self.value != nil { throw TransformErrors.invalidKey }
            return Self(prefix: prefix, value: value, children: children)
        case 1:
            let keyRemainder = key.dropFirst(selfPathSlice.count)
            let keyChar = keyRemainder.first!
            if let child = children[keyChar] {
                let updatedChild = try child.inserting(key: keyRemainder, value: value)
                var newChildren = children
                newChildren[keyChar] = updatedChild
                return Self(prefix: prefix, value: self.value, children: newChildren)
            } else {
                let newChild = ChildType(node: Self(prefix: String(keyRemainder), value: value, children: [:]))
                var newChildren = children
                newChildren[keyChar] = newChild
                return Self(prefix: prefix, value: self.value, children: newChildren)
            }
        case 2:
            let remainingPath = String(selfPathSlice.dropFirst(key.count))
            let existingChild = ChildType(node: Self(prefix: remainingPath, value: self.value, children: children))
            return Self(prefix: String(key), value: value, children: [remainingPath.first!: existingChild])
        default:
            let common = commonPrefixString(key, selfPathSlice)
            let keyRemainder = String(key.dropFirst(common.count))
            let pathRemainder = String(selfPathSlice.dropFirst(common.count))
            let existingChild = ChildType(node: Self(prefix: pathRemainder, value: self.value, children: children))
            let newChild = ChildType(node: Self(prefix: keyRemainder, value: value, children: [:]))
            return Self(prefix: common, value: nil, children: [pathRemainder.first!: existingChild, keyRemainder.first!: newChild])
        }
    }
}

// MARK: - Specialized transform for Header<MerkleDictionary> values

extension RadixNode where ValueType: Header, ValueType.NodeType: MerkleDictionary {
    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        guard let childPrefix = transforms.childPrefix(for: prefix.first!) else { throw TransformErrors.transformFailed }
        let childPrefixSlice = ArraySlice(childPrefix)
        let prefixSlice = ArraySlice(prefix)
        let comparison = compareSlices(childPrefixSlice, prefixSlice)

        switch comparison {
        case 0:
            return try transformExactMatch(transforms: transforms, childPrefix: childPrefix, keyProvider: keyProvider)
        case 1:
            return try transformChildLonger(transforms: transforms, childPrefixSlice: childPrefixSlice, keyProvider: keyProvider)
        case 2:
            return try transformPrefixLonger(transforms: transforms, childPrefix: childPrefix, prefixSlice: prefixSlice, keyProvider: keyProvider)
        default:
            return try transformDivergent(transforms: transforms, prefixSlice: prefixSlice, childPrefixSlice: childPrefixSlice, keyProvider: keyProvider)
        }
    }

    private func createEmptyHeaderValue(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> ValueType? {
        let newHeader = ValueType(node: ValueType.NodeType())
        return try newHeader.transform(transforms: transforms, keyProvider: keyProvider)
    }

    private func transformExactMatch(transforms: ArrayTrie<Transform>, childPrefix: String, keyProvider: KeyProvider?) throws -> Self? {
        let traversedChild = transforms.traverse(path: childPrefix)

        if let traversedChild, let transform = traversedChild.get([""]) {
            guard transforms.traverse([prefix]) == nil else { throw TransformErrors.transformFailed }
            switch transform {
            case .update(let newValue):
                let newChildren = try transformChildren(transforms: traversedChild, keyProvider: keyProvider)
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: prefix, value: newValue, children: newChildren)
            case .delete:
                if value == nil { throw TransformErrors.transformFailed }
                let newChildren = try transformChildren(transforms: traversedChild, keyProvider: keyProvider)
                return try collapsed(prefix: prefix, children: newChildren)
            case .insert(let newValue):
                if value != nil { throw TransformErrors.transformFailed }
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: prefix, value: newValue, children: children)
            }
        }

        let newChildren = (traversedChild?.isEmpty ?? true) ? children : try transformChildren(transforms: traversedChild!, keyProvider: keyProvider)

        if let traversedNext = transforms.traverse([childPrefix]), !traversedNext.isEmpty {
            if let value = value {
                guard let newValue = try value.transform(transforms: traversedNext, keyProvider: keyProvider) else {
                    return try collapsed(prefix: prefix, children: newChildren)
                }
                return Self(prefix: prefix, value: newValue, children: newChildren)
            }
            return Self(prefix: prefix, value: try createEmptyHeaderValue(transforms: traversedNext, keyProvider: keyProvider), children: children)
        }

        return try collapsed(prefix: prefix, children: newChildren)
    }

    private func transformChildLonger(transforms: ArrayTrie<Transform>, childPrefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let remainingChildPrefix = childPrefixSlice.dropFirst(prefix.count)
        guard let traversedChild = transforms.traverse(path: prefix) else { throw TransformErrors.transformFailed }
        let childChar = remainingChildPrefix.first!

        guard let child = children[childChar] else {
            let newChild = try Self.insertAll(childChar: childChar, transforms: traversedChild)
            var newChildren = children
            newChildren[childChar] = ChildType(node: newChild)
            return Self(prefix: prefix, value: value, children: newChildren)
        }

        guard let childNode = child.node else { throw TransformErrors.missingData }
        guard let newChild = try childNode.transform(transforms: traversedChild, keyProvider: keyProvider) else {
            var newChildren = children
            newChildren.removeValue(forKey: childChar)
            if value != nil {
                return Self(prefix: prefix, value: value, children: newChildren)
            }
            return try collapsed(prefix: prefix, children: newChildren)
        }

        var newChildren = children
        newChildren[childChar] = try child.reEncryptIfNeeded(node: newChild, keyProvider: keyProvider)
        return Self(prefix: prefix, value: value, children: newChildren)
    }

    private func transformPrefixLonger(transforms: ArrayTrie<Transform>, childPrefix: String, prefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let remainingPrefix = prefixSlice.dropFirst(childPrefix.count)
        guard let existingNodeChar = remainingPrefix.first else { throw TransformErrors.transformFailed }
        guard let traversedChild = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
        var newChildren = [Character: ChildType]()
        var existingNodeHandled = false

        for childChar in traversedChild.childCharacters() {
            guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if childChar == existingNodeChar {
                existingNodeHandled = true
                if let newChild = try Self(prefix: String(remainingPrefix), value: value, children: children).transform(transforms: childTransform, keyProvider: keyProvider) {
                    newChildren[childChar] = ChildType(node: newChild)
                }
            } else {
                newChildren[childChar] = ChildType(node: try Self.insertAll(childChar: childChar, transforms: childTransform))
            }
        }

        if !existingNodeHandled {
            newChildren[existingNodeChar] = ChildType(node: Self(prefix: String(remainingPrefix), value: value, children: children))
        }

        if case .insert(let newValue) = traversedChild.get([""]) {
            guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
            return Self(prefix: childPrefix, value: newValue, children: newChildren)
        } else if traversedChild.get([""]) != nil {
            throw TransformErrors.transformFailed
        }

        if let traversedNext = transforms.traverse([childPrefix]), !traversedNext.isEmpty {
            return Self(prefix: childPrefix, value: try createEmptyHeaderValue(transforms: traversedNext, keyProvider: keyProvider), children: newChildren)
        }

        return try collapsed(prefix: childPrefix, children: newChildren)
    }

    private func transformDivergent(transforms: ArrayTrie<Transform>, prefixSlice: ArraySlice<Character>, childPrefixSlice: ArraySlice<Character>, keyProvider: KeyProvider?) throws -> Self? {
        let common = commonPrefixString(prefixSlice, childPrefixSlice)
        let prefixRemainder = String(prefixSlice.dropFirst(common.count))
        let childPrefixRemainder = String(childPrefixSlice.dropFirst(common.count))
        guard let childTransforms = transforms.traverse(path: common)?.traverseChild(childPrefixRemainder.first!) else { throw TransformErrors.transformFailed }
        let newChild = try Self.insertAll(childChar: childPrefixRemainder.first!, transforms: childTransforms)
        return Self(prefix: common, value: nil, children: [
            childPrefixRemainder.first!: ChildType(node: newChild),
            prefixRemainder.first!: ChildType(node: Self(prefix: prefixRemainder, value: value, children: children))
        ])
    }

    static func insertAll(childChar: Character, transforms: ArrayTrie<Transform>) throws -> Self {
        guard let childPrefix = transforms.childPrefix(for: childChar) else { throw TransformErrors.transformFailed }
        guard let traversedTransforms = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
        var newProperties = [Character: ChildType]()
        for childChar in traversedTransforms.childCharacters() {
            guard let traversedChild = traversedTransforms.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if traversedChild.isEmpty { throw TransformErrors.transformFailed }
            newProperties[childChar] = ChildType(node: try insertAll(childChar: childChar, transforms: traversedChild))
        }
        if case .insert(let newValue) = traversedTransforms.get([""]) {
            guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
            return Self(prefix: childPrefix, value: newValue, children: newProperties)
        } else if traversedTransforms.get([""]) != nil {
            throw TransformErrors.transformFailed
        }
        if let traversedNext = transforms.traverse([childPrefix]), !traversedNext.isEmpty {
            let newHeader = ValueType(node: ValueType.NodeType())
            let newHeaderValue = try newHeader.transform(transforms: traversedNext)
            return Self(prefix: childPrefix, value: newHeaderValue, children: newProperties)
        }
        return Self(prefix: childPrefix, value: nil, children: newProperties)
    }
}
