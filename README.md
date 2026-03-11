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
| **MerkleArray** | Append-only ordered collection backed by a `MerkleDictionary` with UInt256 binary keys. Supports efficient range queries. |
| **MerkleSet** | Membership-only set backed by a `MerkleDictionary` with empty string sentinels. Supports union, intersection, difference. |

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

### MerkleArray

An ordered, append-only collection backed by a `MerkleDictionary` with 256-bit binary string keys. Indices are encoded as 256-character strings of `0` and `1`, so lexicographic order matches numeric order and the radix trie compresses sequential indices efficiently.

```swift
import cashew

var log = MerkleArrayImpl<String>()
log = try log.append("event_1")
log = try log.append("event_2")
log = try log.append("event_3")

let first = try log.first()   // "event_1"
let last = try log.last()     // "event_3"
let val = try log.get(at: 1)  // "event_2"
log.count                      // 3
```

Mutate and delete by index:

```swift
log = try log.mutating(at: 1, value: "event_2_updated")
log = try log.deleting(at: 0)  // swaps with last element to maintain contiguous indices
```

Concatenate two arrays:

```swift
var batch = MerkleArrayImpl<String>()
batch = try batch.append("new_1").append("new_2")
log = try log.append(contentsOf: batch)
```

#### Range Queries

Range queries use `.range` as a `ResolutionStrategy`, resolved via `resolve(paths:)`. Fetches `O(k)` nodes, not `O(n)`:

```swift
let header = HeaderImpl(node: log)
try header.storeRecursively(storer: myStore)

let resolved = try await HeaderImpl<MerkleArrayImpl<String>>(rawCID: header.rawCID)
    .resolve(fetcher: myFetcher)

// Load only indices 10..<20 from a 1000-element array
let page = try await resolved.node!.resolve(
    paths: MerkleArrayImpl<String>.rangePaths(10..<20), fetcher: myFetcher
)
```

Build custom resolution paths for full control:

```swift
var paths = ArrayTrie<ResolutionStrategy>()
paths.set([], value: .range(10..<20))       // expands to .targeted for each index
paths.set([MerkleArrayImpl<String>.binaryKey(15)], value: .recursive) // override: recursively resolve index 15
let page = try await resolved.node!.resolve(paths: paths, fetcher: myFetcher)
```

#### Nested Arrays and Chained Range Queries

Values can be `Header` types wrapping inner `MerkleArray`s. Range queries chain through both levels — `.range` at an outer key flows through to the inner array:

```swift
typealias InnerArray = MerkleArrayImpl<String>
typealias OuterArray = MerkleArrayImpl<HeaderImpl<InnerArray>>

// Resolve outer[2..<5] and for each, resolve inner[0..<10]
let page = try await outer.resolve(
    paths: OuterArray.rangePaths(2..<5, innerStrategy: .range(0..<10)),
    fetcher: myFetcher
)
```

Apply transforms across a range of nested arrays:

```swift
let innerTransforms: [[String]: Transform] = [
    [InnerArray.binaryKey(3)]: .update("new_value")
]
// Updates index 3 in every inner array at outer indices 0..<4
let result = try outer.transformNested(
    outerRange: 0..<4, innerTransforms: innerTransforms
)
```

Or build the full path manually for selective transforms:

```swift
var transforms = ArrayTrie<Transform>()
transforms.set([OuterArray.binaryKey(0), InnerArray.binaryKey(2)], value: .update("changed"))
transforms.set([OuterArray.binaryKey(1), InnerArray.binaryKey(5)], value: .delete)
let result = try outer.transform(transforms: transforms)
```

### MerkleSet

A membership-only collection backed by `MerkleDictionary` with empty string sentinels as values. Supports standard set operations.

```swift
import cashew

var set = MerkleSetImpl()
set = try set.insert("alice")
set = try set.insert("bob")
set = try set.insert("charlie")

try set.contains("alice")  // true
try set.contains("dave")   // false
set.count                   // 3

let members: Set<String> = try set.members()  // {"alice", "bob", "charlie"}

set = try set.remove("bob")
try set.contains("bob")  // false
```

Set operations:

```swift
let a = try MerkleSetImpl().insert("alice").insert("bob")
let b = try MerkleSetImpl().insert("bob").insert("charlie")

let union = try a.union(b)                // {"alice", "bob", "charlie"}
let intersection = try a.intersection(b)  // {"bob"}
let difference = try a.subtracting(b)     // {"alice"}
let symDiff = try a.symmetricDifference(b) // {"alice", "charlie"}
```

`MerkleSet` inherits all `MerkleDictionary` capabilities — content addressability, resolution, encryption, proofs, and transforms all work unchanged.

### Cursor Iteration

`MerkleDictionary` supports sorted key iteration with cursor-based pagination by traversing the radix trie in lexicographic order.

```swift
var dict = MerkleDictionaryImpl<String>()
dict = try dict.inserting(key: "cherry", value: "3")
dict = try dict.inserting(key: "apple", value: "1")
dict = try dict.inserting(key: "banana", value: "2")

let sorted = try dict.sortedKeys()  // ["apple", "banana", "cherry"]
let pairs = try dict.sortedKeysAndValues()  // [(key: "apple", value: "1"), ...]
```

Paginate with `limit` and `after`:

```swift
let page1 = try dict.sortedKeys(limit: 2)               // ["apple", "banana"]
let page2 = try dict.sortedKeys(limit: 2, after: "banana") // ["cherry"]

let valuePage = try dict.sortedKeysAndValues(limit: 10, after: lastKey)
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

### Query Language

Cashew includes a simple query language for reading and transforming data structures via strings. Queries return a `(Self, CashewResult)` tuple — the possibly-modified structure and the result of the last expression.

```swift
var dict = MerkleDictionaryImpl<String>()

// Build up data and query in one pipeline
let (updated, result) = try dict.query("""
    insert "alice" = "engineer" | insert "bob" = "designer" | keys sorted
""")
// result == .list(["alice", "bob"])
// updated has both keys inserted
```

#### Commands

| Command | Example | Result |
|---------|---------|--------|
| `get "key"` | `get "alice"` | `.value("engineer")` |
| `keys` | `keys` | `.list(["alice", "bob"])` |
| `keys sorted` | `keys sorted limit 5 after "a"` | `.list([...])` |
| `values` | `values` | `.entries([...])` |
| `values sorted` | `values sorted limit 10` | `.entries([...])` |
| `count` | `count` | `.count(2)` |
| `contains "key"` | `contains "alice"` | `.bool(true)` |
| `insert "key" = "val"` | `insert "alice" = "engineer"` | `.ok` |
| `update "key" = "val"` | `update "alice" = "lead"` | `.ok` |
| `set "key" = "val"` | `set "alice" = "cto"` | `.ok` (insert or update) |
| `delete "key"` | `delete "alice"` | `.ok` |

Array-specific (on `MerkleArray`):

| Command | Example | Result |
|---------|---------|--------|
| `get at <n>` | `get at 0` | `.value("first")` |
| `first` | `first` | `.value("first")` |
| `last` | `last` | `.value("last")` |
| `append "val"` | `append "new"` | `.ok` |

Aliases: `members` = `keys`, `size` = `count`, `has` = `contains`, `add` = `insert`, `remove`/`delete`, `put` = `set`.

#### Pipelines

Chain expressions with `|` to build up data and query it:

```swift
let (_, result) = try MerkleDictionaryImpl<String>().query("""
    insert "cherry" = "3" | insert "apple" = "1" | insert "banana" = "2" | keys sorted limit 2
""")
// result == .list(["apple", "banana"])
```

```swift
let (arr, result) = try MerkleArrayImpl<String>().query("""
    append "hello" | append "world" | first
""")
// result == .value("hello"), arr.count == 2
```

#### Execution Model

Queries compile into a `CashewPlan` that batches consecutive transforms into a single `ArrayTrie<Transform>`, applied in one pass via the existing `transform(transforms:)` machinery. Reads flush pending transforms first.

```swift
// These three inserts compile into ONE ArrayTrie<Transform> step, not three separate tree rebuilds
let (dict, _) = try MerkleDictionaryImpl<String>().query("""
    insert "a" = "1" | insert "b" = "2" | insert "c" = "3"
""")
```

For lazy-loaded data, the plan computes resolution paths automatically. Use the async variant with a fetcher to resolve before executing:

```swift
// Computes resolution paths: ["alice"] → .targeted
// Resolves needed nodes from store, then executes the query
let (_, result) = try await unresolvedDict.query(#"get "alice""#, fetcher: myFetcher)
```

You can also inspect or use the plan directly:

```swift
let expressions = try CashewParser.parse(#"insert "a" = "1" | get "a""#)
let plan = CashewPlan.compile(expressions)

plan.steps        // [.transform(trie), .evaluate(.get("a"))]
plan.resolutionPaths()  // ArrayTrie with ["a"] → .targeted
```

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

### Append-Only Event Log

Use `MerkleArrayImpl<String>` as an append-only event log. Each append produces a new root CID. Range queries enable pagination — load only the events you need. Structural sharing means appending one event only changes the trie branch for the new index.

### Time-Series Sensor Data

Model multi-sensor time-series as `MerkleArrayImpl<HeaderImpl<MerkleArrayImpl<String>>>` — an outer array of sensors, each containing an inner array of readings. Chained range queries load readings 5..10 from sensors 1..3 without touching the rest. Nested transforms apply calibration updates across all sensors in one pass.

### Chat Message History

Combine `MerkleDictionary` (keyed by channel name) with `MerkleArray` (messages per channel). Pagination loads only the last N messages. Every message append produces a new CID for auditable history.

### Audit Trail with Merkle Proofs

Build a transaction ledger and generate existence/insertion/deletion proofs. Proofs from CID-only headers are minimal — only the path to the target key is materialized; unrelated branches stay as CID stubs.

## API Reference

### Protocols

| Protocol | Conforms To | Purpose |
|----------|-------------|---------|
| `Node` | `Codable`, `LosslessStringConvertible`, `Sendable` | Base for all Merkle structures. Defines `get`, `set`, `resolve`, `transform`, `proof`, `storeRecursively`. |
| `Header` | `Codable`, `Sendable`, `LosslessStringConvertible` | Wraps a `Node` with its CID and optional `EncryptionInfo`. Supports resolve, proof, transform, store, encrypt. Can be resolved or unresolved. |
| `RadixNode` | `Node` | Compressed trie node with `prefix`, optional `value`, and `children`. |
| `RadixHeader` | `Header` | Header constrained to `RadixNode`. |
| `MerkleDictionary` | `Node` | Top-level key-value map. Dispatches by first character to `RadixHeader` children. Supports cursor-based sorted iteration. |
| `MerkleArray` | `Node` | Ordered append-only collection backed by `MerkleDictionary` with UInt256 binary keys. |
| `MerkleSet` | `MerkleDictionary` | Membership-only set backed by `MerkleDictionary` with empty string sentinels. Set operations: union, intersection, subtracting, symmetricDifference. |
| `Scalar` | `Node` | Leaf node with no children. Returns empty for `properties()`. |
| `Fetcher` | `Sendable` | Async data retrieval by CID. One method: `fetch(rawCid:) async throws -> Data`. |
| `Storer` | -- | Data persistence by CID. One method: `store(rawCid:data:) throws`. |
| `KeyProvider` | -- | Key lookup by hash. One method: `key(for:) -> SymmetricKey?`. |
| `KeyProvidingFetcher` | `Fetcher`, `KeyProvider` | Combined fetcher + key provider for resolving encrypted data. |

### Enums

| Enum | Cases | Purpose |
|------|-------|---------|
| `ResolutionStrategy` | `.targeted`, `.recursive`, `.list`, `.range(after:limit:)` | Controls how deep resolution goes |
| `Transform` | `.insert(String)`, `.update(String)`, `.delete` | Mutation operations for transforms |
| `SparseMerkleProof` | `.insertion`, `.mutation`, `.deletion`, `.existence` | Proof types for sparse Merkle proofs |
| `EncryptionStrategy` | `.targeted(key)`, `.list(key)`, `.recursive(key)` | Controls what gets encrypted at each path |

### Error Types

| Error | Cases |
|-------|-------|
| `DataErrors` | `.nodeNotAvailable`, `.serializationFailed`, `.cidCreationFailed`, `.encryptionFailed`, `.keyNotFound`, `.invalidIV` |
| `TransformErrors` | `.transformFailed(String)`, `.invalidKey(String)`, `.missingData(String)` |
| `ProofErrors` | `.invalidProofType(String)`, `.proofFailed(String)` |
| `ResolutionErrors` | `.typeError(String)` |
| `CashewDecodingError` | `.decodeFromDataError` |

### Concrete Types

| Type | Purpose |
|------|---------|
| `MerkleDictionaryImpl<V>` | Concrete `MerkleDictionary`. `V` must be `Codable + Sendable + LosslessStringConvertible`. |
| `MerkleArrayImpl<V>` | Concrete `MerkleArray`. Same constraints as `MerkleDictionaryImpl`. |
| `MerkleSetImpl` | Concrete `MerkleSet`. Uses `String` values with empty string sentinel. |
| `RadixNodeImpl<V>` | Concrete `RadixNode` with JSON coding for `Character`-keyed children. |
| `HeaderImpl<N>` | Generic `Header` wrapping any `Node` type. |
| `RadixHeaderImpl<V>` | `RadixHeader` for `RadixNodeImpl<V>`. |
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
  |-- MerkleArray (ordered collection, backed by MerkleDictionary)
  |-- MerkleSet (membership set, backed by MerkleDictionary)

Header (Codable + Sendable, wraps a Node with its CID + optional EncryptionInfo)
  |-- RadixHeader (Header constrained to RadixNode)
```

Concrete implementations: `MerkleDictionaryImpl<V>`, `MerkleArrayImpl<V>`, `MerkleSetImpl`, `RadixNodeImpl<V>`, `HeaderImpl<N>`, `RadixHeaderImpl<V>`.

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
  Core/           -- Node, Header protocols + CID creation + encryption helpers
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

## Running Tests

```bash
swift test
```

Tests cover resolution, transforms, proofs, headers, key enumeration, encryption, arrays, range query performance, and real-world scenarios.

## License

MIT
