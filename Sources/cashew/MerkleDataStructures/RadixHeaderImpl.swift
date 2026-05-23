import Foundation
import Multicodec
import Multihash
import CID
import Crypto

/// Default concrete implementation of ``RadixHeader``.
public struct RadixHeaderImpl<Value>: RadixHeader where Value: Codable, Value: Sendable, Value: LosslessStringConvertible {
    public typealias NodeType = RadixNodeImpl<Value>

    public let rawCID: String
    public let rawNode: Box<NodeType>?
    public let encryptionInfo: EncryptionInfo?

    public var node: NodeType? {
        return rawNode?.boxed
    }

    public init(rawCID: String, node: NodeType?, encryptionInfo: EncryptionInfo?) {
        self.rawCID = rawCID
        self.rawNode = node.map { Box($0) }
        self.encryptionInfo = encryptionInfo
    }

    public init(node: NodeType, key: SymmetricKey) throws {
        let plaintext = try Self.serializeNode(node, codec: Self.defaultCodec)
        let (encrypted, iv) = try EncryptionHelper.encrypt(data: plaintext, key: key)
        let multihash = try Multihash(raw: encrypted, hashedWith: .sha2_256)
        let cid = try CID(version: .v1, codec: Self.defaultCodec, multihash: multihash)
        self.rawCID = cid.toBaseEncodedString
        self.rawNode = Box(node)
        self.encryptionInfo = EncryptionInfo(key: key, iv: iv)
    }
}

extension RadixHeaderImpl: Volume { }
extension RadixHeaderImpl: VolumeRadixHeader { }

// Explicit storeRecursively to resolve Swift protocol dispatch ambiguity.
// RadixHeaderImpl conforms to both Header and Volume; without this the
// compiler may dispatch to Volume+store.swift, which ignores encryptionInfo
// and stores plain bytes at an encrypted CID — causing authenticationFailure
// on the subsequent decrypt during resolve. Mirrors HeaderImpl's explicit impl.
extension RadixHeaderImpl {
    public func storeRecursively(storer: Storer) throws {
        guard let node = node else { return }
        if storer.contains(rawCid: rawCID) { return }
        let dataToStore: Data
        if let info = encryptionInfo {
            guard let keyProvider = storer as? KeyProvider else { throw DataErrors.keyNotFound }
            guard let key = keyProvider.key(for: info.keyHash) else { throw DataErrors.keyNotFound }
            guard let ivData = info.ivData else { throw DataErrors.invalidIV }
            let nonce = try AES.GCM.Nonce(data: ivData)
            let plaintext = try Self.serializeNode(node, codec: Self.defaultCodec)
            dataToStore = try EncryptionHelper.encrypt(data: plaintext, key: key, nonce: nonce)
        } else {
            guard let nodeData = node.toData() else { throw DataErrors.serializationFailed }
            dataToStore = nodeData
        }
        if self is any Volume, let volumeAware = storer as? VolumeAwareStorer {
            try volumeAware.enterVolume(rootCID: rawCID)
            try volumeAware.store(rawCid: rawCID, data: dataToStore)
            try node.storeRecursively(storer: volumeAware)
            try volumeAware.exitVolume(rootCID: rawCID)
        } else {
            try storer.store(rawCid: rawCID, data: dataToStore)
            try node.storeRecursively(storer: storer)
        }
    }
}

// MARK: - Codable
extension RadixHeaderImpl: Codable {
    enum CodingKeys: String, CodingKey {
        case rawCID
        case encryptionInfo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawCID, forKey: .rawCID)
        try container.encodeIfPresent(encryptionInfo, forKey: .encryptionInfo)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawCID = try container.decode(String.self, forKey: .rawCID)
        encryptionInfo = try container.decodeIfPresent(EncryptionInfo.self, forKey: .encryptionInfo)
        rawNode = nil
    }
}
