/// Backward-compatible alias. In v2, VolumeMerkleDictionaryImpl is MerkleDictionaryImpl.
public typealias VolumeMerkleDictionaryImpl<Value> = MerkleDictionaryImpl<Value>
where Value: Codable, Value: Sendable, Value: LosslessStringConvertible
