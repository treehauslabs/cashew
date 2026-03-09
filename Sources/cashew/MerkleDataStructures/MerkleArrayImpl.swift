public struct MerkleArrayImpl<Value>: MerkleArray where Value: Codable, Value: Sendable, Value: LosslessStringConvertible {
    public typealias Element = Value
    public typealias DictionaryType = MerkleDictionaryImpl<Value>

    public let backing: DictionaryType
    public let count: Int

    public init(backing: DictionaryType, count: Int) {
        self.backing = backing
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case backing, count
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backing, forKey: .backing)
        try container.encode(count, forKey: .count)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backing = try container.decode(DictionaryType.self, forKey: .backing)
        count = try container.decode(Int.self, forKey: .count)
    }
}
