public extension Volume {
    func storeRecursively(storer: Storer) throws {
        guard let node = node else { return }
        if storer.contains(rawCid: rawCID) { return }
        if let volumeAware = storer as? VolumeAwareStorer {
            try volumeAware.provide(rootCID: rawCID)
        }
        guard let nodeData = node.toData() else { throw DataErrors.serializationFailed }
        try storer.store(rawCid: rawCID, data: nodeData)
        try node.storeRecursively(storer: storer)
    }
}
