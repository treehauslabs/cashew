import ArrayTrie
import Foundation
import Multicodec
import CollectionConcurrencyKit

public protocol Node: CashewQueryable, Codable, LosslessStringConvertible, Sendable {
    typealias PathSegment = String

    // traversal
    func get(property: PathSegment) -> Address?
    func properties() -> Set<PathSegment>
    
    // update
    func set(properties: [PathSegment: Address]) -> Self
    
    func resolve(paths: ArrayTrie<ResolutionStrategy>, fetcher: Fetcher) async throws -> Self
    func storeRecursively(storer: Storer) throws
    func transform(transforms: ArrayTrie<Transform>) throws -> Self?
    func transform(transforms: ArrayTrie<Transform>, keyProvider: KeyProvider?) throws -> Self?
    func proof(paths: ArrayTrie<SparseMerkleProof>, fetcher: Fetcher) async throws -> Self
    func encrypt(encryption: ArrayTrie<EncryptionStrategy>) throws -> Self
}

private let sharedJSONDecoder = JSONDecoder()
private let sharedJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

public extension Node {
    init?(data: Data) {
       guard let decoded = try? sharedJSONDecoder.decode(Self.self, from: data) else { return nil }
       self = decoded
    }
    
    func toData() -> Data? {
        return try? sharedJSONEncoder.encode(self)
    }
    
    init?(_ description: String) {
        guard let data = description.data(using: .utf8) else { return nil }
        guard let newNode = Self(data: data) else { return nil }
        self = newNode
    }
    
    var description: String {
        guard let data = toData() else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Node {
    @inline(__always)
    func compareSlices(_ slice1: ArraySlice<Character>, _ slice2: ArraySlice<Character>) -> Int {
        if (slice1.elementsEqual(slice2)) { return 0 }
        if (slice1.starts(with: slice2)) { return 1 }
        if (slice2.starts(with: slice1)) { return 2 }
        else { return 3 }
    }
    
    @inline(__always)
    func commonPrefixString(_ slice1: ArraySlice<Character>, _ slice2: ArraySlice<Character>) -> String {
        return commonPrefix(slice1, slice2)
    }
    
    func commonPrefix(_ slice1: ArraySlice<Character>, _ slice2: ArraySlice<Character>) -> String {
        // Optimize: Pre-allocate string capacity and avoid repeated memory allocations
        let maxLength = min(slice1.count, slice2.count)
        var result = ""
        result.reserveCapacity(maxLength)
        
        let pairs = zip(slice1, slice2)
        for (char1, char2) in pairs {
            if char1 == char2 {
                result.append(char1)
            } else {
                break
            }
        }
        
        return result
    }
}
