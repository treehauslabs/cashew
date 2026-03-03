import Testing
import Foundation
import ArrayTrie
import Crypto
@testable import cashew

// MARK: - User Profile Store

@Suite("Real-World: User Profile Store")
struct UserProfileStoreTests {

    typealias ProfileDict = MerkleDictionaryImpl<String>
    typealias UserStore = MerkleDictionaryImpl<HeaderImpl<ProfileDict>>

    private func makeProfile(name: String, email: String, role: String) throws -> ProfileDict {
        try ProfileDict()
            .inserting(key: "name", value: name)
            .inserting(key: "email", value: email)
            .inserting(key: "role", value: role)
    }

    @Test("Full user lifecycle: insert, query, update, delete")
    func testUserLifecycle() throws {
        let alice = try makeProfile(name: "Alice", email: "alice@co.com", role: "engineer")
        let bob = try makeProfile(name: "Bob", email: "bob@co.com", role: "designer")
        let charlie = try makeProfile(name: "Charlie", email: "charlie@co.com", role: "manager")

        var store = try UserStore()
            .inserting(key: "u001", value: HeaderImpl(node: alice))
            .inserting(key: "u002", value: HeaderImpl(node: bob))
            .inserting(key: "u003", value: HeaderImpl(node: charlie))
        #expect(store.count == 3)

        let bobProfile = try store.get(key: "u002")!.node!
        #expect(try bobProfile.get(key: "name") == "Bob")
        #expect(try bobProfile.get(key: "role") == "designer")

        let updatedBob = try makeProfile(name: "Bob", email: "bob@co.com", role: "lead designer")
        store = try store.mutating(key: "u002", value: HeaderImpl(node: updatedBob))
        #expect(try store.get(key: "u002")!.node!.get(key: "role") == "lead designer")

        store = try store.deleting(key: "u003")
        #expect(store.count == 2)
        #expect(try store.allKeys() == Set(["u001", "u002"]))

        let allUsers = try store.allKeysAndValues()
        #expect(allUsers.count == 2)
        #expect(allUsers["u001"] != nil)
        #expect(allUsers["u002"] != nil)
    }

    @Test("Structural sharing: unchanged users keep the same CID across versions")
    func testStructuralSharing() throws {
        let alice = try makeProfile(name: "Alice", email: "alice@co.com", role: "engineer")
        let bob = try makeProfile(name: "Bob", email: "bob@co.com", role: "designer")

        let v1 = try UserStore()
            .inserting(key: "u001", value: HeaderImpl(node: alice))
            .inserting(key: "u002", value: HeaderImpl(node: bob))

        let charlie = try makeProfile(name: "Charlie", email: "charlie@co.com", role: "manager")
        let v2 = try v1.inserting(key: "u003", value: HeaderImpl(node: charlie))

        let aliceCIDv1 = try v1.get(key: "u001")!.rawCID
        let aliceCIDv2 = try v2.get(key: "u001")!.rawCID
        #expect(aliceCIDv1 == aliceCIDv2)

        let bobCIDv1 = try v1.get(key: "u002")!.rawCID
        let bobCIDv2 = try v2.get(key: "u002")!.rawCID
        #expect(bobCIDv1 == bobCIDv2)

        let v1Header = HeaderImpl(node: v1)
        let v2Header = HeaderImpl(node: v2)
        #expect(v1Header.rawCID != v2Header.rawCID)
    }

    @Test("Store and resolve user profiles from CID-only references")
    func testStoreAndResolveProfiles() async throws {
        let alice = try makeProfile(name: "Alice", email: "alice@co.com", role: "engineer")
        let bob = try makeProfile(name: "Bob", email: "bob@co.com", role: "designer")

        let store = try UserStore()
            .inserting(key: "u001", value: HeaderImpl(node: alice))
            .inserting(key: "u002", value: HeaderImpl(node: bob))

        let header = HeaderImpl(node: store)
        let fetcher = TestStoreFetcher()
        try header.storeRecursively(storer: fetcher)

        let resolved = try await HeaderImpl<UserStore>(rawCID: header.rawCID)
            .resolveRecursive(fetcher: fetcher)

        #expect(resolved.rawCID == header.rawCID)
        #expect(try resolved.node!.get(key: "u001")!.node!.get(key: "name") == "Alice")
        #expect(try resolved.node!.get(key: "u002")!.node!.get(key: "email") == "bob@co.com")
    }
}

// MARK: - Version-Controlled Configuration

@Suite("Real-World: Version-Controlled Configuration")
struct VersionedConfigTests {

    typealias Config = MerkleDictionaryImpl<String>

    @Test("Configuration versioning with rollback to previous state")
    func testConfigVersioningAndRollback() async throws {
        let v1 = try Config()
            .inserting(key: "debug", value: "false")
            .inserting(key: "timeout", value: "30")
            .inserting(key: "region", value: "us-east-1")
        let v1Header = HeaderImpl(node: v1)

        var transforms = ArrayTrie<Transform>()
        transforms.set(["timeout"], value: .update("60"))
        transforms.set(["retries"], value: .insert("3"))
        let v2 = try v1.transform(transforms: transforms)!
        let v2Header = HeaderImpl(node: v2)

        transforms = ArrayTrie<Transform>()
        transforms.set(["debug"], value: .delete)
        let v3 = try v2.transform(transforms: transforms)!
        let v3Header = HeaderImpl(node: v3)

        #expect(v1Header.rawCID != v2Header.rawCID)
        #expect(v2Header.rawCID != v3Header.rawCID)

        let fetcher = TestStoreFetcher()
        try v1Header.storeRecursively(storer: fetcher)
        try v2Header.storeRecursively(storer: fetcher)
        try v3Header.storeRecursively(storer: fetcher)

        let rolledBack = try await HeaderImpl<Config>(rawCID: v1Header.rawCID)
            .resolveRecursive(fetcher: fetcher)
        #expect(try rolledBack.node!.get(key: "timeout") == "30")
        #expect(try rolledBack.node!.get(key: "debug") == "false")

        let current = try await HeaderImpl<Config>(rawCID: v3Header.rawCID)
            .resolveRecursive(fetcher: fetcher)
        #expect(try current.node!.get(key: "timeout") == "60")
        #expect(try current.node!.get(key: "retries") == "3")
        #expect(try current.node!.get(key: "debug") == nil)
    }

    @Test("Unchanged config branches share CIDs across versions")
    func testConfigStructuralSharing() throws {
        let v1 = try Config()
            .inserting(key: "region", value: "us-east-1")
            .inserting(key: "timeout", value: "30")
            .inserting(key: "debug", value: "false")

        var transforms = ArrayTrie<Transform>()
        transforms.set(["timeout"], value: .update("60"))
        let v2 = try v1.transform(transforms: transforms)!

        let regionCIDv1 = v1.children["r"]!.rawCID
        let regionCIDv2 = v2.children["r"]!.rawCID
        #expect(regionCIDv1 == regionCIDv2)

        let debugCIDv1 = v1.children["d"]!.rawCID
        let debugCIDv2 = v2.children["d"]!.rawCID
        #expect(debugCIDv1 == debugCIDv2)

        let timeoutCIDv1 = v1.children["t"]!.rawCID
        let timeoutCIDv2 = v2.children["t"]!.rawCID
        #expect(timeoutCIDv1 != timeoutCIDv2)
    }

    @Test("Batch config update via transform preserves count")
    func testBatchConfigUpdate() throws {
        var config = try Config()
            .inserting(key: "feature_a", value: "enabled")
            .inserting(key: "feature_b", value: "disabled")
            .inserting(key: "max_connections", value: "100")
        #expect(config.count == 3)

        var transforms = ArrayTrie<Transform>()
        transforms.set(["feature_b"], value: .update("enabled"))
        transforms.set(["feature_c"], value: .insert("enabled"))
        transforms.set(["max_connections"], value: .update("200"))
        config = try config.transform(transforms: transforms)!

        #expect(config.count == 4)
        #expect(try config.get(key: "feature_b") == "enabled")
        #expect(try config.get(key: "feature_c") == "enabled")
        #expect(try config.get(key: "max_connections") == "200")
        #expect(try config.get(key: "feature_a") == "enabled")
    }
}

// MARK: - Access-Controlled Records with Selective Encryption

@Suite("Real-World: Selective Encryption for Access Control")
struct SelectiveEncryptionTests {

    typealias RecordDict = MerkleDictionaryImpl<HeaderImpl<TestScalar>>

    @Test("Public fields accessible, private fields encrypted")
    func testSelectiveFieldEncryption() throws {
        let patientKey = SymmetricKey(size: .bits256)

        var record = RecordDict(children: [:], count: 0)
        record = try record.inserting(key: "patient_id", value: HeaderImpl(node: TestScalar(val: 12345)))
        record = try record.inserting(key: "name", value: HeaderImpl(node: TestScalar(val: 1)))
        record = try record.inserting(key: "ssn", value: HeaderImpl(node: TestScalar(val: 999)))
        record = try record.inserting(key: "diagnosis", value: HeaderImpl(node: TestScalar(val: 42)))

        let header = HeaderImpl(node: record)

        var encryption = ArrayTrie<EncryptionStrategy>()
        encryption.set(["ssn"], value: .targeted(patientKey))
        encryption.set(["diagnosis"], value: .targeted(patientKey))
        let encrypted = try header.encrypt(encryption: encryption)

        let encNode = encrypted.node!
        let publicId = try encNode.get(key: "patient_id")!
        #expect(publicId.encryptionInfo == nil)
        let nameVal = try encNode.get(key: "name")!
        #expect(nameVal.encryptionInfo == nil)

        let ssnVal = try encNode.get(key: "ssn")!
        #expect(ssnVal.encryptionInfo != nil)
        let diagVal = try encNode.get(key: "diagnosis")!
        #expect(diagVal.encryptionInfo != nil)
    }

    @Test("Authorized resolver can read encrypted fields after store/resolve")
    func testAuthorizedAccess() async throws {
        let patientKey = SymmetricKey(size: .bits256)
        let fetcher = TestKeyProvidingStoreFetcher()
        fetcher.registerKey(patientKey)

        var record = MerkleDictionaryImpl<HeaderImpl<TestScalar>>(children: [:], count: 0)
        record = try record.inserting(key: "public_id", value: HeaderImpl(node: TestScalar(val: 100)))
        record = try record.inserting(key: "secret_score", value: HeaderImpl(node: TestScalar(val: 42)))
        let header = HeaderImpl(node: record)

        var encryption = ArrayTrie<EncryptionStrategy>()
        encryption.set(["secret_score"], value: .targeted(patientKey))
        let encrypted = try header.encrypt(encryption: encryption)

        try encrypted.storeRecursively(storer: fetcher)

        let resolved = try await encrypted.removingNode().resolveRecursive(fetcher: fetcher)
        let publicVal = try resolved.node!.get(key: "public_id")!
        let publicResolved = try await publicVal.resolve(fetcher: fetcher)
        #expect(publicResolved.node!.val == 100)

        let secretVal = try resolved.node!.get(key: "secret_score")!
        let secretResolved = try await secretVal.resolve(fetcher: fetcher)
        #expect(secretResolved.node!.val == 42)
    }

    @Test("Unauthorized resolver cannot read encrypted fields")
    func testUnauthorizedAccess() async throws {
        let patientKey = SymmetricKey(size: .bits256)
        let authorizedFetcher = TestKeyProvidingStoreFetcher()
        authorizedFetcher.registerKey(patientKey)

        var record = MerkleDictionaryImpl<HeaderImpl<TestScalar>>(children: [:], count: 0)
        record = try record.inserting(key: "public_id", value: HeaderImpl(node: TestScalar(val: 100)))
        record = try record.inserting(key: "secret_score", value: HeaderImpl(node: TestScalar(val: 42)))
        let header = HeaderImpl(node: record)

        var encryption = ArrayTrie<EncryptionStrategy>()
        encryption.set(["secret_score"], value: .targeted(patientKey))
        let encrypted = try header.encrypt(encryption: encryption)
        try encrypted.storeRecursively(storer: authorizedFetcher)

        let unauthorizedFetcher = TestStoreFetcher()
        let encryptedSecretVal = try encrypted.node!.get(key: "secret_score")!
        let cidOnly = HeaderImpl<TestScalar>(rawCID: encryptedSecretVal.rawCID, node: nil, encryptionInfo: encryptedSecretVal.encryptionInfo)

        await #expect(throws: (any Error).self) {
            _ = try await cidOnly.resolve(fetcher: unauthorizedFetcher)
        }
    }

    @Test("Multi-tenant encryption: each tenant's data encrypted with separate key")
    func testMultiTenantIsolation() throws {
        let tenantAKey = SymmetricKey(size: .bits256)
        let tenantBKey = SymmetricKey(size: .bits256)

        typealias TenantStore = MerkleDictionaryImpl<HeaderImpl<TestScalar>>

        var store = TenantStore(children: [:], count: 0)
        store = try store.inserting(key: "tenant_a_data", value: HeaderImpl(node: TestScalar(val: 1)))
        store = try store.inserting(key: "tenant_b_data", value: HeaderImpl(node: TestScalar(val: 2)))
        let header = HeaderImpl(node: store)

        var encryption = ArrayTrie<EncryptionStrategy>()
        encryption.set(["tenant_a_data"], value: .targeted(tenantAKey))
        encryption.set(["tenant_b_data"], value: .targeted(tenantBKey))
        let encrypted = try header.encrypt(encryption: encryption)

        let aVal = try encrypted.node!.get(key: "tenant_a_data")!
        let bVal = try encrypted.node!.get(key: "tenant_b_data")!
        #expect(aVal.encryptionInfo != nil)
        #expect(bVal.encryptionInfo != nil)
        #expect(aVal.encryptionInfo!.keyHash != bVal.encryptionInfo!.keyHash)
    }
}

// MARK: - Lazy-Loading Product Catalog

@Suite("Real-World: Lazy-Loading Product Catalog")
struct LazyCatalogTests {

    typealias Product = MerkleDictionaryImpl<String>
    typealias Category = MerkleDictionaryImpl<HeaderImpl<Product>>
    typealias Catalog = MerkleDictionaryImpl<HeaderImpl<Category>>

    private func buildCatalog() throws -> (Catalog, HeaderImpl<Catalog>) {
        let laptop = try Product()
            .inserting(key: "name", value: "Laptop Pro")
            .inserting(key: "price", value: "999")
            .inserting(key: "sku", value: "ELEC-001")
        let phone = try Product()
            .inserting(key: "name", value: "SmartPhone X")
            .inserting(key: "price", value: "699")
            .inserting(key: "sku", value: "ELEC-002")
        let novel = try Product()
            .inserting(key: "name", value: "The Great Novel")
            .inserting(key: "price", value: "15")
            .inserting(key: "sku", value: "BOOK-001")
        let textbook = try Product()
            .inserting(key: "name", value: "Algorithms 101")
            .inserting(key: "price", value: "85")
            .inserting(key: "sku", value: "BOOK-002")

        let electronics = try Category()
            .inserting(key: "laptop", value: HeaderImpl(node: laptop))
            .inserting(key: "phone", value: HeaderImpl(node: phone))
        let books = try Category()
            .inserting(key: "novel", value: HeaderImpl(node: novel))
            .inserting(key: "textbook", value: HeaderImpl(node: textbook))

        let catalog = try Catalog()
            .inserting(key: "electronics", value: HeaderImpl(node: electronics))
            .inserting(key: "books", value: HeaderImpl(node: books))

        return (catalog, HeaderImpl(node: catalog))
    }

    @Test("List resolution enumerates keys but values remain CID-only")
    func testListResolution() async throws {
        let (_, catalogHeader) = try buildCatalog()
        let fetcher = TestStoreFetcher()
        try catalogHeader.storeRecursively(storer: fetcher)

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set([""], value: .list)
        let resolved = try await HeaderImpl<Catalog>(rawCID: catalogHeader.rawCID)
            .resolve(paths: paths, fetcher: fetcher)

        let keys = try resolved.node!.allKeys()
        #expect(keys.contains("electronics"))
        #expect(keys.contains("books"))

        let electronicsHeader = try resolved.node!.get(key: "electronics")!
        #expect(electronicsHeader.node == nil)
    }

    @Test("Targeted resolution loads only the specified category")
    func testTargetedResolution() async throws {
        let (_, catalogHeader) = try buildCatalog()
        let fetcher = TestStoreFetcher()
        try catalogHeader.storeRecursively(storer: fetcher)

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set(["electronics"], value: .targeted)
        let resolved = try await HeaderImpl<Catalog>(rawCID: catalogHeader.rawCID)
            .resolve(paths: paths, fetcher: fetcher)

        let electronicsHeader = try resolved.node!.get(key: "electronics")!
        #expect(electronicsHeader.node != nil)

        let booksRawHeader = resolved.node!.children[Character("b")]
        #expect(booksRawHeader?.node == nil)
    }

    @Test("Recursive resolution loads entire subtree")
    func testRecursiveResolution() async throws {
        let (_, catalogHeader) = try buildCatalog()
        let fetcher = TestStoreFetcher()
        try catalogHeader.storeRecursively(storer: fetcher)

        var paths = ArrayTrie<ResolutionStrategy>()
        paths.set(["electronics"], value: .recursive)
        let resolved = try await HeaderImpl<Catalog>(rawCID: catalogHeader.rawCID)
            .resolve(paths: paths, fetcher: fetcher)

        let electronicsHeader = try resolved.node!.get(key: "electronics")!
        #expect(electronicsHeader.node != nil)

        let laptopHeader = try electronicsHeader.node!.get(key: "laptop")!
        #expect(laptopHeader.node != nil)
        #expect(try laptopHeader.node!.get(key: "name") == "Laptop Pro")
        #expect(try laptopHeader.node!.get(key: "price") == "999")

        let phoneHeader = try electronicsHeader.node!.get(key: "phone")!
        #expect(phoneHeader.node != nil)
        #expect(try phoneHeader.node!.get(key: "name") == "SmartPhone X")

        let booksRawHeader = resolved.node!.children[Character("b")]
        #expect(booksRawHeader?.node == nil)
    }

    @Test("Incremental resolution: list first, then targeted drill-down")
    func testIncrementalResolution() async throws {
        let (_, catalogHeader) = try buildCatalog()
        let fetcher = TestStoreFetcher()
        try catalogHeader.storeRecursively(storer: fetcher)

        var listPaths = ArrayTrie<ResolutionStrategy>()
        listPaths.set([""], value: .list)
        let listed = try await HeaderImpl<Catalog>(rawCID: catalogHeader.rawCID)
            .resolve(paths: listPaths, fetcher: fetcher)

        let keys = try listed.node!.allKeys()
        #expect(keys.contains("books"))
        let booksHeader = try listed.node!.get(key: "books")!
        #expect(booksHeader.node == nil)

        let booksResolved = try await booksHeader.resolveRecursive(fetcher: fetcher)
        let novelResolved = try booksResolved.node!.get(key: "novel")!
        #expect(novelResolved.node != nil)
        #expect(try novelResolved.node!.get(key: "name") == "The Great Novel")
    }
}

// MARK: - Audit Trail with Merkle Proofs

@Suite("Real-World: Audit Trail with Merkle Proofs")
struct AuditTrailTests {

    typealias Ledger = MerkleDictionaryImpl<String>

    private func buildLedger(count: Int) throws -> Ledger {
        var ledger = Ledger()
        for i in 1...count {
            let txID = String(format: "tx%03d", i)
            ledger = try ledger.inserting(key: txID, value: "\(i * 100)")
        }
        return ledger
    }

    @Test("Existence proof for a specific transaction is minimal")
    func testExistenceProofIsMinimal() async throws {
        var ledger = Ledger()
        ledger = try ledger.inserting(key: "alpha_tx", value: "100")
        ledger = try ledger.inserting(key: "beta_tx", value: "200")
        ledger = try ledger.inserting(key: "gamma_tx", value: "300")
        ledger = try ledger.inserting(key: "delta_tx", value: "400")
        let header = HeaderImpl(node: ledger)
        let fetcher = TestStoreFetcher()
        try header.storeRecursively(storer: fetcher)

        let cidOnly = HeaderImpl<Ledger>(rawCID: header.rawCID)
        var proofPaths = ArrayTrie<SparseMerkleProof>()
        proofPaths.set(["alpha_tx"], value: .existence)
        let proof = try await cidOnly.proof(paths: proofPaths, fetcher: fetcher)

        #expect(proof.rawCID == header.rawCID)

        let proofNode = proof.node!
        let alphaVal = try proofNode.get(key: "alpha_tx")
        #expect(alphaVal == "100")

        let aHeader = proofNode.children[Character("a")]
        #expect(aHeader?.node != nil)
        let bHeader = proofNode.children[Character("b")]
        #expect(bHeader?.node == nil)
        let gHeader = proofNode.children[Character("g")]
        #expect(gHeader?.node == nil)
    }

    @Test("Insertion proof confirms key does not yet exist")
    func testInsertionProof() async throws {
        let ledger = try buildLedger(count: 5)
        let header = HeaderImpl(node: ledger)
        let fetcher = TestStoreFetcher()
        try header.storeRecursively(storer: fetcher)

        var proofPaths = ArrayTrie<SparseMerkleProof>()
        proofPaths.set(["tx999"], value: .insertion)
        let proof = try await header.proof(paths: proofPaths, fetcher: fetcher)
        #expect(proof.rawCID == header.rawCID)
    }

    @Test("Historical audit: prove transaction existed in an older version")
    func testHistoricalVersionProof() async throws {
        let v1 = try buildLedger(count: 10)
        let v1Header = HeaderImpl(node: v1)
        let fetcher = TestStoreFetcher()
        try v1Header.storeRecursively(storer: fetcher)

        var transforms = ArrayTrie<Transform>()
        transforms.set(["tx011"], value: .insert("1100"))
        transforms.set(["tx012"], value: .insert("1200"))
        let v2 = try v1.transform(transforms: transforms)!
        let v2Header = HeaderImpl(node: v2)
        try v2Header.storeRecursively(storer: fetcher)

        #expect(v1Header.rawCID != v2Header.rawCID)

        let resolvedV1 = try await HeaderImpl<Ledger>(rawCID: v1Header.rawCID)
            .resolveRecursive(fetcher: fetcher)

        var proofPaths = ArrayTrie<SparseMerkleProof>()
        proofPaths.set(["tx005"], value: .existence)
        let proof = try await resolvedV1.proof(paths: proofPaths, fetcher: fetcher)
        #expect(proof.rawCID == v1Header.rawCID)
        #expect(try proof.node!.get(key: "tx005") == "500")
    }

    @Test("Deletion proof for removing a transaction")
    func testDeletionProof() async throws {
        let ledger = try buildLedger(count: 5)
        let header = HeaderImpl(node: ledger)
        let fetcher = TestStoreFetcher()
        try header.storeRecursively(storer: fetcher)

        var proofPaths = ArrayTrie<SparseMerkleProof>()
        proofPaths.set(["tx003"], value: .deletion)
        let proof = try await header.proof(paths: proofPaths, fetcher: fetcher)

        #expect(proof.rawCID == header.rawCID)
        #expect(try proof.node!.get(key: "tx003") == "300")
    }

    @Test("Proof preserves root CID integrity")
    func testProofPreservesRootCID() async throws {
        let ledger = try buildLedger(count: 20)
        let header = HeaderImpl(node: ledger)
        let fetcher = TestStoreFetcher()
        try header.storeRecursively(storer: fetcher)

        var proofPaths = ArrayTrie<SparseMerkleProof>()
        proofPaths.set(["tx010"], value: .existence)
        proofPaths.set(["tx015"], value: .mutation)
        let proof = try await header.proof(paths: proofPaths, fetcher: fetcher)

        #expect(proof.rawCID == header.rawCID)
        #expect(try proof.node!.get(key: "tx010") == "1000")
        #expect(try proof.node!.get(key: "tx015") == "1500")
    }
}
