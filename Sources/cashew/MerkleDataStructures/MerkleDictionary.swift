import ArrayTrie

public protocol MerkleDictionary: Node {
    associatedtype ValueType
    associatedtype ChildType: RadixHeader where ChildType.NodeType.ValueType == ValueType
    
    var children: [Character: ChildType] { get }
    var count: Int { get }
    
    init(children: [Character: ChildType], count: Int)
}

public extension MerkleDictionary {
    init() {
        self.init(children: [:], count: 0)
    }
    
    func get(property: PathSegment) -> Address? {
        guard let char = property.first else { return nil }
        return children[char]
    }
    
    func properties() -> Set<PathSegment> {
        return Set(children.keys.map { String($0) })
    }
    
    func set(properties: [PathSegment: Address]) -> Self {
        var newProperties = [Character: ChildType]()
        for property in properties {
            newProperties[property.key.first!] = property.value as? ChildType
        }
        return Self(children: newProperties, count: count)
    }
    
    func set(properties: [Character: ChildType]) -> Self {
        return Self(children: properties, count: count)
    }
    
    func allKeys() throws -> Set<String> {
        var keys = Set<String>()
        
        for (_, child) in children {
            guard let node = child.node else { throw DataErrors.nodeNotAvailable }
            try collectKeys(from: node, currentPath: "", into: &keys)
        }
        
        return keys
    }
    
    func allKeysAndValues() throws -> [String: ValueType] {
        var keysAndValues = [String: ValueType]()
        
        for (_, child) in children {
            guard let node = child.node else { throw DataErrors.nodeNotAvailable }
            try collectKeysAndValues(from: node, currentPath: "", into: &keysAndValues)
        }
        
        return keysAndValues
    }
    
    private func collectKeys(from node: ChildType.NodeType, currentPath: String, into keys: inout Set<String>) throws {
        let fullPath = currentPath + node.prefix
        
        // If this node has a value, it represents a complete key
        if node.value != nil {
            keys.insert(fullPath)
        }
        
        // Recursively traverse children
        for (_, child) in node.children {
            guard let childNode = child.node else { throw DataErrors.nodeNotAvailable }
            try collectKeys(from: childNode, currentPath: fullPath, into: &keys)
        }
    }
    
    private func collectKeysAndValues(from node: ChildType.NodeType, currentPath: String, into keysAndValues: inout [String: ValueType]) throws {
        let fullPath = currentPath + node.prefix
        
        // If this node has a value, it represents a complete key-value pair
        if let value = node.value {
            keysAndValues[fullPath] = value
        }
        
        // Recursively traverse children
        for (_, child) in node.children {
            guard let childNode = child.node else { throw DataErrors.nodeNotAvailable }
            try collectKeysAndValues(from: childNode, currentPath: fullPath, into: &keysAndValues)
        }
    }
}
