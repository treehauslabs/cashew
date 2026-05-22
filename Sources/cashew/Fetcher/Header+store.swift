import Foundation
import Crypto

public extension Header {
    func storeRecursively(storer: Storer) throws {
        guard let node = node else {
            return
        }
        let alreadyContains = storer.contains(rawCid: rawCID)
        let isVol = self is any Volume
        if alreadyContains && isVol { print("SKIP-VOLUME: \(rawCID.prefix(12)) isVol=\(isVol)") }
        if alreadyContains { return }
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
        let isVolume = self is any Volume
        let isVolumeAware = storer is any VolumeAwareStorer
        if isVolume && isVolumeAware { print("DEBUG VOLUME STORE: \(rawCID.prefix(12))") }
        // If this Header is also a Volume and the storer is VolumeAware, use enter/exit
        // scope management so sub-volumes are stored under their own roots. Calling
        // through `any Header` bypasses the Volume+store.swift override (Swift existential
        // dispatch limitation), so we check the runtime type here instead.
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
