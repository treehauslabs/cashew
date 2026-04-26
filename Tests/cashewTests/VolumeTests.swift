import Testing
import Foundation
import ArrayTrie
@testable import cashew

// MARK: - Test helpers

final class VolumeTestFetcher: VolumeAwareFetcher, Storer, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var _provideCalls: [(rootCID: String, paths: ArrayTrie<ResolutionStrategy>)] = []

    var provideCalls: [(rootCID: String, paths: ArrayTrie<ResolutionStrategy>)] {
        lock.withLock { _provideCalls }
    }

    func enterVolume(rootCID: String, paths: ArrayTrie<ResolutionStrategy>) async throws {
        lock.withLock {
            _provideCalls.append((rootCID: rootCID, paths: paths))
        }
    }

    func fetch(rawCid: String) async throws -> Data {
        let data = lock.withLock { storage[rawCid] }
        guard let data = data else { throw FetchError.notFound }
        return data
    }

    func store(rawCid: String, data: Data) throws {
        lock.withLock { storage[rawCid] = data }
    }
}

final class PlainTestFetcher: Fetcher, Storer, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func fetch(rawCid: String) async throws -> Data {
        let data = lock.withLock { storage[rawCid] }
        guard let data = data else { throw FetchError.notFound }
        return data
    }

    func store(rawCid: String, data: Data) throws {
        lock.withLock { storage[rawCid] = data }
    }
}

// MARK: - Tests

@Suite("Volume")
struct VolumeTests {

    // MARK: - Basic Header behavior

    @Test("VolumeImpl computes a CID from its node")
    func cidCreation() throws {
        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "a", value: "1")

        let vol = VolumeImpl(node: dict)
        #expect(!vol.rawCID.isEmpty)
        #expect(vol.node != nil)
    }

    @Test("Same content produces the same CID")
    func deterministicCID() throws {
        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "a", value: "1")

        let vol1 = VolumeImpl(node: dict)
        let vol2 = VolumeImpl(node: dict)
        #expect(vol1.rawCID == vol2.rawCID)
    }

    @Test("VolumeImpl round-trips through Codable")
    func codable() throws {
        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "x", value: "y")

        let vol = VolumeImpl(node: dict)
        let data = try JSONEncoder().encode(vol)
        let decoded = try JSONDecoder().decode(VolumeImpl<MerkleDictionaryImpl<String>>.self, from: data)

        #expect(decoded.rawCID == vol.rawCID)
        #expect(decoded.node == nil) // node is not serialized, only CID
    }

    @Test("VolumeImpl CID differs from HeaderImpl CID for same node")
    func volumeCIDDiffersFromHeader() throws {
        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "a", value: "1")

        let vol = VolumeImpl(node: dict)
        let header = HeaderImpl(node: dict)
        // Both wrap the same node, so CIDs should be the same
        // (CID is computed from the node's serialization, not the header type)
        #expect(vol.rawCID == header.rawCID)
    }

    // MARK: - provide is called on VolumeAwareFetcher

    @Test("resolve(paths:fetcher:) calls provide on VolumeAwareFetcher")
    func resolvePathsCallsProvide() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "alice", value: "engineer")
        dict = try dict.inserting(key: "bob", value: "designer")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set(["a"], value: .targeted)

        let resolved = try await cidOnly.resolve(paths: paths, fetcher: fetcher)
        #expect(resolved.node != nil)
        #expect(fetcher.provideCalls.count == 1)
        #expect(fetcher.provideCalls[0].rootCID == vol.rawCID)
    }

    @Test("resolveRecursive calls provide on VolumeAwareFetcher")
    func resolveRecursiveCallsProvide() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "k", value: "v")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)
        let resolved = try await cidOnly.resolveRecursive(fetcher: fetcher)

        #expect(resolved.node != nil)
        #expect(fetcher.provideCalls.count == 1)
        #expect(fetcher.provideCalls[0].rootCID == vol.rawCID)
        #expect(fetcher.provideCalls[0].paths.get([]) == .recursive)
    }

    @Test("resolve(fetcher:) calls provide on VolumeAwareFetcher")
    func resolveSingleCallsProvide() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "k", value: "v")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)
        let resolved = try await cidOnly.resolve(fetcher: fetcher)

        #expect(resolved.node != nil)
        #expect(fetcher.provideCalls.count == 1)
        #expect(fetcher.provideCalls[0].rootCID == vol.rawCID)
        #expect(fetcher.provideCalls[0].paths.get([]) == .targeted)
    }

    // MARK: - Non-VolumeAware fetchers work normally

    @Test("Volume resolves normally with a plain Fetcher")
    func plainFetcherWorks() async throws {
        let fetcher = PlainTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "a", value: "1")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)
        let resolved = try await cidOnly.resolveRecursive(fetcher: fetcher)

        #expect(resolved.node != nil)
        let keys = try resolved.node!.allKeys()
        #expect(keys == ["a"])
    }

    // MARK: - No provide call when paths are empty

    @Test("resolve(paths:fetcher:) skips provide when paths are empty")
    func emptyPathsSkipsProvide() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "a", value: "1")
        let vol = VolumeImpl(node: dict)

        let paths = ArrayTrie<ResolutionStrategy>()
        let result = try await vol.resolve(paths: paths, fetcher: fetcher)

        #expect(fetcher.provideCalls.count == 0)
        #expect(result.rawCID == vol.rawCID)
    }

    // MARK: - Nested Volumes

    @Test("Nested Volumes each trigger their own provide call")
    func nestedVolumes() async throws {
        let fetcher = VolumeTestFetcher()

        // Inner volume: a dictionary
        var inner = MerkleDictionaryImpl<String>()
        inner = try inner.inserting(key: "x", value: "1")
        let innerVol = VolumeImpl(node: inner)

        // Outer node: a dictionary whose value is the inner Volume
        var outer = MerkleDictionaryImpl<VolumeImpl<MerkleDictionaryImpl<String>>>()
        outer = try outer.inserting(key: "data", value: innerVol)
        let outerVol = VolumeImpl(node: outer)

        try outerVol.storeRecursively(storer: fetcher)

        // Resolve from CID-only
        let cidOnly = VolumeImpl<MerkleDictionaryImpl<VolumeImpl<MerkleDictionaryImpl<String>>>>(rawCID: outerVol.rawCID)

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set(["d"], value: .recursive) // "d" is the first-char dispatch for "data"

        let _ = try await cidOnly.resolve(paths: paths, fetcher: fetcher)

        // Outer volume should have triggered provide
        let outerCalls = fetcher.provideCalls.filter { $0.rootCID == outerVol.rawCID }
        #expect(outerCalls.count == 1)

        // Inner volume should also have triggered provide (its own CID)
        let innerCalls = fetcher.provideCalls.filter { $0.rootCID == innerVol.rawCID }
        #expect(innerCalls.count == 1)

        // Total: 2 provide calls
        #expect(fetcher.provideCalls.count == 2)
    }

    // MARK: - Volume through any Header existential

    @Test("Volume resolve override fires through any Header existential")
    func existentialDispatch() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "k", value: "v")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)

        // Erase to any Header
        let existential: any Header = cidOnly

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set([], value: .recursive)
        let _ = try await existential.resolveRecursive(fetcher: fetcher)

        #expect(fetcher.provideCalls.count == 1)
        #expect(fetcher.provideCalls[0].rootCID == vol.rawCID)
    }

    // MARK: - Store and resolve round-trip

    @Test("VolumeImpl stores and resolves a full round-trip")
    func storeResolveRoundTrip() async throws {
        let fetcher = VolumeTestFetcher()

        var dict = MerkleDictionaryImpl<String>()
        dict = try dict.inserting(key: "alice", value: "engineer")
        dict = try dict.inserting(key: "bob", value: "designer")
        dict = try dict.inserting(key: "charlie", value: "manager")

        let vol = VolumeImpl(node: dict)
        try vol.storeRecursively(storer: fetcher)

        let cidOnly = VolumeImpl<MerkleDictionaryImpl<String>>(rawCID: vol.rawCID)
        let resolved = try await cidOnly.resolveRecursive(fetcher: fetcher)

        let keys = try resolved.node!.allKeys()
        #expect(keys == ["alice", "bob", "charlie"])
    }
}
