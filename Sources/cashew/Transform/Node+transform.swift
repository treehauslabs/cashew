import ArrayTrie
import CollectionConcurrencyKit

public extension Node {    
    func transform(transforms: ArrayTrie<Transform>) throws -> Self? {
        if transforms.isEmpty { return self }
        switch transforms.get([]) {
            case .update(let newNodeString):
                guard let updatedNode = Self(newNodeString) else { throw TransformErrors.transformFailed }
                return try updatedNode.transformAfterUpdate(transforms: transforms)
            default: return try transformAfterUpdate(transforms: transforms)
        }
    }
    
    func transformAfterUpdate(transforms: ArrayTrie<Transform>) throws -> Self? {
        var newProperties: [PathSegment: Address] = [:]

        let allChildKeys = Set<String>().union(transforms.childKeys()).union(properties())

        for childKey in allChildKeys {
            guard let address = get(property: childKey) else { throw TransformErrors.transformFailed }
            if let newTransforms = transforms.traverse([childKey]) {
                guard let newAddress = try address.transform(transforms: newTransforms) else { throw TransformErrors.transformFailed }
                newProperties[childKey] = newAddress
            }
            else {
                newProperties[childKey] = address
            }
        }

        return set(properties: newProperties)
    }

    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        if transforms.isEmpty { return self }
        switch transforms.get([]) {
            case .update(let newNodeString):
                guard let updatedNode = Self(newNodeString) else { throw TransformErrors.transformFailed }
                return try updatedNode.transformAfterUpdate(transforms: transforms, keyProvider: keyProvider)
            default: return try transformAfterUpdate(transforms: transforms, keyProvider: keyProvider)
        }
    }

    func transformAfterUpdate(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        var newProperties: [PathSegment: Address] = [:]

        let allChildKeys = Set<String>().union(transforms.childKeys()).union(properties())

        for childKey in allChildKeys {
            guard let address = get(property: childKey) else { throw TransformErrors.transformFailed }
            if let newTransforms = transforms.traverse([childKey]) {
                guard let newAddress = try address.transform(transforms: newTransforms, keyProvider: keyProvider) else { throw TransformErrors.transformFailed }
                newProperties[childKey] = newAddress
            }
            else {
                newProperties[childKey] = address
            }
        }

        return set(properties: newProperties)
    }
}
