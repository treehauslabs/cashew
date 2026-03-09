import ArrayTrie

public extension MerkleArray {
    func transform(transforms: ArrayTrie<Transform>) throws -> Self? {
        return try transform(transforms: transforms, keyProvider: nil)
    }

    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        guard let newBacking = try backing.transform(transforms: transforms, keyProvider: keyProvider) else { return nil }
        return Self(backing: newBacking, count: newBacking.count)
    }

    func mutating(at index: Int, value: Element) throws -> Self {
        guard index >= 0 && index < count else { throw TransformErrors.invalidKey }
        let newBacking = try backing.mutating(key: Self.binaryKey(index), value: value)
        return Self(backing: newBacking, count: count)
    }

    func deleting(at index: Int) throws -> Self {
        guard index >= 0 && index < count else { throw TransformErrors.invalidKey }
        let key = Self.binaryKey(index)
        let lastKey = Self.binaryKey(count - 1)
        if index == count - 1 {
            let newBacking = try backing.deleting(key: key)
            return Self(backing: newBacking, count: count - 1)
        }
        guard let lastElement = try backing.get(key: lastKey) else { throw TransformErrors.missingData }
        var transforms = ArrayTrie<Transform>()
        transforms.set([key], value: .update(String(describing: lastElement)))
        transforms.set([lastKey], value: .delete)
        guard let newBacking = try backing.transform(transforms: transforms) else { throw TransformErrors.transformFailed }
        return Self(backing: newBacking, count: count - 1)
    }

    static func rangeTransforms(range: Range<Int>, transform: Transform) -> ArrayTrie<Transform> {
        var trie = ArrayTrie<Transform>()
        for i in range {
            trie.set([binaryKey(i)], value: transform)
        }
        return trie
    }
}

public extension MerkleArray where Element: Header, Element.NodeType: MerkleArray {
    static func nestedRangeTransforms(outerRange: Range<Int>, innerTransforms: [[String]: Transform]) -> ArrayTrie<Transform> {
        var trie = ArrayTrie<Transform>()
        for i in outerRange {
            let outerKey = binaryKey(i)
            for (innerPath, transform) in innerTransforms {
                trie.set([outerKey] + innerPath, value: transform)
            }
        }
        return trie
    }

    func transformNested(outerRange: Range<Int>, innerTransforms: [[String]: Transform], keyProvider: KeyProvider? = nil) throws -> Self? {
        let trie = Self.nestedRangeTransforms(outerRange: outerRange, innerTransforms: innerTransforms)
        return try transform(transforms: trie, keyProvider: keyProvider)
    }
}
