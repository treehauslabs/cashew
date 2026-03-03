public extension Node {
    func storeRecursively(storer: Storer) throws {
        try properties().forEach { property in
            try get(property: property)?.storeRecursively(storer: storer)
        }
    }
}
