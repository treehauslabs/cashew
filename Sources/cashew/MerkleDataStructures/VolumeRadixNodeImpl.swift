/// Backward-compatible alias. In v2, VolumeRadixNodeImpl is RadixNodeImpl.
public typealias VolumeRadixNodeImpl<Value> = RadixNodeImpl<Value>
where Value: Codable, Value: Sendable, Value: LosslessStringConvertible
