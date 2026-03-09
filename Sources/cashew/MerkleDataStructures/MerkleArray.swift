import ArrayTrie

public protocol MerkleArray: Node {
    associatedtype Element
    associatedtype DictionaryType: MerkleDictionary where DictionaryType.ValueType == Element

    var backing: DictionaryType { get }
    var count: Int { get }

    init(backing: DictionaryType, count: Int)
}

public extension MerkleArray {
    init() {
        self.init(backing: DictionaryType(), count: 0)
    }

    func get(property: PathSegment) -> Address? {
        return backing.get(property: property)
    }

    func properties() -> Set<PathSegment> {
        return backing.properties()
    }

    func set(properties: [PathSegment: Address]) -> Self {
        return Self(backing: backing.set(properties: properties), count: count)
    }

    static func binaryKey(_ index: Int) -> String {
        var chars = [Character](repeating: "0", count: 256)
        var val = index
        var pos = 255
        while val > 0 && pos >= 0 {
            if val & 1 == 1 {
                chars[pos] = "1"
            }
            val >>= 1
            pos -= 1
        }
        return String(chars)
    }

    func get(at index: Int) throws -> Element? {
        guard index >= 0 && index < count else { return nil }
        return try backing.get(key: Self.binaryKey(index))
    }

    func append(_ element: Element) throws -> Self {
        let newBacking = try backing.inserting(key: Self.binaryKey(count), value: element)
        return Self(backing: newBacking, count: count + 1)
    }

    func append(contentsOf other: Self) throws -> Self {
        var result = self
        for i in 0..<other.count {
            guard let element = try other.get(at: i) else { throw DataErrors.nodeNotAvailable }
            result = try result.append(element)
        }
        return result
    }

    func first() throws -> Element? {
        guard count > 0 else { return nil }
        return try get(at: 0)
    }

    func last() throws -> Element? {
        guard count > 0 else { return nil }
        return try get(at: count - 1)
    }
}
