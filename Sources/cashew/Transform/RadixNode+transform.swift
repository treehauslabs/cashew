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
        let childChars = traversedTransforms.childCharacters()
        var newProperties = [Character: ChildType]()
        for childChar in childChars {
            guard let traversedChild = traversedTransforms.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if traversedChild.isEmpty { throw TransformErrors.transformFailed }
            let newChildAfterInsertion = try insertAll(childChar: childChar, transforms: traversedChild)
            let newChild = ChildType(node: newChildAfterInsertion)
            newProperties[childChar] = newChild
        }
        let transform = traversedTransforms.get([""])
        if let transform = transform {
            switch transform {
            case .insert(let newValue):
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: childPrefix, value: newValue, children: newProperties)
            default:
                throw TransformErrors.transformFailed
            }
        }
        return Self(prefix: childPrefix, value: nil, children: newProperties)
    }
    
    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        guard let childPrefix = transforms.childPrefix(for: prefix.first!) else { throw TransformErrors.transformFailed }
        let childPrefixSlice = ArraySlice(childPrefix)
        let prefixSlice = ArraySlice(prefix)
        let comparison = compareSlices(childPrefixSlice, prefixSlice)
        if comparison == 0 {
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
            if value != nil {
                if let traversedNext = transforms.traverse([childPrefix]) {
                    if !traversedNext.isEmpty {
                        if let value = value as? Address {
                            if let newValue = try value.transform(transforms: traversedNext, keyProvider: keyProvider) {
                                if let newValue = newValue as? ValueType {
                                    return Self(prefix: prefix, value: newValue, children: newChildren)
                                }
                                else {
                                    throw TransformErrors.transformFailed
                                }
                            }
                            return try collapsed(prefix: prefix, children: newChildren)
                        }
                        else { throw TransformErrors.invalidKey }
                    }
                }
                return Self(prefix: prefix, value: value, children: newChildren)
            }
            return try collapsed(prefix: prefix, children: newChildren)
        }
        if comparison == 1 {
            let remainingChildPrefix = childPrefixSlice.dropFirst(prefix.count)
            guard let traversedChild = transforms.traverse(path: prefix) else { throw TransformErrors.transformFailed }
            let childChar = remainingChildPrefix.first!
            if let child = children[childChar] {
                guard let childNode = child.node else { throw TransformErrors.missingData }
                if let newChild = try childNode.transform(transforms: traversedChild, keyProvider: keyProvider) {
                    var newChildren = children
                    newChildren[childChar] = try child.reEncryptIfNeeded(node: newChild, keyProvider: keyProvider)
                    return Self(prefix: prefix, value: value, children: newChildren)
                }
                else {
                    var newChildren = children
                    newChildren.removeValue(forKey: childChar)
                    if value != nil {
                        return Self(prefix: prefix, value: value, children: newChildren)
                    }
                    return try collapsed(prefix: prefix, children: newChildren)
                }
            }
            else {
                let newChild = try Self.insertAll(childChar: childChar, transforms: traversedChild)
                var newChildren = children
                newChildren[childChar] = ChildType(node: newChild)
                return Self(prefix: prefix, value: value, children: newChildren)
            }
        }
        if comparison == 2 {
            let remainingPrefix = prefixSlice.dropFirst(childPrefix.count)
            guard let existingNodeChar = remainingPrefix.first else { throw TransformErrors.transformFailed }
            guard let traversedChild = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
            var newChildren = [Character: ChildType]()
            var existingNodeHandled = false
            for childChar in traversedChild.childCharacters() {
                if childChar == existingNodeChar {
                    existingNodeHandled = true
                    guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
                    if let newChild = try Self(prefix: String(remainingPrefix), value: value, children: children).transform(transforms: childTransform, keyProvider: keyProvider) {
                        newChildren[childChar] = ChildType(node: newChild)
                    }
                }
                else {
                    guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
                    let newChild = try Self.insertAll(childChar: childChar, transforms: childTransform)
                    newChildren[childChar] = ChildType(node: newChild)
                }
            }
            if !existingNodeHandled {
                newChildren[existingNodeChar] = ChildType(node: Self(prefix: String(remainingPrefix), value: value, children: children))
            }
            if let newValue = traversedChild.get([""]) {
                switch newValue {
                case .insert(let newValue):
                    guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                    return Self(prefix: childPrefix, value: newValue, children: newChildren)
                default: throw TransformErrors.transformFailed
                }
            }
            return try collapsed(prefix: childPrefix, children: newChildren)
        }
        let common = commonPrefixString(prefixSlice, childPrefixSlice)
        let prefixSliceRemainder = String(prefixSlice.dropFirst(common.count))
        let childPrefixSliceRemainder = String(childPrefixSlice.dropFirst(common.count))
        guard let childTransforms = transforms.traverse(path: common)?.traverseChild(childPrefixSliceRemainder.first!) else { throw TransformErrors.transformFailed }
        let newChild = try Self.insertAll(childChar: childPrefixSliceRemainder.first!, transforms: childTransforms)
        var newChildren = [Character: ChildType]()
        newChildren[childPrefixSliceRemainder.first!] = ChildType(node: newChild)
        newChildren[prefixSliceRemainder.first!] = ChildType(node: Self(prefix: String(prefixSliceRemainder), value: value, children: children))
        return Self(prefix: common, value: nil, children: newChildren)
    }

    func transformChildren(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> [Character: ChildType] {
        var newChildren = [Character: ChildType]()
        let allChildChars = Set(transforms.childCharacters()).union(children.keys)
        for childChar in allChildChars {
            if let transformChild = transforms.traverseChild(childChar) {
                if let currentChild = children[childChar] {
                    if let transformedChild = try currentChild.transform(transforms: transformChild, keyProvider: keyProvider) {
                        newChildren[childChar] = transformedChild
                    }
                    else {
                        newChildren.removeValue(forKey: childChar)
                    }
                }
                else {
                    let newChild = try Self.insertAll(childChar: childChar, transforms: transformChild)
                    newChildren[childChar] = ChildType(node: newChild)
                }
            }
            else {
                if let currentChild = children[childChar] {
                    newChildren[childChar] = currentChild
                }
                else {
                    throw TransformErrors.transformFailed
                }
            }
        }
        return newChildren
    }

    func get(key: ArraySlice<Character>) throws -> ValueType? {
        let prefixSlice = ArraySlice(prefix)

        if key.elementsEqual(prefixSlice) {
            return value
        }
        
        // If the remaining key starts with the compressed path, consume it
        if key.starts(with: prefixSlice) {
            let newKey = key.dropFirst(prefixSlice.count)
            guard let childChar = newKey.first else { return value }
            guard let child = children[childChar] else { return nil }
            guard let childNode = child.node else { throw TransformErrors.missingData }
            return try childNode.get(key: newKey)
        }
        
        // Otherwise, no match
        return nil
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
            let newChild = try child.deleting(key: newKey)
            if let newChild = newChild {
                var newChildren = children
                newChildren[childChar] = newChild
                return Self(prefix: prefix, value: value, children: newChildren)
            }
            if children.count == 1 && value == nil { return nil  }
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
            if let child = children[keyChar] {
                let updatedChild = try child.mutating(key: keyRemainder, value: value)
                var newChildren = children
                newChildren[keyChar] = updatedChild
                return Self(prefix: prefix, value: self.value, children: newChildren)
            } else {
                throw TransformErrors.invalidKey
            }
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
            let newChildren = [remainingPath.first!:existingChild]
            return Self(prefix: String(key), value: value, children: newChildren)
        default:
            let common = commonPrefixString(key, selfPathSlice)
            let keyRemainder = String(key.dropFirst(common.count))
            let pathRemainder = String(selfPathSlice.dropFirst(common.count))
            let existingChild = ChildType(node: Self(prefix: pathRemainder, value: self.value, children: children))
            let newChild = ChildType(node: Self(prefix: keyRemainder, value: value, children: [:]))
            let newChildren = [pathRemainder.first!: existingChild, keyRemainder.first!: newChild]
            return Self(prefix: common, value: nil, children: newChildren)
        }
    }
}

extension RadixNode where ValueType: Header, ValueType.NodeType: MerkleDictionary {
    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        guard let childPrefix = transforms.childPrefix(for: prefix.first!) else { throw TransformErrors.transformFailed }
        let childPrefixSlice = ArraySlice(childPrefix)
        let prefixSlice = ArraySlice(prefix)
        let comparison = compareSlices(childPrefixSlice, prefixSlice)
        if comparison == 0 {
            let traversedChild = transforms.traverse(path: childPrefix)
            if let traversedChild = traversedChild, let transform = traversedChild.get([""]) {
                if transforms.traverse([prefix]) != nil { throw TransformErrors.transformFailed }
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
            let newChildren = traversedChild == nil || traversedChild!.isEmpty ? children : try transformChildren(transforms: traversedChild!, keyProvider: keyProvider)
            if let traversedNext = transforms.traverse([childPrefix]) {
                if !traversedNext.isEmpty {
                    if let value = value {
                        if let newValue = try value.transform(transforms: traversedNext, keyProvider: keyProvider) {
                            return Self(prefix: prefix, value: newValue, children: newChildren)
                        }
                        return try collapsed(prefix: prefix, children: newChildren)
                    }
                    else {
                        let newDictionary = ValueType.NodeType()
                        let newHeader = ValueType(node: newDictionary)
                        let newHeaderValue = try newHeader.transform(transforms: traversedNext, keyProvider: keyProvider)
                        return Self(prefix: prefix, value: newHeaderValue, children: children)
                    }
                }
            }
            return try collapsed(prefix: prefix, children: newChildren)
        }
        if comparison == 1 {
            let remainingChildPrefix = childPrefixSlice.dropFirst(prefix.count)
            guard let traversedChild = transforms.traverse(path: prefix) else { throw TransformErrors.transformFailed }
            let childChar = remainingChildPrefix.first!
            if let child = children[childChar] {
                guard let childNode = child.node else { throw TransformErrors.missingData }
                if let newChild = try childNode.transform(transforms: traversedChild, keyProvider: keyProvider) {
                    var newChildren = children
                    newChildren[childChar] = try child.reEncryptIfNeeded(node: newChild, keyProvider: keyProvider)
                    return Self(prefix: prefix, value: value, children: newChildren)
                }
                else {
                    var newChildren = children
                    newChildren.removeValue(forKey: childChar)
                    if value != nil {
                        return Self(prefix: prefix, value: value, children: newChildren)
                    }
                    return try collapsed(prefix: prefix, children: newChildren)
                }
            }
            else {
                let newChild = try Self.insertAll(childChar: childChar, transforms: traversedChild)
                var newChildren = children
                newChildren[childChar] = ChildType(node: newChild)
                return Self(prefix: prefix, value: value, children: newChildren)
            }
        }
        if comparison == 2 {
            let remainingPrefix = prefixSlice.dropFirst(childPrefix.count)
            guard let existingNodeChar = remainingPrefix.first else { throw TransformErrors.transformFailed }
            guard let traversedChild = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
            var newChildren = [Character: ChildType]()
            var existingNodeHandled = false
            for childChar in traversedChild.childCharacters() {
                if childChar == existingNodeChar {
                    existingNodeHandled = true
                    guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
                    if let newChild = try Self(prefix: String(remainingPrefix), value: value, children: children).transform(transforms: childTransform, keyProvider: keyProvider) {
                        newChildren[childChar] = ChildType(node: newChild)
                    }
                }
                else {
                    guard let childTransform = traversedChild.traverseChild(childChar) else { throw TransformErrors.transformFailed }
                    let newChild = try Self.insertAll(childChar: childChar, transforms: childTransform)
                    newChildren[childChar] = ChildType(node: newChild)
                }
            }
            if !existingNodeHandled {
                newChildren[existingNodeChar] = ChildType(node: Self(prefix: String(remainingPrefix), value: value, children: children))
            }
            if let newValue = traversedChild.get([""]) {
                switch newValue {
                case .insert(let newValue):
                    guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                    return Self(prefix: childPrefix, value: newValue, children: newChildren)
                default: throw TransformErrors.transformFailed
                }
            }
            if let traversedNext = transforms.traverse([childPrefix]) {
                if !traversedNext.isEmpty {
                    let newDictionary = ValueType.NodeType()
                    let newHeader = ValueType(node: newDictionary)
                    let newHeaderValue = try newHeader.transform(transforms: traversedNext, keyProvider: keyProvider)
                    return Self(prefix: childPrefix, value: newHeaderValue, children: newChildren)
                }
            }
            return try collapsed(prefix: childPrefix, children: newChildren)
        }
        let common = commonPrefixString(prefixSlice, childPrefixSlice)
        let prefixSliceRemainder = String(prefixSlice.dropFirst(common.count))
        let childPrefixSliceRemainder = String(childPrefixSlice.dropFirst(common.count))
        guard let childTransforms = transforms.traverse(path: common)?.traverseChild(childPrefixSliceRemainder.first!) else { throw TransformErrors.transformFailed }
        let newChild = try Self.insertAll(childChar: childPrefixSliceRemainder.first!, transforms: childTransforms)
        var newChildren = [Character: ChildType]()
        newChildren[childPrefixSliceRemainder.first!] = ChildType(node: newChild)
        newChildren[prefixSliceRemainder.first!] = ChildType(node: Self(prefix: String(prefixSliceRemainder), value: value, children: children))
        return Self(prefix: common, value: nil, children: newChildren)
    }

    static func insertAll(childChar: Character, transforms: ArrayTrie<Transform>) throws -> Self {
        guard let childPrefix = transforms.childPrefix(for: childChar) else { throw TransformErrors.transformFailed }
        guard let traversedTransforms = transforms.traverse(path: childPrefix) else { throw TransformErrors.transformFailed }
        let childChars = traversedTransforms.childCharacters()
        var newProperties = [Character: ChildType]()
        for childChar in childChars {
            guard let traversedChild = traversedTransforms.traverseChild(childChar) else { throw TransformErrors.transformFailed }
            if traversedChild.isEmpty { throw TransformErrors.transformFailed }
            let newChildAfterInsertion = try insertAll(childChar: childChar, transforms: traversedChild)
            let newChild = ChildType(node: newChildAfterInsertion)
            newProperties[childChar] = newChild
        }
        if let transform = traversedTransforms.get([""]) {
            switch transform {
            case .insert(let newValue):
                guard let newValue = ValueType(newValue) else { throw TransformErrors.transformFailed }
                return Self(prefix: childPrefix, value: newValue, children: newProperties)
            default:
                throw TransformErrors.transformFailed
            }
        }
        if let traversedNext = transforms.traverse([childPrefix]) {
            if !traversedNext.isEmpty {
                let newDictionary = ValueType.NodeType()
                let newHeader = ValueType(node: newDictionary)
                let newHeaderValue = try newHeader.transform(transforms: traversedNext)
                return Self(prefix: childPrefix, value: newHeaderValue, children: newProperties)
            }
        }
        return Self(prefix: childPrefix, value: nil, children: newProperties)
    }
}
