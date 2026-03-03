public extension RadixHeader {
    func resolveChildren(fetcher: Fetcher) async throws -> Self {
        if let node = node {
            let newNode = try await node.resolveChildren(fetcher: fetcher)
            return Self(rawCID: rawCID, node: newNode, encryptionInfo: encryptionInfo)
        }
        else {
            let fetchedData = try await fetcher.fetch(rawCid: rawCID)
            let decrypted = try decryptIfNeeded(data: fetchedData, fetcher: fetcher)
            guard let node = NodeType(data: decrypted) else { throw CashewDecodingError.decodeFromDataError }
            let newNode = try await node.resolveChildren(fetcher: fetcher)
            return Self(rawCID: rawCID, node: newNode, encryptionInfo: encryptionInfo)
        }
    }
}
