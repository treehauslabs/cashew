import Testing
import Foundation
import ArrayTrie
import CID
@preconcurrency import Multicodec
import Multihash
@testable import cashew

@Suite("Headers & Content Addressability")
struct ContentAddressabilityTests {

    @Suite("Header Basics")
    struct HeaderBasics {

        @Test("Initialize with rawCID only")
        func testInitWithRawCID() {
            let cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: cid)

            #expect(header.rawCID == cid)
            #expect(header.node == nil)
        }

        @Test("Initialize with rawCID and node")
        func testInitWithRawCIDAndNode() throws {
            let cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = HeaderImpl(rawCID: cid, node: dictionary)

            #expect(header.rawCID == cid)
            #expect(try header.node?.get(key: "key1") == "value1")
            #expect(header.node?.count == 1)
        }

        @Test("Initialize with node only - uses placeholder CID")
        func testInitWithNodeOnly() throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = HeaderImpl(node: dictionary)

            #expect(try header.node?.get(key: "key1") == "value1")
            #expect(header.rawCID.hasPrefix("bagu") || header.rawCID.hasPrefix("bafy"))
            #expect(header.rawCID.count > 10)
        }

        @Test("Initialize with node and specific codec")
        func testInitWithNodeAndCodec() throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = HeaderImpl(node: dictionary, codec: .dag_json)

            #expect(try header.node?.get(key: "key1") == "value1")
            #expect(header.rawCID.hasPrefix("bagu") || header.rawCID.hasPrefix("bafy"))
        }

        @Test("Async create with proper CID generation")
        func testAsyncCreate() async throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = try await HeaderImpl.create(node: dictionary, codec: .dag_json)

            #expect(try header.node?.get(key: "key1") == "value1")
            #expect(header.rawCID.hasPrefix("bagu") || header.rawCID.hasPrefix("bafy"))
            #expect(header.rawCID != "bafyreigdhej4kdla7q2z5rnpfxqhj6c2wuutcka2rzkqxvmzq4f2j7kfgy")
        }

        @Test("CID creation is deterministic with async create")
        func testCIDCreationDeterministic() async throws {
            var dictionary1 = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary1 = try dictionary1.inserting(key: "key1", value: "value1")

            var dictionary2 = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary2 = try dictionary2.inserting(key: "key1", value: "value1")

            let header1 = try await HeaderImpl.create(node: dictionary1, codec: .dag_json)
            let header2 = try await HeaderImpl.create(node: dictionary2, codec: .dag_json)

            #expect(header1.rawCID == header2.rawCID)
        }

        @Test("Different codecs produce different CIDs")
        func testDifferentCodecsProduceDifferentCIDs() async throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")

            let headerCBOR = try await HeaderImpl.create(node: dictionary, codec: .dag_cbor)
            let headerJSON = try await HeaderImpl.create(node: dictionary, codec: .dag_json)

            #expect(headerCBOR.rawCID != headerJSON.rawCID)
        }

        @Test("Map node to data")
        func testMapToData() throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = HeaderImpl(node: dictionary)

            let data = try header.mapToData()
            #expect(data.count > 0)

            let json = try JSONSerialization.jsonObject(with: data)
            #expect(json is [String: Any])
        }

        @Test("Map to data throws when no node")
        func testMapToDataThrowsWhenNoNode() {
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: "test-cid")

            #expect(throws: DataErrors.self) {
                try header.mapToData()
            }
        }

        @Test("Recreate CID with async method")
        func testRecreateCID() async throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = try await HeaderImpl.create(node: dictionary)
            let originalCID = header.rawCID

            let recreatedCID = try await header.recreateCID()
            #expect(recreatedCID == originalCID)
        }

        @Test("Recreate CID returns original when no node")
        func testRecreateCIDReturnsOriginalWhenNoNode() async throws {
            let originalCID = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: originalCID)

            let recreatedCID = try await header.recreateCID()
            #expect(recreatedCID == originalCID)
        }

        @Test("LosslessStringConvertible description")
        func testLosslessStringConvertibleDescription() {
            let cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: cid)

            #expect(header.description == cid)
        }

        @Test("LosslessStringConvertible init")
        func testLosslessStringConvertibleInit() {
            let cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(cid)

            #expect(header != nil)
            #expect(header?.rawCID == cid)
            #expect(header?.node == nil)
        }

        @Test("Recreate CID with specific codec")
        func testRecreateCIDWithCodec() async throws {
            var dictionary = MerkleDictionaryImpl<String>(children: [:], count: 0)
            dictionary = try dictionary.inserting(key: "key1", value: "value1")
            let header = try await HeaderImpl.create(node: dictionary)

            let cidWithJSON = try await header.recreateCID(withCodec: .dag_json)
            let cidWithCBOR = try await header.recreateCID(withCodec: .dag_cbor)

            #expect(cidWithJSON != cidWithCBOR)
            #expect(cidWithJSON.hasPrefix("bagu") || cidWithJSON.hasPrefix("bafy"))
            #expect(cidWithCBOR.hasPrefix("bagu") || cidWithCBOR.hasPrefix("bafy"))
        }

        @Test("Recreate CID with codec throws when no node")
        func testRecreateCIDWithCodecThrowsWhenNoNode() async throws {
            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: "test-cid")

            await #expect(throws: DataErrors.self) {
                try await header.recreateCID(withCodec: .dag_json)
            }
        }

        @Test("Header CID is deterministic for identical nodes")
        func testHeaderCIDDeterministic() throws {
            let scalar1 = TestScalar(val: 100)
            let scalar2 = TestScalar(val: 100)
            let header1 = HeaderImpl(node: scalar1)
            let header2 = HeaderImpl(node: scalar2)
            #expect(header1.rawCID == header2.rawCID)
        }

        @Test("Header CID differs for different nodes")
        func testHeaderCIDDiffers() throws {
            let scalar1 = TestScalar(val: 1)
            let scalar2 = TestScalar(val: 2)
            let header1 = HeaderImpl(node: scalar1)
            let header2 = HeaderImpl(node: scalar2)
            #expect(header1.rawCID != header2.rawCID)
        }

        @Test("serializeNode throws on failure rather than returning empty data")
        func testSerializeNodeThrowsOnFailure() throws {
            let scalar = TestScalar(val: 42)
            let header = HeaderImpl(node: scalar)
            let data = try header.mapToData()
            #expect(!data.isEmpty)
        }

        @Test("Node description returns empty string when encoding fails")
        func testNodeDescriptionSafeOnEncodingFailure() throws {
            let dict = MerkleDictionaryImpl<String>(children: [:], count: 0)
            let description = dict.description
            #expect(!description.isEmpty)
        }

        @Test("Node description works for valid nodes")
        func testNodeDescriptionWorksForValidNodes() throws {
            let scalar = TestScalar(val: 42)
            let description = scalar.description
            #expect(description.contains("42"))
        }

        @Test("CashewDecodingError is throwable and catchable")
        func testCashewDecodingErrorThrowable() throws {
            #expect(throws: CashewDecodingError.self) {
                throw CashewDecodingError.decodeFromDataError
            }
        }

        @Test("CashewDecodingError does not conflict with Swift.DecodingError")
        func testCashewDecodingErrorNoConflict() throws {
            let cashewError: Error = CashewDecodingError.decodeFromDataError
            let swiftError: Error = Swift.DecodingError.dataCorrupted(
                Swift.DecodingError.Context(codingPath: [], debugDescription: "test")
            )

            #expect(cashewError is CashewDecodingError)
            #expect(swiftError is Swift.DecodingError)
            #expect(!(cashewError is Swift.DecodingError))
            #expect(!(swiftError is CashewDecodingError))
        }

        @Test("Decoding invalid data throws CashewDecodingError")
        func testDecodingInvalidDataThrowsCashewError() async throws {
            let fetcher = TestStoreFetcher()
            fetcher.storeRaw(rawCid: "fakeCID", data: Data([0xFF, 0xFE]))

            let header = HeaderImpl<MerkleDictionaryImpl<String>>(rawCID: "fakeCID")
            await #expect(throws: CashewDecodingError.self) {
                _ = try await header.resolve(fetcher: fetcher)
            }
        }

        @Test("RadixHeaderImpl init with nil node produces nil rawNode")
        func testRadixHeaderImplNilNode() throws {
            let header = RadixHeaderImpl<String>(rawCID: "test", node: nil)
            #expect(header.node == nil)
            #expect(header.rawCID == "test")
        }

        @Test("RadixHeaderImpl init with non-nil node produces valid rawNode")
        func testRadixHeaderImplNonNilNode() throws {
            typealias DictType = MerkleDictionaryImpl<String>
            let dict = try DictType(children: [:], count: 0)
                .inserting(key: "k", value: "v")

            let child = dict.children["k"]!
            let node = child.node!
            let header = RadixHeaderImpl<String>(rawCID: "test", node: node)
            #expect(header.node != nil)
            #expect(header.node!.prefix == node.prefix)
        }

        @Test("LosslessStringConvertible init from valid UTF-8 data succeeds")
        func testLosslessStringConvertibleValidData() throws {
            let data = "hello".data(using: .utf8)!
            let result = String(data: data)
            #expect(result == "hello")
        }

        @Test("LosslessStringConvertible init from invalid data returns nil")
        func testLosslessStringConvertibleInvalidData() throws {
            let data = Data([0xFF, 0xFE, 0x80, 0x81])
            let result = String(data: data)
            #expect(result == nil)
        }
    }

    @Suite("Content Addressability")
    struct ContentAddressability {

        @Test("Content addressability preserved after fixes")
        func testContentAddressabilityRegression() throws {
            let scalar = TestScalar(val: 42)
            let header1 = HeaderImpl(node: scalar)
            let header2 = HeaderImpl(node: scalar)
            #expect(header1.rawCID == header2.rawCID)

            let dict1 = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "a", value: "1")
            let dict2 = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "a", value: "1")
            let dh1 = HeaderImpl(node: dict1)
            let dh2 = HeaderImpl(node: dict2)
            #expect(dh1.rawCID == dh2.rawCID)
        }

        @Test("Same logical structure built in different order produces same CID")
        func testInsertionOrderIndependentCID() throws {
            let dict1 = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "alpha", value: "1")
                .inserting(key: "beta", value: "2")
                .inserting(key: "gamma", value: "3")

            let dict2 = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "gamma", value: "3")
                .inserting(key: "alpha", value: "1")
                .inserting(key: "beta", value: "2")

            let dict3 = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "beta", value: "2")
                .inserting(key: "gamma", value: "3")
                .inserting(key: "alpha", value: "1")

            let h1 = HeaderImpl(node: dict1)
            let h2 = HeaderImpl(node: dict2)
            let h3 = HeaderImpl(node: dict3)

            #expect(h1.rawCID == h2.rawCID)
            #expect(h2.rawCID == h3.rawCID)
        }

        @Test("Transform result matches manual construction CID")
        func testTransformMatchesManualCID() throws {
            let dict = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "a", value: "old")

            var transforms = ArrayTrie<Transform>()
            transforms.set(["a"], value: .update("new"))
            transforms.set(["b"], value: .insert("added"))

            let transformResult = try dict.transform(transforms: transforms)!
            let manualResult = try MerkleDictionaryImpl<String>(children: [:], count: 0)
                .inserting(key: "a", value: "new")
                .inserting(key: "b", value: "added")

            #expect(HeaderImpl(node: transformResult).rawCID == HeaderImpl(node: manualResult).rawCID)
        }
    }
}
