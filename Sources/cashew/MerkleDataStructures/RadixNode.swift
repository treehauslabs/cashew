public protocol RadixNode: Node {
    associatedtype ChildType: RadixHeader where ChildType.NodeType == Self
    associatedtype ValueType: LosslessStringConvertible
    
    var prefix: String { get }
    var value: ValueType? { get }
    var children: [Character: ChildType] { get }
    
    init(prefix: String, value: ValueType?, children: [Character: ChildType])
}

public extension RadixNode {
    func keepingOnlyLinks() -> Self {
        var newProperties = [String: Address]()
        for property in properties() {
            newProperties[property] = get(property: property)!.removingNode()
        }
        if value is Address {
            if let value = value {
                let newValue = (value as! Address).removingNode() as! ValueType
                let newNode = set(properties: newProperties)
                return Self(prefix: prefix, value: newValue, children: newNode.children)
            }
        }
        return set(properties: newProperties)
    }
    
    func storeRecursively(storer: Storer) throws {
        try properties().forEach { property in
            try get(property: property)?.storeRecursively(storer: storer)
        }
        if value is Address {
            if let value = value {
                try (value as! Address).storeRecursively(storer: storer)
            }
        }
    }
    
    func set(properties: [PathSegment : any Address]) -> Self {
        var newProperties = [Character: ChildType]()
        for property in properties.keys {
            newProperties.updateValue(properties[property] as! ChildType, forKey: property.first!)
        }
        return Self(prefix: prefix, value: value, children: newProperties)
    }
    
    func set(properties: [Character: ChildType]) -> Self {
        return Self(prefix: prefix, value: value, children: properties)
    }
    
    func get(property: PathSegment) -> Address? {
        guard let char = property.first else { return nil }
        return children[char]
    }

    func getChild(property: PathSegment) -> ChildType {
        return children[property.first!]!
    }
    
    func properties() -> Set<PathSegment> {
        return Set(children.keys.map({ character in String(character) }))
    }
    
    func set(property: PathSegment, to child: any Address) -> Self {
        guard let typedChild = child as? ChildType, let char = property.first else { return self }
        var newChildren = children
        newChildren[char] = typedChild
        return Self(prefix: prefix, value: value, children: newChildren)
    }
}
