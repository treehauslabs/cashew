import Foundation

actor ThreadSafeDictionary<Key: Hashable, Value>: Sendable {
    private var storage: [Key: Value] = [:]
    
    func set(_ key: Key, value: Value) {
        storage[key] = value
    }
    
    func get(_ key: Key) -> Value? {
        return storage[key]
    }
    
    func allKeyValuePairs() -> [Key: Value] {
        return storage
    }
}
