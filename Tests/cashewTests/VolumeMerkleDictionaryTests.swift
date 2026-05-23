import Testing
import Foundation
import ArrayTrie
@testable import cashew

/// Pins the central invariant of ``VolumeMerkleDictionaryImpl``: every header
/// reachable from the root is a ``Volume``. The pin-ledger model of GC — liveness
/// means "some chain's pin set references this Volume root" — only works if every
/// trie-internal link is itself a Volume boundary that can be pinned independently.
/// If a single internal header drops Volume conformance, its subtree becomes
/// protected only transitively by the nearest outer Volume, and any sweep that
/// collects that outer Volume also collects the subtree — even if a different
/// chain still needs it. These tests would catch that.
@Suite("Volume Merkle Dictionary — all headers are Volumes")
struct VolumeMerkleDictionaryTests {

    typealias Dict = VolumeMerkleDictionaryImpl<String>

    // MARK: - Traversal helpers

    /// Walks every header reachable from a root dictionary and runs `visit` on
    /// each. Calls into `children` directly (no resolve) because the tests
    /// construct the trie in-memory — every node is already present.
    static func visitAllHeaders(
        in dict: Dict,
        visit: (any Header) throws -> Void
    ) throws {
        for (_, child) in dict.children {
            try visitHeader(child, visit: visit)
        }
    }

    static func visitHeader(
        _ header: VolumeRadixHeaderImpl<String>,
        visit: (any Header) throws -> Void
    ) throws {
        try visit(header)
        guard let node = header.node else {
            throw TestError.nodeMissing(cid: header.rawCID)
        }
        for (_, child) in node.children {
            try visitHeader(child, visit: visit)
        }
    }

    enum TestError: Error {
        case nodeMissing(cid: String)
    }

    // MARK: - The core invariant

    @Test("Every header in an inserted trie is a Volume (shallow, one key)")
    func shallowIsVolume() throws {
        let dict = try Dict().inserting(key: "alice", value: "v1")

        var count = 0
        try Self.visitAllHeaders(in: dict) { header in
            #expect(header is any Volume,
                    "header at CID \(header.rawCID) is not a Volume")
            count += 1
        }
        #expect(count >= 1, "expected at least one header in the trie")
    }

    @Test("Every header in a branched trie is a Volume")
    func branchedIsVolume() throws {
        // Two keys that share a common prefix force the radix trie to split
        // on the shared edge. Two keys with different leading chars force two
        // distinct top-level children. Together they produce a trie with
        // both branching and path compression — the most likely places for a
        // missing-Volume bug to hide.
        let dict = try Dict()
            .inserting(key: "alice", value: "v1")
            .inserting(key: "alicia", value: "v2")
            .inserting(key: "bob", value: "v3")
            .inserting(key: "carol", value: "v4")

        var count = 0
        try Self.visitAllHeaders(in: dict) { header in
            #expect(header is any Volume,
                    "header at CID \(header.rawCID) is not a Volume")
            count += 1
        }
        // Expect: 3 top-level children (a, b, c) + split under 'a' for alice/alicia.
        #expect(count >= 4,
                "expected at least 4 headers after inserting 4 keys with one shared prefix, got \(count)")
    }

    @Test("Every header in a deep trie is a Volume")
    func deepIsVolume() throws {
        // Build a trie deep enough to exercise many levels of recursion.
        var dict = Dict()
        for i in 0..<50 {
            dict = try dict.inserting(key: "key-\(i)", value: "v\(i)")
        }

        var count = 0
        try Self.visitAllHeaders(in: dict) { header in
            #expect(header is any Volume,
                    "header at CID \(header.rawCID) is not a Volume")
            count += 1
        }
        #expect(count > 0)
    }

    // MARK: - Outer wrapping

    @Test("VolumeImpl<VolumeMerkleDictionaryImpl> is itself a Volume, and every descendant header is a Volume")
    func wrappedRootIsVolume() throws {
        let dict = try Dict()
            .inserting(key: "alice", value: "v1")
            .inserting(key: "bob", value: "v2")

        let outer = VolumeImpl(node: dict)
        #expect((outer as any Header) is any Volume)

        // Every child header inside is a Volume too.
        try Self.visitAllHeaders(in: outer.node!) { header in
            #expect(header is any Volume)
        }
    }

    // MARK: - provide() fires at every boundary during resolve

    /// Fetcher that records each ``VolumeAwareFetcher/provide`` call. Serves
    /// nodes from an in-memory store so we can resolve the full trie after
    /// stripping it to CIDs only.
    final class ProvideRecordingFetcher: VolumeAwareFetcher, Storer, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: Data] = [:]
        private var _providedRoots: [String] = []

        var providedRoots: [String] {
            lock.withLock { _providedRoots }
        }

        func enterVolume(rootCID: String, paths: ArrayTrie<ResolutionStrategy>) async throws {
            lock.withLock { _providedRoots.append(rootCID) }
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

    @Test("Resolving the trie fires provide() at every trie node — not just the root")
    func provideFiresAtEveryNode() async throws {
        let dict = try Dict()
            .inserting(key: "alice", value: "v1")
            .inserting(key: "alicia", value: "v2")
            .inserting(key: "bob", value: "v3")

        let fetcher = ProvideRecordingFetcher()
        let outer = VolumeImpl(node: dict)
        try outer.storeRecursively(storer: fetcher)

        // Collect every CID we put on the wire for later comparison.
        var expectedCIDs: Set<String> = [outer.rawCID]
        try Self.visitAllHeaders(in: dict) { header in
            expectedCIDs.insert(header.rawCID)
        }

        // Strip in-memory nodes so resolve has to fetch.
        let stripped = VolumeImpl<Dict>(rawCID: outer.rawCID, node: nil, encryptionInfo: nil)
        _ = try await stripped.resolveRecursive(fetcher: fetcher)

        // Every Volume boundary we walked past must have called provide.
        let provided = Set(fetcher.providedRoots)
        for cid in expectedCIDs {
            #expect(provided.contains(cid),
                    "expected provide() to fire for CID \(cid) but fetcher saw roots: \(fetcher.providedRoots)")
        }
    }
}

/// A node with both HeaderImpl (non-Volume) and VolumeImpl children.
/// Mimics Block's structure where `spec` is HeaderImpl and `frontier` is VolumeImpl.
private struct MixedNode: Node, Sendable {
    typealias Dict = VolumeMerkleDictionaryImpl<String>
    let label: HeaderImpl<Dict>
    let data: VolumeImpl<Dict>

    static let LABEL = "label"
    static let DATA = "data"

    func properties() -> Set<String> { [Self.LABEL, Self.DATA] }
    func get(property: String) -> (any Header)? {
        switch property {
        case Self.LABEL: return label
        case Self.DATA: return data
        default: return nil
        }
    }
    func set(properties: [String: any Header]) -> MixedNode {
        MixedNode(
            label: properties[Self.LABEL] as? HeaderImpl<Dict> ?? label,
            data: properties[Self.DATA] as? VolumeImpl<Dict> ?? data
        )
    }
}

// MARK: - Multi-level Volume hierarchy with custom nodes

/// A division of a company. Its `teams` are each their own Volume, so a
/// Division owning a Volume boundary nests a second layer of Volumes underneath.
private struct Division: Node, Sendable {
    var teams: [String: VolumeImpl<VolumeMerkleDictionaryImpl<String>>]

    init(teams: [String: VolumeImpl<VolumeMerkleDictionaryImpl<String>>] = [:]) {
        self.teams = teams
    }

    func properties() -> Set<String> { Set(teams.keys) }
    func get(property: String) -> (any Header)? { teams[property] }
    func set(properties: [String: any Header]) -> Division {
        var copy = self
        for (k, v) in properties {
            if let vol = v as? VolumeImpl<VolumeMerkleDictionaryImpl<String>> {
                copy.teams[k] = vol
            }
        }
        return copy
    }
}

/// A company holding several divisions. Each division is a Volume (second level),
/// and each division's teams are Volume-wrapped Volume-aware dictionaries
/// (third level), whose internal radix headers are also Volumes (fourth level).
private struct Company: Node, Sendable {
    var divisions: [String: VolumeImpl<Division>]

    init(divisions: [String: VolumeImpl<Division>] = [:]) {
        self.divisions = divisions
    }

    func properties() -> Set<String> { Set(divisions.keys) }
    func get(property: String) -> (any Header)? { divisions[property] }
    func set(properties: [String: any Header]) -> Company {
        var copy = self
        for (k, v) in properties {
            if let vol = v as? VolumeImpl<Division> {
                copy.divisions[k] = vol
            }
        }
        return copy
    }
}

/// Exercises `provide()` across a four-level Volume hierarchy built from
/// arbitrary custom nodes — not just the `VolumeMerkleDictionary` shape. This
/// is the contract we rely on when state, blocks, transactions, and their
/// internal Merkle subtrees all carry their own Volume boundaries: every root
/// at every level must fire `provide` so the fetcher (and, on the storage side,
/// the worker) knows which Volume owns each subtree.
@Suite("Multi-level Volume hierarchy with custom nodes")
struct MultiLevelVolumeTests {

    typealias Dict = VolumeMerkleDictionaryImpl<String>
    typealias DictVolume = VolumeImpl<Dict>

    private static func team(_ kvs: (String, String)...) throws -> DictVolume {
        var dict = Dict()
        for (k, v) in kvs { dict = try dict.inserting(key: k, value: v) }
        return VolumeImpl(node: dict)
    }

    private static func sampleCompany() throws -> Company {
        let eng = Division(teams: [
            "backend":  try team(("alice", "lead"), ("bob", "senior")),
            "frontend": try team(("carol", "lead"), ("dave", "mid")),
        ])
        let design = Division(teams: [
            "brand": try team(("eve", "lead"), ("frank", "junior")),
        ])
        return Company(divisions: [
            "eng":    VolumeImpl(node: eng),
            "design": VolumeImpl(node: design),
        ])
    }

    @Test("provide() fires for the root Volume in a multi-level hierarchy")
    func provideFiresAtEveryLevel() async throws {
        let company = try Self.sampleCompany()
        let root = VolumeImpl(node: company)

        let fetcher = VolumeMerkleDictionaryTests.ProvideRecordingFetcher()
        try root.storeRecursively(storer: fetcher)

        // Strip the root to CID-only and resolve.
        let stripped = VolumeImpl<Company>(rawCID: root.rawCID, node: nil, encryptionInfo: nil)
        _ = try await stripped.resolveRecursive(fetcher: fetcher)

        // The root Volume must fire provide() so all data can be fetched.
        let provided = Set(fetcher.providedRoots)
        #expect(provided.contains(root.rawCID),
                "root Volume must call provide() — fetcher saw: \(provided)")
    }

    @Test("Nested Volume roots each get exactly one provide() call per resolve")
    func oneProvidePerBoundaryPerResolve() async throws {
        // A pinned Volume should be announced exactly once when its subtree is
        // resolved — duplicate provide() calls would inflate per-peer traffic
        // and double-count Volume visits in storage workers trying to group
        // contiguous writes by root.
        let company = try Self.sampleCompany()
        let root = VolumeImpl(node: company)

        let fetcher = VolumeMerkleDictionaryTests.ProvideRecordingFetcher()
        try root.storeRecursively(storer: fetcher)

        let stripped = VolumeImpl<Company>(rawCID: root.rawCID, node: nil, encryptionInfo: nil)
        _ = try await stripped.resolveRecursive(fetcher: fetcher)

        var counts: [String: Int] = [:]
        for cid in fetcher.providedRoots { counts[cid, default: 0] += 1 }
        for (cid, count) in counts {
            #expect(count == 1, "expected exactly one provide() per Volume root, got \(count) for \(cid)")
        }
    }
}

// MARK: - Store → Fetch round-trip tests

/// A VolumeAwareStorer that groups CIDs by Volume boundary, mirroring
/// BrokerStorer's behavior. Each provide() seals the previous buffer
/// into a volume-keyed dict. fetch() serves from the volume store.
private final class VolumeGroupingStore: VolumeAwareStorer, @unchecked Sendable {
    private let lock = NSLock()
    private var activeRoot: String?
    private var buffer: [String: Data] = [:]
    private(set) var volumes: [String: [String: Data]] = [:]

    var providedRoots: [String] {
        lock.withLock { Array(volumes.keys) }
    }

    func enterVolume(rootCID: String) throws {
        lock.withLock {
            if let root = activeRoot, !buffer.isEmpty {
                volumes[root] = buffer
            }
            activeRoot = rootCID
            buffer = [:]
        }
    }

    func store(rawCid: String, data: Data) throws {
        lock.withLock { buffer[rawCid] = data }
    }

    func contains(rawCid: String) -> Bool { false }

    func seal() {
        lock.withLock {
            if let root = activeRoot, !buffer.isEmpty {
                volumes[root] = buffer
            }
            activeRoot = nil
            buffer = [:]
        }
    }

    func allData() -> [String: Data] {
        lock.withLock {
            var all: [String: Data] = [:]
            for (_, entries) in volumes { for (k, v) in entries { all[k] = v } }
            return all
        }
    }
}

/// Fetcher that serves from a VolumeGroupingStore and records provide() calls.
private final class VolumeGroupingFetcher: VolumeAwareFetcher, @unchecked Sendable {
    private let store: VolumeGroupingStore
    private let lock = NSLock()
    private var cache: [String: Data] = [:]
    private(set) var providedRoots: [String] = []

    init(store: VolumeGroupingStore) { self.store = store }

    func enterVolume(rootCID: String, paths: ArrayTrie<ResolutionStrategy>) async throws {
        lock.withLock {
            providedRoots.append(rootCID)
            if let entries = store.volumes[rootCID] {
                for (k, v) in entries { cache[k] = v }
            }
        }
    }

    func fetch(rawCid: String) async throws -> Data {
        if let data = lock.withLock({ cache[rawCid] }) { return data }
        let all = store.allData()
        if let data = all[rawCid] { return data }
        throw FetchError.notFound
    }
}

@Suite("Store → Fetch round-trip")
struct VolumeRoundTripTests {

    typealias Dict = VolumeMerkleDictionaryImpl<String>

    @Test("Store and resolve a single-key dictionary round-trips correctly")
    func singleKeyRoundTrip() async throws {
        let dict = try Dict().inserting(key: "alice", value: "v1")
        let outer = VolumeImpl(node: dict)

        let store = VolumeGroupingStore()
        try outer.storeRecursively(storer: store)
        store.seal()

        #expect(!store.volumes.isEmpty, "storeRecursively should produce at least one volume")
        #expect(store.volumes[outer.rawCID] != nil, "outer Volume root should have its own volume group")

        let stripped = VolumeImpl<Dict>(rawCID: outer.rawCID, node: nil, encryptionInfo: nil)
        let fetcher = VolumeGroupingFetcher(store: store)
        let resolved = try await stripped.resolveRecursive(fetcher: fetcher)

        #expect(resolved.node != nil, "resolved node should not be nil")
        let value = try resolved.node?.get(key: "alice")
        #expect(value == "v1", "round-tripped value should match")
    }

    @Test("Store and resolve a branched dictionary round-trips all values")
    func branchedRoundTrip() async throws {
        let dict = try Dict()
            .inserting(key: "alice", value: "v1")
            .inserting(key: "alicia", value: "v2")
            .inserting(key: "bob", value: "v3")
        let outer = VolumeImpl(node: dict)

        let store = VolumeGroupingStore()
        try outer.storeRecursively(storer: store)
        store.seal()

        #expect(store.volumes.count >= 2, "branched trie should produce multiple volume groups")

        let stripped = VolumeImpl<Dict>(rawCID: outer.rawCID, node: nil, encryptionInfo: nil)
        let fetcher = VolumeGroupingFetcher(store: store)
        let resolved = try await stripped.resolveRecursive(fetcher: fetcher)

        #expect(try resolved.node?.get(key: "alice") == "v1")
        #expect(try resolved.node?.get(key: "alicia") == "v2")
        #expect(try resolved.node?.get(key: "bob") == "v3")
    }

    @Test("Store fires provide() at every Volume boundary during storeRecursively")
    func storeFiresProvideAtBoundaries() throws {
        let dict = try Dict()
            .inserting(key: "alice", value: "v1")
            .inserting(key: "bob", value: "v2")
        let outer = VolumeImpl(node: dict)

        let store = VolumeGroupingStore()
        try outer.storeRecursively(storer: store)
        store.seal()

        #expect(store.volumes[outer.rawCID] != nil,
                "provide() should fire for the outer Volume root during store")

        var headerCIDs: Set<String> = []
        try VolumeMerkleDictionaryTests.visitAllHeaders(in: dict) { header in
            headerCIDs.insert(header.rawCID)
        }
        for cid in headerCIDs {
            #expect(store.volumes[cid] != nil,
                    "provide() should fire for internal header CID \(cid) during store")
        }
    }

    @Test("Non-Volume children are stored inside enclosing Volume's group, not lost")
    func nonVolumeChildrenInEnclosingVolume() throws {
        // MixedNode has both a HeaderImpl child (plain) and a VolumeImpl child.
        // With Set iteration, the Volume child might be visited first, sealing
        // the parent's buffer before the HeaderImpl child is stored.
        // The fix in Node+store.swift stores non-Volume children first.
        let store = VolumeGroupingStore()
        let labelDict = try VolumeMerkleDictionaryImpl<String>().inserting(key: "name", value: "test")
        let dataDict = VolumeMerkleDictionaryImpl<String>()
        let mixed = MixedNode(
            label: HeaderImpl(node: labelDict),
            data: VolumeImpl(node: dataDict)
        )
        let root = VolumeImpl(node: mixed)
        try root.storeRecursively(storer: store)
        store.seal()

        let rootVolume = store.volumes[root.rawCID]
        #expect(rootVolume != nil, "root volume should exist")

        let labelCID = mixed.label.rawCID
        #expect(rootVolume?[labelCID] != nil,
                "HeaderImpl child (label) must be stored inside the enclosing Volume's group, not lost when a sibling Volume boundary seals the buffer first")
    }

    @Test("Every VolumeRadixHeader in a VolumeMerkleDictionary gets its own volume root")
    func radixHeadersAreVolumeRoots() throws {
        let dict = try VolumeMerkleDictionaryImpl<String>()
            .inserting(key: "alice", value: "100")
            .inserting(key: "bob", value: "200")

        let outer = VolumeImpl(node: dict)
        let store = VolumeGroupingStore()
        try outer.storeRecursively(storer: store)
        store.seal()

        #expect(store.volumes[outer.rawCID] != nil, "outer VolumeImpl must be a volume root")

        var allHeaderCIDs: Set<String> = []
        try VolumeMerkleDictionaryTests.visitAllHeaders(in: dict) { header in
            allHeaderCIDs.insert(header.rawCID)
        }

        for cid in allHeaderCIDs {
            #expect(store.volumes[cid] != nil,
                    "VolumeRadixHeader \(String(cid.prefix(16)))… must have its own volume root — missing means provide() never fired during store")
        }
    }

    @Test("4-level custom hierarchy round-trips through volume-grouped store")
    func multiLevelRoundTrip() async throws {
        let eng = Division(teams: [
            "backend": VolumeImpl(node: try Dict()
                .inserting(key: "alice", value: "lead")
                .inserting(key: "bob", value: "senior")),
        ])
        let company = Company(divisions: [
            "eng": VolumeImpl(node: eng),
        ])
        let root = VolumeImpl(node: company)

        let store = VolumeGroupingStore()
        try root.storeRecursively(storer: store)
        store.seal()

        #expect(store.volumes.count >= 3, "4-level hierarchy should produce multiple volume groups")

        let stripped = VolumeImpl<Company>(rawCID: root.rawCID, node: nil, encryptionInfo: nil)
        let fetcher = VolumeGroupingFetcher(store: store)
        let resolved = try await stripped.resolveRecursive(fetcher: fetcher)

        let engDiv = resolved.node?.divisions["eng"]
        #expect(engDiv != nil, "eng division should resolve")
        let backend = engDiv?.node?.teams["backend"]
        #expect(backend != nil, "backend team should resolve")
        let alice = try backend?.node?.get(key: "alice")
        #expect(alice == "lead", "alice's value should round-trip correctly")
    }
}

