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
            try header.storeRecursively(storer: storer)
        }
    }
}
