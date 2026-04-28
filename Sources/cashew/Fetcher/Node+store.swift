public extension Node {
    func storeRecursively(storer: Storer) throws {
        let props = properties()
        var volumes: [(PathSegment, any Header)] = []
        for property in props {
            guard let header = get(property: property) else { continue }
            if header is any Volume {
                volumes.append((property, header))
            } else {
                try header.storeRecursively(storer: storer)
            }
        }
        for (_, header) in volumes {
            if let vrh = header as? any VolumeRadixHeader {
                try vrh.storeRecursively(storer: storer)
            } else {
                try (header as! any Volume).storeRecursively(storer: storer)
            }
        }
    }
}
