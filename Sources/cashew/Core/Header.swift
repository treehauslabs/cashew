import Foundation
import ArrayTrie
import CID
import Multicodec
import Multihash
import Crypto

public protocol Header: Codable, Address, LosslessStringConvertible {
    associatedtype NodeType: Node

    var rawCID: String { get }
    var node: NodeType? { get }
    var encryptionInfo: EncryptionInfo? { get }

    init(rawCID: String)
    init(node: NodeType)
    init(node: NodeType, codec: Codecs)

    init(rawCID: String, node: NodeType?)
    init(rawCID: String, node: NodeType?, encryptionInfo: EncryptionInfo?)
    init(node: NodeType, key: SymmetricKey) throws
}

public extension Header {
    var encryptionInfo: EncryptionInfo? { nil }

    init(rawCID: String) {
        self = Self(rawCID: rawCID, node: nil, encryptionInfo: nil)
    }

    init(rawCID: String, node: NodeType?) {
        self = Self(rawCID: rawCID, node: node, encryptionInfo: nil)
    }

    init(node: NodeType) {
        self = Self(rawCID: Self.createSyncCID(for: node, codec: Self.defaultCodec), node: node, encryptionInfo: nil)
    }

    init(node: NodeType, codec: Codecs) {
        self = Self(rawCID: Self.createSyncCID(for: node, codec: codec), node: node, encryptionInfo: nil)
    }

    static var defaultCodec: Codecs { .dag_json }

    static func create(node: NodeType, codec: Codecs = defaultCodec) async throws -> Self {
        let cid = try await createCID(for: node, codec: codec)
        return Self(rawCID: cid, node: node, encryptionInfo: nil)
    }

    private static func createCID(for node: NodeType, codec: Codecs) async throws -> String {
        let data = try serializeNode(node, codec: codec)
        let multihash = try Multihash(raw: data, hashedWith: .sha2_256)
        let cid = try CID(version: .v1, codec: codec, multihash: multihash)
        return cid.toBaseEncodedString
    }

    static func createSyncCID(for node: NodeType, codec: Codecs) -> String {
        do {
            let data = try serializeNode(node, codec: codec)
            let multihash = try Multihash(raw: data, hashedWith: .sha2_256)
            let cid = try CID(version: .v1, codec: codec, multihash: multihash)
            return cid.toBaseEncodedString
        } catch {
            return "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
        }
    }

    static func serializeNode(_ node: NodeType, codec: Codecs) throws -> Data {
        guard let data = node.toData() else { throw DataErrors.serializationFailed }
        return data
    }

    func mapToData() throws -> Data {
        guard let node = self.node else {
            throw DataErrors.nodeNotAvailable
        }
        return try Self.serializeNode(node, codec: Self.defaultCodec)
    }

    func recreateCID() async throws -> String {
        guard let node = self.node else {
            return rawCID
        }
        return try await Self.createCID(for: node, codec: Self.defaultCodec)
    }

    func recreateCID(withCodec codec: Codecs) async throws -> String {
        guard let node = self.node else {
            throw DataErrors.nodeNotAvailable
        }
        return try await Self.createCID(for: node, codec: codec)
    }

    var description: String {
        if let info = encryptionInfo {
            return "enc:\(info.keyHash):\(info.iv):\(rawCID)"
        }
        return rawCID
    }

    init?(_ description: String) {
        if description.hasPrefix("enc:") {
            let remainder = description.dropFirst(4)
            let parts = remainder.split(separator: ":", maxSplits: 2)
            guard parts.count == 3 else { return nil }
            let keyHash = String(parts[0])
            let iv = String(parts[1])
            let cid = String(parts[2])
            let info = EncryptionInfo(keyHash: keyHash, iv: iv)
            self = Self(rawCID: cid, node: nil, encryptionInfo: info)
        } else {
            self = Self(rawCID: description, node: nil, encryptionInfo: nil)
        }
    }

    func removingNode() -> Self {
        return Self(rawCID: rawCID, node: nil, encryptionInfo: encryptionInfo)
    }

    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        let encryptedNode = try node.encrypt(encryption: encryption)
        return Self(node: encryptedNode)
    }

    func encryptSelf(key: SymmetricKey) throws -> Self {
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        return try Self(node: node, key: key)
    }

    func reEncryptIfNeeded(node: NodeType, keyProvider: KeyProvider?) throws -> Self {
        guard let info = encryptionInfo, let keyProvider = keyProvider else { return Self(node: node) }
        guard let key = keyProvider.key(for: info.keyHash) else { throw DataErrors.keyNotFound }
        return try Self(node: node, key: key)
    }

    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self? {
        if transforms.isEmpty() { return self }
        guard let node = node else { throw DataErrors.nodeNotAvailable }
        guard let result = try node.transform(transforms: transforms, keyProvider: keyProvider) else { return nil }
        return try reEncryptIfNeeded(node: result, keyProvider: keyProvider)
    }

    func decryptIfNeeded(data: Data, fetcher: Fetcher) throws -> Data {
        guard let info = encryptionInfo else { return data }
        guard let keyProvider = fetcher as? KeyProvider else {
            throw DataErrors.keyNotFound
        }
        guard let key = keyProvider.key(for: info.keyHash) else {
            throw DataErrors.keyNotFound
        }
        return try EncryptionHelper.decrypt(data: data, key: key)
    }
}
