import CID
import Foundation

/// Persists serialized node data to a content-addressed store.
public protocol Storer {
    func store(rawCid: String, data: Data) throws
}
