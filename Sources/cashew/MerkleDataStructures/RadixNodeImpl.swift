import Foundation

public struct RadixNodeImpl<Value>: RadixNode where Value: Codable, Value: Sendable, Value: LosslessStringConvertible {
    public typealias ValueType = Value
    public typealias ChildType = RadixHeaderImpl<Value>
    
    public var prefix: String
    public var value: ValueType?
    public var children: [Character : ChildType]
    
    public init(prefix: String, value: ValueType?, children: [Character: ChildType]) {
        self.prefix = prefix
        self.value = value
        self.children = children
    }
    
    enum CodingKeys: String, CodingKey {
        case prefix, value, children
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prefix, forKey: .prefix)
        try container.encodeIfPresent(value, forKey: .value)
        
        // Convert Character keys to String for encoding
        let stringKeyChildren = Dictionary(uniqueKeysWithValues: children.map { (String($0.key), $0.value) })
        try container.encode(stringKeyChildren, forKey: .children)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prefix = try container.decode(String.self, forKey: .prefix)
        value = try container.decodeIfPresent(ValueType.self, forKey: .value)
        
        // Convert String keys back to Character
        let stringKeyChildren = try container.decode([String: ChildType].self, forKey: .children)
        children = Dictionary(uniqueKeysWithValues: stringKeyChildren.compactMap { key, value in
            guard let char = key.first else { return nil }
            return (char, value)
        })
    }
}
