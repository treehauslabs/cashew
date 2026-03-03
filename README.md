# Cashew

A Swift library for building versioned, tamper-evident key-value stores where data can live anywhere and load on demand.

## Quick Example

```swift
import cashew

var dict = MerkleDictionaryImpl<String>()
dict = try dict.inserting(key: "alice", value: "engineer")
dict = try dict.inserting(key: "bob", value: "designer")

let header = HeaderImpl(node: dict)
print(header.rawCID) // "baguqeera..." — unique fingerprint of this exact data
```

Every version of the data gets a unique CID (Content Identifier) — a SHA2-256 hash of its deterministic JSON serialization. Same content always produces the same CID. Change anything and the CID changes.

## What Problem It Solves

Most key-value stores treat data as a mutable blob. Cashew treats data as an immutable, content-addressed Merkle radix trie — every "write" produces a new root with a new CID, while unchanged branches share structure with previous versions. This gives you three things traditional stores don't: **verifiable integrity** (the CID proves the data hasn't been tampered with), **lazy loading** (load only the branches you need from any content-addressable backend), and **efficient proofs** (prove a key exists or doesn't without revealing the entire dataset).

## Good Fit

- Content-addressable storage backends (IPFS, CAS databases)
- Versioned state where every mutation must be auditable
- Distributed systems that need tamper-evident data exchange
- Selective encryption — some fields public, some private, same data structure
- Sparse proofs — prove properties about specific keys without the full dataset

## Not a Fit

- High-throughput mutable key-value stores (Cashew is immutable; every write allocates)
- Data that doesn't need content addressing or integrity guarantees
- Simple in-memory caches where a `Dictionary` suffices

## Key Concepts

| Concept | What it means |
|---------|--------------|
| **CID** | Content Identifier — a hash of the data. Same data → same CID. |
| **Header** | A smart pointer holding a CID and optionally the data it refers to. `node == nil` means "unresolved" — you know the hash but haven't loaded the data yet. |
| **Resolve** | Fetch data from a store using its CID. Three strategies: `.targeted` (one node), `.recursive` (full subtree), `.list` (structure only). |
| **Transform** | Mutate the structure (insert/update/delete). Returns a new tree with new CIDs for changed nodes. |
| **Proof** | Generate a minimal subtree proving a key exists, doesn't exist, or can be modified. |
| **MerkleDictionary** | The top-level key-value map. Dispatches by first character to a compressed radix trie. |

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/treehauslabs/cashew.git", from: "1.0.0")
]
```

Requires macOS 12.0+ and Swift 6.0+.

## Usage

### Creating and Mutating a Dictionary

```swift
import cashew

var dict = MerkleDictionaryImpl<String>()

dict = try dict.inserting(key: "alice", value: "engineer")
dict = try dict.inserting(key: "bob", value: "designer")
dict = try dict.inserting(key: "alicia", value: "manager")

let value = try dict.get(key: "alice") // Optional("engineer")

dict = try dict.mutating(key: "bob", value: "lead designer")
dict = try dict.deleting(key: "alicia")

let keys: Set<String> = try dict.allKeys()
let pairs: [String: String] = try dict.allKeysAndValues()
```

### Content Addressability

Every structure has a deterministic CID derived from its content:

```swift
let node = RadixNodeImpl<String>(prefix: "hello", value: "world", children: [:])
let header = RadixHeaderImpl(node: node)
print(header.rawCID) // CIDv1 string, e.g. "baguqeera..."

let header2 = RadixHeaderImpl(node: node)
assert(header.rawCID == header2.rawCID) // same content → same CID
```

### Resolution (Lazy Loading)

Headers can exist as CID-only references. Resolution fetches the actual data using a pluggable `Fetcher`:

```swift
struct IPFSFetcher: Fetcher {
    func fetch(rawCid: String) async throws -> Data {
        // fetch from IPFS, a database, or any content-addressable store
    }
}

let fetcher = IPFSFetcher()

var paths = ArrayTrie<ResolutionStrategy>()
paths.set(["users", "a"], value: .targeted)  // fetch just this node
paths.set(["config"], value: .recursive)     // fetch entire subtree
paths.set(["posts"], value: .list)           // fetch structure only, values stay CID-only

let resolved = try await dictionary.resolve(paths: paths, fetcher: fetcher)
```

### Storage

Persist resolved data using a pluggable `Storer`:

```swift
struct MyStore: Storer {
    func store(rawCid: String, data: Data) throws {
        // write to disk, database, IPFS, etc.
    }
}

try header.storeRecursively(storer: MyStore())
```

### Transforms (Batch Mutations)

Apply multiple insert/update/delete operations in one pass:

```swift
var transforms = ArrayTrie<Transform>()
transforms.set(["alice"], value: .update("senior engineer"))
transforms.set(["charlie"], value: .insert("intern"))
transforms.set(["bob"], value: .delete)

let newDict = try dict.transform(transforms: transforms)
// newDict has the mutations applied; CIDs are recomputed
```

### Sparse Merkle Proofs

Generate minimal subtrees that prove specific properties about keys:

```swift
var proofPaths = ArrayTrie<SparseMerkleProof>()
proofPaths.set(["alice"], value: .existence)   // prove key exists
proofPaths.set(["dave"], value: .insertion)     // prove key doesn't exist (safe to insert)
proofPaths.set(["bob"], value: .mutation)       // prove key exists (can be updated)
proofPaths.set(["charlie"], value: .deletion)   // prove key exists with neighbors (can be deleted)

let proof = try await dictionary.proof(paths: proofPaths, fetcher: fetcher)
// proof contains only the nodes needed to verify these properties
```

### Nested Dictionaries

Values can themselves be `Header` types wrapping `MerkleDictionary`, enabling hierarchical structures:

```swift
typealias InnerDict = MerkleDictionaryImpl<String>
typealias OuterDict = MerkleDictionaryImpl<HeaderImpl<InnerDict>>

var outer = OuterDict()
let inner = try InnerDict()
    .inserting(key: "name", value: "Alice")
    .inserting(key: "role", value: "Engineer")
let innerHeader = HeaderImpl(node: inner)

outer = try outer.inserting(key: "user1", value: innerHeader)
```

Transforms on nested dictionaries propagate through both levels:

```swift
var transforms = ArrayTrie<Transform>()
transforms.set(["user1", "name"], value: .update("Alicia"))

let updated = try outer.transform(transforms: transforms)
// The nested dictionary gets a new CID, which changes the parent's CID
```

### Encryption

Cashew supports AES-GCM encryption for content-addressable headers. The CID becomes a hash of the ciphertext, so content-addressing guarantees still hold.

#### Encrypting a Single Header

```swift
import Crypto

let key = SymmetricKey(size: .bits256)
let scalar = MyScalar(value: 42)

let encHeader = try HeaderImpl(node: scalar, key: key)
encHeader.encryptionInfo?.keyHash  // base64(SHA256(key))
encHeader.encryptionInfo?.iv       // base64(random nonce)
```

#### Storing and Resolving Encrypted Data

Fetchers must conform to `KeyProvider` to look up keys by hash:

```swift
class MyStoreFetcher: Storer, Fetcher, KeyProvider {
    private var storage: [String: Data] = [:]
    private var keys: [String: SymmetricKey] = [:]

    func registerKey(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let hash = Data(SHA256.hash(data: keyData)).base64EncodedString()
        keys[hash] = key
    }

    func key(for keyHash: String) -> SymmetricKey? { keys[keyHash] }
    func store(rawCid: String, data: Data) { storage[rawCid] = data }
    func fetch(rawCid: String) async throws -> Data {
        guard let data = storage[rawCid] else { throw MyError.notFound }
        return data
    }
}

let fetcher = MyStoreFetcher()
fetcher.registerKey(key)

let encHeader = try HeaderImpl(node: scalar, key: key)
try encHeader.storeRecursively(storer: fetcher)

let cidOnly = HeaderImpl<MyScalar>(
    rawCID: encHeader.rawCID,
    node: nil,
    encryptionInfo: encHeader.encryptionInfo
)
let resolved = try await cidOnly.resolve(fetcher: fetcher)
resolved.node!  // decrypted scalar
```

#### Path-Based Encryption Strategies

Encryption strategies are specified via `ArrayTrie<EncryptionStrategy>`:

- **`.targeted(key)`** — Encrypts only the value at a specific path.
- **`.list(key)`** — Encrypts the trie structure (RadixHeaders). Keys aren't enumerable without the key.
- **`.recursive(key)`** — Encrypts everything — structure and values — with the same key.

```swift
var dict = MerkleDictionaryImpl<HeaderImpl<MyScalar>>()
dict = try dict.inserting(key: "public-field", value: HeaderImpl(node: MyScalar(value: 1)))
dict = try dict.inserting(key: "secret-field", value: HeaderImpl(node: MyScalar(value: 2)))
let header = HeaderImpl(node: dict)

var encryption = ArrayTrie<EncryptionStrategy>()
encryption.set(["secret-field"], value: .targeted(key))
let encrypted = try header.encrypt(encryption: encryption)

let publicVal = try encrypted.node!.get(key: "public-field")!
publicVal.encryptionInfo  // nil — plaintext

let secretVal = try encrypted.node!.get(key: "secret-field")!
secretVal.encryptionInfo  // non-nil — encrypted
```

Different keys for different branches:

```swift
let teamKey = SymmetricKey(size: .bits256)
let aliceKey = SymmetricKey(size: .bits256)

var encryption = ArrayTrie<EncryptionStrategy>()
encryption.set([""], value: .recursive(teamKey))
encryption.set(["alice"], value: .recursive(aliceKey))

let encrypted = try header.encrypt(encryption: encryption)
// "bob" uses teamKey; "alice" and descendants use aliceKey
```

#### Preserving Encryption Through Transforms

Supply a `KeyProvider` to preserve encryption when transforming:

```swift
var transforms = ArrayTrie<Transform>()
transforms.set(["alice"], value: .delete)
let result = try encrypted.transform(transforms: transforms, keyProvider: fetcher)
```

| Transform | Encryption behavior |
|-----------|-------------------|
| **Delete** (value removed) | Header is gone — nothing to preserve |
| **Delete** (trie restructured) | Surviving headers keep their encryption |
| **Update** | Header re-encrypted with same key, new IV |
| **Insert** | New header is **not** auto-encrypted |
| **No keyProvider** | Encryption is stripped (backward compatible) |

To encrypt newly inserted content, use the combined transform+encrypt overload:

```swift
let result = try header.transform(
    transforms: transforms,
    encryption: encryption,
    keyProvider: fetcher
)
```

#### Serialization Format

```swift
let enc = try HeaderImpl(node: scalar, key: key)
enc.description
// "enc:abc123...==:def456...==:baguqeer..."
//       keyHash       iv        rawCID

let restored = HeaderImpl<MyScalar>(enc.description)!
restored.rawCID == enc.rawCID  // true
```

See [Encryption README](Sources/cashew/Encryption/README.md) for the full reference.

## Real-World Examples

The test suite includes scenario-based tests that demonstrate practical usage patterns. See `Tests/cashewTests/RealWorldTests.swift` for the full implementations.

### User Profile Store

Model user profiles as a `MerkleDictionaryImpl<String>`, exercise the full lifecycle (insert, query, update, delete), and verify structural sharing — unchanged user records keep the same CIDs across versions.

### Version-Controlled Configuration

Store configuration as versioned snapshots. Each version gets its own root CID. Roll back to any historical version by resolving its CID.

### Access-Controlled Records

Use targeted encryption on `MerkleDictionaryImpl<HeaderImpl<TestScalar>>` to encrypt private fields per-record while keeping public fields readable by anyone. Authorized resolvers (with the key) read private data; unauthorized resolvers get `DataErrors.keyNotFound`.

### Lazy-Loading Catalog

Build a 3-level hierarchy (catalog → categories → products). Demonstrate resolution strategies: `.list` loads category structure with values still CID-only, `.targeted` resolves a single category, `.recursive` loads an entire subtree.

### Audit Trail with Merkle Proofs

Build a transaction ledger and generate existence/insertion/deletion proofs. Proofs from CID-only headers are minimal — only the path to the target key is materialized; unrelated branches stay as CID stubs.

## API Reference

### Protocols

| Protocol | Conforms To | Purpose |
|----------|-------------|---------|
| `Node` | `Codable`, `LosslessStringConvertible`, `Sendable` | Base for all Merkle structures. Defines `get`, `set`, `resolve`, `transform`, `proof`, `storeRecursively`. |
| `Address` | `Sendable` | Reference to content. Supports `resolve`, `proof`, `transform`, `storeRecursively`, `removingNode`. |
| `Header` | `Codable`, `Address`, `LosslessStringConvertible` | Wraps a `Node` with its CID and optional `EncryptionInfo`. Can be resolved or unresolved. |
| `RadixNode` | `Node` | Compressed trie node with `prefix`, optional `value`, and `children`. |
| `RadixHeader` | `Header` | Header constrained to `RadixNode`. |
| `MerkleDictionary` | `Node` | Top-level key-value map. Dispatches by first character to `RadixHeader` children. |
| `Scalar` | `Node` | Leaf node with no children. Returns empty for `properties()`. |
| `Fetcher` | `Sendable` | Async data retrieval by CID. One method: `fetch(rawCid:) async throws -> Data`. |
| `Storer` | -- | Data persistence by CID. One method: `store(rawCid:data:) throws`. |
| `KeyProvider` | -- | Key lookup by hash. One method: `key(for:) -> SymmetricKey?`. |
| `KeyProvidingFetcher` | `Fetcher`, `KeyProvider` | Combined fetcher + key provider for resolving encrypted data. |

### Enums

| Enum | Cases | Purpose |
|------|-------|---------|
| `ResolutionStrategy` | `.targeted`, `.recursive`, `.list` | Controls how deep resolution goes |
| `Transform` | `.insert(String)`, `.update(String)`, `.delete` | Mutation operations for transforms |
| `SparseMerkleProof` | `.insertion`, `.mutation`, `.deletion`, `.existence` | Proof types for sparse Merkle proofs |
| `EncryptionStrategy` | `.targeted(key)`, `.list(key)`, `.recursive(key)` | Controls what gets encrypted at each path |

### Error Types

| Error | Cases |
|-------|-------|
| `DataErrors` | `.nodeNotAvailable`, `.serializationFailed`, `.cidCreationFailed`, `.encryptionFailed`, `.keyNotFound`, `.invalidIV` |
| `TransformErrors` | `.transformFailed`, `.invalidKey`, `.missingData` |
| `ProofErrors` | `.invalidProofType`, `.proofFailed` |
| `ResolutionErrors` | `.typeError` |
| `CashewDecodingError` | `.decodeFromDataError` |

### Concrete Types

| Type | Purpose |
|------|---------|
| `MerkleDictionaryImpl<V>` | Concrete `MerkleDictionary`. `V` must be `Codable + Sendable + LosslessStringConvertible`. |
| `RadixNodeImpl<V>` | Concrete `RadixNode` with JSON coding for `Character`-keyed children. |
| `HeaderImpl<N>` | Generic `Header` wrapping any `Node` type. |
| `RadixHeaderImpl<V>` | `RadixHeader` for `RadixNodeImpl<V>`. |
| `ThreadSafeDictionary<K,V>` | Actor-based thread-safe dictionary for concurrent resolution. |
| `EncryptionInfo` | Metadata on an encrypted header (`keyHash` + `iv`). |

## Architecture

### Data Flow

```
                        ┌─────────────┐
                        │   Fetcher   │  (pluggable: IPFS, DB, filesystem)
                        │ fetch(cid)  │
                        └──────┬──────┘
                               │ Data
                               ▼
  ┌──────────┐  resolve   ┌─────────┐  transform   ┌──────────┐
  │Unresolved├───────────>│Resolved ├──────────────>│  New     │
  │  Header  │            │ Header  │               │ Header   │
  │(CID only)│            │(CID+Node)              │(new CID) │
  └──────────┘            └────┬────┘               └────┬─────┘
                               │                         │
                               │ proof     encrypt       │ storeRecursively
                               ▼             │           ▼
                        ┌──────────┐         │    ┌─────────────┐
                        │  Proof   │         └───>│   Storer    │
                        │(minimal  │              │ + KeyProvider│
                        │ subtree) │              │ store(cid,  │
                        └──────────┘              │       data) │
                                                  └─────────────┘
```

### Protocol Hierarchy

```
Node (base: Codable + LosslessStringConvertible + Sendable)
  |-- Scalar (leaf node, no children)
  |-- RadixNode (compressed trie node)
  |-- MerkleDictionary (top-level key-value map)

Address (Sendable, supports resolve/proof/transform/store/encrypt)
  |-- Header (Codable, wraps a Node with its CID + optional EncryptionInfo)
      |-- RadixHeader (Header constrained to RadixNode)
```

Concrete implementations: `MerkleDictionaryImpl<V>`, `RadixNodeImpl<V>`, `HeaderImpl<N>`, `RadixHeaderImpl<V>`.

### How the Trie Works

A `MerkleDictionary` maps string keys to values by dispatching on the first character to a radix trie branch:

```
MerkleDictionary { count: 4 }
  'a' -> RadixHeader -> RadixNode(prefix: "alice", value: "engineer", children: {})
  'b' -> RadixHeader -> RadixNode(prefix: "b", value: nil, children: {
           'o' -> RadixHeader -> RadixNode(prefix: "ob", value: "designer", children: {})
           'a' -> RadixHeader -> RadixNode(prefix: "az", value: "manager", children: {})
         })
```

Path compression stores "alice" as a single node rather than 5 chained nodes — O(k) lookup where k is key length. When serialized, only CIDs are written; resolve headers by fetching from a content-addressable store.

## Project Structure

```
Sources/cashew/
  Core/           -- Node, Address, Header protocols + CID creation + encryption helpers
  MerkleDataStructures/ -- MerkleDictionary, RadixNode, RadixHeader protocols + concrete impls
  Fetcher/        -- Fetcher, Storer, KeyProvider protocols + store extensions
  Resolver/       -- Resolution strategies + resolve extensions per type
  Transform/      -- Transform operations + insert/delete/mutate/get per type
  Encryption/     -- Encryption strategies + encrypt extensions per type
  Proofs/         -- Sparse Merkle proof types + proof extensions per type
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [ArrayTrie](https://github.com/treehauslabs/ArrayTrie) | Trie data structure for path-based traversal of resolution/transform/proof specs |
| [swift-crypto](https://github.com/apple/swift-crypto) | SHA2-256 hashing for CID generation |
| [swift-cid](https://github.com/swift-libp2p/swift-cid) | IPFS CIDv1 content identifiers |
| [swift-multicodec](https://github.com/swift-libp2p/swift-multicodec) | Codec identifiers (dag-json, dag-cbor, etc.) |
| [swift-multihash](https://github.com/swift-libp2p/swift-multihash) | Self-describing hash format |
| [swift-collections](https://github.com/apple/swift-collections) | Swift standard collections |
| [CollectionConcurrencyKit](https://github.com/JohnSundell/CollectionConcurrencyKit) | `concurrentForEach` for parallel async operations |

## Running Tests

```bash
swift test
```

327 tests across 38 suites covering resolution, transforms, proofs, headers, key enumeration, encryption, and real-world scenarios.

## License

MIT
