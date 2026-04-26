public extension VolumeRadixHeader {
    func storeRecursively(storer: Storer) throws {
        guard let node = node else { return }
        if let volumeAware = storer as? VolumeAwareStorer {
            try volumeAware.enterVolume(rootCID: rawCID)
        }
        guard let nodeData = node.toData() else { throw DataErrors.serializationFailed }
        try storer.store(rawCid: rawCID, data: nodeData)
        try node.storeRecursively(storer: storer)
        if let volumeAware = storer as? VolumeAwareStorer {
            try volumeAware.exitVolume(rootCID: rawCID)
        }
    }
}
