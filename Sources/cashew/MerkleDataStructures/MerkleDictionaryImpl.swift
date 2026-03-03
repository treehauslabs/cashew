public struct MerkleDictionaryImpl<Value>: MerkleDictionary where Value: Codable, Value: Sendable, Value: LosslessStringConvertible {
    public typealias ValueType = Value
    public typealias ChildType = RadixHeaderImpl<Value>
    
    public var count: Int
    public var children: [Character : ChildType]

    public init(children: [Character : ChildType], count: Int) {
        self.children = children
        self.count = count
    }
    
    enum CodingKeys: String, CodingKey {
        case children, count
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        
        // Convert Character keys to String for encoding
        let stringKeyChildren = Dictionary(uniqueKeysWithValues: children.map { (String($0.key), $0.value) })
        try container.encode(stringKeyChildren, forKey: .children)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        
        // Convert String keys back to Character
        let stringKeyChildren = try container.decode([String: ChildType].self, forKey: .children)
        children = Dictionary(uniqueKeysWithValues: stringKeyChildren.compactMap { key, value in
            guard let char = key.first else { return nil }
            return (char, value)
        })
    }
}
