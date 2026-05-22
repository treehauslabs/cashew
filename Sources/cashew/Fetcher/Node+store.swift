public extension Node {
    func storeRecursively(storer: Storer) throws {
        for property in properties() {
            guard let header = get(property: property) else { continue }
            try header.storeRecursively(storer: storer)
        }
    }
}
