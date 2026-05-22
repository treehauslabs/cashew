/// Backward-compatible alias. In v2, every RadixHeader is a Volume boundary.
public typealias VolumeRadixHeaderImpl<Value> = RadixHeaderImpl<Value>
where Value: Codable, Value: Sendable, Value: LosslessStringConvertible
