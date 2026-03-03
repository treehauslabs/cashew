# Cashew

A Swift library for content-addressable Merkle data structures with lazy resolution, sparse proofs, and structural transformations.

## Overview

Cashew solves a specific problem: how do you build a key-value store where every version of the data has a unique cryptographic fingerprint, parts of the data can live on remote storage and be loaded on-demand, and you can efficiently prove things about what's in (or not in) the store without materializing all of it?

The answer is a **Merkle radix trie** -- a compressed trie where every node is identified by a CID (Content Identifier), which is the SHA2-256 hash of the node's deterministic JSON serialization. This is the same content-addressing scheme used by IPFS/IPLD, meaning Cashew data structures are natively interoperable with the IPFS ecosystem.

### The Core Idea

Every data structure in Cashew is **immutable** and **content-addressed**. When you "modify" a dictionary, you get back a new dictionary with a new root CID. Unchanged subtrees share the same CIDs as before -- this is structural sharing through content addressing.

The key abstraction is the **Header** -- a smart pointer that holds a CID and optionally the data that CID refers to:

```
Header
  rawCID: "baguqeera..."   <- always present (the hash)
  node: RadixNode?          <- sometimes present (the actual data)
```

A Header with `node == nil` is an **unresolved reference** -- you know *what* data exists (by its hash) but haven't loaded it yet. Call `resolve(fetcher:)` to fetch the data from any content-addressable store (IPFS, a database, the filesystem) and populate the `node`. This is how Cashew enables lazy loading of arbitrarily large data structures.

### How the Trie Works

A `MerkleDictionary` maps string keys to values. Internally, it dispatches by the first character of each key to a radix trie branch:

```
MerkleDictionary { count: 4 }
  'a' -> RadixHeader -> RadixNode(prefix: "alice", value: "engineer", children: {})
  'b' -> RadixHeader -> RadixNode(prefix: "b", value: nil, children: {
           'o' -> RadixHeader -> RadixNode(prefix: "ob", value: "designer", children: {})
           'a' -> RadixHeader -> RadixNode(prefix: "az", value: "manager", children: {})
         })
```

Each `RadixNode` stores a compressed `prefix` (the shared path segment), an optional `value` (present if this node terminates a complete key), and `children` keyed by the next character. Path compression means "alice" is stored as a single node rather than 5 chained nodes -- giving O(k) lookup where k is key length, with much lower constant factors than an uncompressed trie.

Every `RadixNode` is wrapped in a `RadixHeader` that computes its CID. When the dictionary is serialized (for storage or transmission), only the CIDs are written -- the actual node data is stripped. To reconstruct the data, you resolve headers by fetching node data from a content-addressable store using the CIDs.

### What You Can Do

Cashew provides four operations on these structures, each specified as a trie of paths:

**1. Resolution** -- Load data from storage. Three strategies control how deep to go:
- `.targeted`: fetch one node (e.g., load just the user's profile header)
- `.recursive`: fetch everything beneath a path (e.g., load an entire subtree)
- `.list`: fetch the trie structure for navigation but leave value-level addresses unresolved (e.g., list all user IDs without loading their profile data)

**2. Transform** -- Mutate the structure (insert, update, delete). Returns a new tree with new CIDs for affected nodes. Handles radix trie maintenance: splitting prefixes when keys diverge, merging nodes when deletions make branches unnecessary.

**3. Proof** -- Generate a minimal subtree proving specific properties:
- `.existence`: this key exists with this value
- `.insertion`: this key does not exist (proving it's safe to insert)
- `.mutation`: this key exists (proving it can be updated)
- `.deletion`: this key exists and here are its neighbors (proving deletion is structurally valid)

**4. Storage** -- Persist resolved nodes to a content-addressable store via `storeRecursively`.

**5. Encryption** -- Selectively encrypt parts of the tree while keeping others public. Three strategies (`targeted`, `list`, `recursive`) control what gets encrypted at each path. Encryption is preserved through transforms when a `KeyProvider` is supplied.

### Nested Dictionaries (Two-Level Addressing)

When `ValueType` is itself a `Header<MerkleDictionary>`, Cashew supports hierarchical structures -- a dictionary whose values are other dictionaries, each with their own CID. This is the power case: you can have a users dictionary where each user value is a CID pointing to that user's own key-value store.

Transforms propagate through both levels: `transforms.set(["user1", "name"], value: .update("Alice"))` reaches into the nested dictionary at key "user1" and updates the "name" key inside it. The nested dictionary gets a new CID, which changes the parent's value, which gives the parent a new CID -- the Merkle property propagates up to the root.

A specialized `RadixNode` extension (`where ValueType: Header, ValueType.NodeType: MerkleDictionary`) handles these two-level transforms, including creating new empty nested dictionaries on-the-fly when inserting into a path that doesn't exist yet.

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

### Architecture

Protocol hierarchy:

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

Each operation (resolve, transform, proof) is implemented via protocol extensions organized by type: `Node+resolve.swift`, `RadixNode+resolve.swift`, `MerkleDictionary+resolve.swift`, etc. The `RadixNode+transform.swift` file is the most complex (~500 lines) because it handles all the radix trie maintenance (prefix splitting, node merging) plus the nested-dictionary specialization.

Concurrency is handled via Swift actors (`ThreadSafeDictionary`) and `CollectionConcurrencyKit`'s `concurrentForEach` for parallel resolution of sibling branches.

## Requirements

- macOS 12.0+
- Swift 6.0+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pumperknickle/cashew.git", from: "1.0.0")
]
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [ArrayTrie](https://github.com/pumperknickle/ArrayTrie) | Trie data structure for path-based traversal of resolution/transform/proof specs |
| [swift-crypto](https://github.com/apple/swift-crypto) | SHA2-256 hashing for CID generation |
| [swift-cid](https://github.com/swift-libp2p/swift-cid) | IPFS CIDv1 content identifiers |
| [swift-multicodec](https://github.com/swift-libp2p/swift-multicodec) | Codec identifiers (dag-json, dag-cbor, etc.) |
| [swift-multihash](https://github.com/swift-libp2p/swift-multihash) | Self-describing hash format |
| [swift-collections](https://github.com/apple/swift-collections) | Swift standard collections |
| [CollectionConcurrencyKit](https://github.com/JohnSundell/CollectionConcurrencyKit) | `concurrentForEach` for parallel async operations |

## Usage

### Creating and Mutating a Dictionary

```swift
import cashew

// Create an empty dictionary with String values
var dict = MerkleDictionaryImpl<String>()

// Insert keys
dict = try dict.inserting(key: "alice", value: "engineer")
dict = try dict.inserting(key: "bob", value: "designer")
dict = try dict.inserting(key: "alicia", value: "manager")

// Lookup
let value = try dict.get(key: "alice") // Optional("engineer")

// Update
dict = try dict.mutating(key: "bob", value: "lead designer")

// Delete
dict = try dict.deleting(key: "alicia")

// Enumerate all keys
let keys: Set<String> = try dict.allKeys()

// Enumerate all key-value pairs
let pairs: [String: String] = try dict.allKeysAndValues()
```

### Content Addressability

Every structure has a deterministic CID derived from its content:

```swift
let node = RadixNodeImpl<String>(prefix: "hello", value: "world", children: [:])
let header = RadixHeaderImpl(node: node)
print(header.rawCID) // CIDv1 string, e.g. "baguqeera..."

// Same content always produces the same CID
let header2 = RadixHeaderImpl(node: node)
assert(header.rawCID == header2.rawCID)
```

### Resolution (Lazy Loading)

Headers can be created with only a CID. Resolution fetches the actual data using a pluggable `Fetcher`:

```swift
struct IPFSFetcher: Fetcher {
    func fetch(rawCid: String) async throws -> Data {
        // fetch from IPFS, a database, or any content-addressable store
    }
}

let fetcher = IPFSFetcher()

// Three resolution strategies, specified via ArrayTrie<ResolutionStrategy>:
var paths = ArrayTrie<ResolutionStrategy>()

// .targeted - fetch just this node (one level)
paths.set(["users", "a"], value: .targeted)

// .recursive - fetch this node and everything beneath it
paths.set(["config"], value: .recursive)

// .list - fetch the trie structure for traversal but leave nested
//         address values unresolved (lazy loading)
paths.set(["posts"], value: .list)

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

// Recursively stores this header and all resolved children
try header.storeRecursively(storer: MyStore())
```

### Transforms (Batch Mutations)

Apply multiple insert/update/delete operations in one pass using `ArrayTrie<Transform>`:

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

// Prove a key exists with its current value
proofPaths.set(["alice"], value: .existence)

// Prove a key can be inserted (doesn't exist yet)
proofPaths.set(["dave"], value: .insertion)

// Prove a key exists and can be mutated
proofPaths.set(["bob"], value: .mutation)

// Prove a key exists and can be deleted
proofPaths.set(["charlie"], value: .deletion)

let proof = try await dictionary.proof(paths: proofPaths, fetcher: fetcher)
// proof contains only the nodes needed to verify these properties
```

### Nested Dictionaries

Values can themselves be `Header` types wrapping `MerkleDictionary`, enabling nested/hierarchical structures:

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

Transforms on nested dictionaries propagate through the tree:

```swift
var transforms = ArrayTrie<Transform>()
// This updates "name" inside the nested dict at key "user1"
transforms.set(["user1", "name"], value: .update("Alicia"))

let updated = try outer.transform(transforms: transforms)
```

### Encryption

Cashew supports optional AES-GCM encryption for content-addressable headers. The CID becomes a hash of the ciphertext rather than the plaintext, so content-addressing guarantees still hold — you just can't read the content without the key.

This is useful when multiple parties share a content-addressable store but each party's data should only be readable by holders of that party's key, or when some fields in a record are public while others are private.

#### Encrypting a Single Header

```swift
import Crypto

let key = SymmetricKey(size: .bits256)
let scalar = MyScalar(value: 42)

let plainHeader = HeaderImpl(node: scalar)
let encHeader = try HeaderImpl(node: scalar, key: key)

encHeader.encryptionInfo?.keyHash  // base64(SHA256(key))
encHeader.encryptionInfo?.iv       // base64(random nonce)
```

#### Storing and Resolving Encrypted Data

Storers and fetchers must conform to `KeyProvider` to look up keys by hash:

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

At store time, the header re-encrypts deterministically using the IV stored in `encryptionInfo`. Because AES-GCM is deterministic given the same (key, nonce, plaintext) triple, this produces identical ciphertext whose hash matches the header's CID.

#### Path-Based Encryption Strategies

Encryption strategies are specified via `ArrayTrie<EncryptionStrategy>`, where paths map to parts of the dictionary's key space:

- **`.targeted(key)`** — At root (`[""]`): encrypts the **trie structure** and values at specifically targeted sub-paths. At a specific path: encrypts only the **value** at that path.
- **`.list(key)`** — Encrypts the **trie structure** (RadixHeaders). You can't enumerate keys without decrypting, but values remain as plaintext CIDs.
- **`.recursive(key)`** — Encrypts **everything** — both trie structure and values — with the same key.

```swift
var dict = MerkleDictionaryImpl<HeaderImpl<MyScalar>>()
dict = try dict.inserting(key: "public-field", value: HeaderImpl(node: MyScalar(value: 1)))
dict = try dict.inserting(key: "secret-field", value: HeaderImpl(node: MyScalar(value: 2)))
let header = HeaderImpl(node: dict)

// Only encrypt the value at "secret-field"
var encryption = ArrayTrie<EncryptionStrategy>()
encryption.set(["secret-field"], value: .targeted(key))
let encrypted = try header.encrypt(encryption: encryption)

let publicVal = try encrypted.node!.get(key: "public-field")!
publicVal.encryptionInfo  // nil — plaintext

let secretVal = try encrypted.node!.get(key: "secret-field")!
secretVal.encryptionInfo  // non-nil — encrypted
```

Recursive encryption propagates to all descendants, but longer-path entries override shorter ones. This lets you use different keys for different branches:

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

When you transform an encrypted tree, encryption is preserved automatically if you supply a `KeyProvider`:

```swift
var transforms = ArrayTrie<Transform>()
transforms.set(["alice"], value: .delete)
let result = try encrypted.transform(transforms: transforms, keyProvider: fetcher)

result!.encryptionInfo!.keyHash == encrypted.encryptionInfo!.keyHash  // true
result!.rawCID != encrypted.rawCID  // true — content changed
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

Encrypted headers serialize to a string preserving the encryption metadata:

```swift
let enc = try HeaderImpl(node: scalar, key: key)
enc.description
// "enc:abc123...==:def456...==:baguqeer..."
//       keyHash       iv        rawCID

let restored = HeaderImpl<MyScalar>(enc.description)!
restored.rawCID == enc.rawCID  // true
```

Plaintext headers serialize as before — just the bare CID string. See [Encryption README](Sources/cashew/Encryption/README.md) for the full encryption reference.

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
| `ResolutionErrors` | `.TypeError` |
| `DecodingError` (internal) | `.decodeFromDataError` |

### Concrete Types

| Type | Purpose |
|------|---------|
| `MerkleDictionaryImpl<V>` | Concrete `MerkleDictionary`. `V` must be `Codable + Sendable + LosslessStringConvertible`. |
| `RadixNodeImpl<V>` | Concrete `RadixNode` with JSON coding for `Character`-keyed children. |
| `HeaderImpl<N>` | Generic `Header` wrapping any `Node` type. |
| `RadixHeaderImpl<V>` | `RadixHeader` for `RadixNodeImpl<V>`. |
| `Box<T>` | Wrapper making `Sendable` types storable in a reference type (used by `HeaderImpl`). |
| `ThreadSafeDictionary<K,V>` | Actor-based thread-safe dictionary for concurrent resolution. |
| `EncryptionInfo` | Metadata on an encrypted header (`keyHash` + `iv`). |
| `EncryptionHelper` | Low-level AES-GCM encrypt/decrypt utilities. |

## Project Structure

```
Sources/cashew/
  Core/
    Node.swift              -- Node protocol + JSON serialization + compareSlices/commonPrefix helpers
    Address.swift           -- Address protocol
    Header.swift            -- Header protocol + CID creation + encryption helpers
    HeaderImpl.swift        -- Concrete Header + Box<T> wrapper
    EncryptionInfo.swift    -- EncryptionInfo struct (keyHash + iv metadata)
    EncryptionHelper.swift  -- AES-GCM encrypt/decrypt utilities
    Scalar.swift            -- Leaf node protocol (no children)
    MulticodecExtensions.swift -- Codec lookup utilities
  MerkleDataStructures/
    MerkleDictionary.swift  -- MerkleDictionary protocol + allKeys/allKeysAndValues
    MerkleDictionaryImpl.swift -- Concrete implementation with JSON coding
    RadixNode.swift         -- RadixNode protocol + property accessors
    RadixNodeImpl.swift     -- Concrete implementation with JSON coding
    RadixHeader.swift       -- RadixHeader protocol (one line)
    RadixHeaderImpl.swift   -- Concrete RadixHeader with JSON coding
  Fetcher/
    Fetcher.swift           -- Fetcher protocol
    Storer.swift            -- Storer protocol
    KeyProvider.swift       -- KeyProvider protocol (key lookup by hash)
    KeyProvidingFetcher.swift -- KeyProvidingFetcher protocol (Fetcher + KeyProvider)
    Node+store.swift        -- Node.storeRecursively extension
    Header+store.swift      -- Header.storeRecursively extension (re-encrypts at store time)
  Resolver/
    ResolutionStrategy.swift -- .targeted/.recursive/.list enum
    ResolutionErrors.swift  -- ResolutionErrors.TypeError
    Node+resolve.swift      -- Node.resolve and Node.resolveRecursive
    Header+resolve.swift    -- Header.resolve (fetches if node is nil)
    RadixNode+resolve.swift -- RadixNode.resolve with prefix traversal + list resolution
    RadixHeader+resolve.swift -- RadixHeader resolution (delegates to node)
    MerkleDictionary+resolve.swift -- MerkleDictionary resolution strategies
    Scalar+resolve.swift    -- No-op resolution for scalars
  Transform/
    Transform.swift         -- .insert/.update/.delete enum
    TransformErrors.swift   -- TransformErrors enum
    Node+transform.swift    -- Generic Node.transform
    Header+transform.swift  -- Header.transform (requires resolved node)
    RadixNode+transform.swift -- RadixNode transform + insert/delete/mutate/get + nested dict specialization
    RadixHeader+transform.swift -- RadixHeader delegates to node
    MerkleDictionary+transform.swift -- MerkleDictionary transform + get/insert/delete/mutate
  Encryption/
    README.md               -- Full encryption reference documentation
    EncryptionStrategy.swift -- .targeted/.list/.recursive enum
    Node+encrypt.swift      -- Node.encrypt extension
    Header+encrypt.swift    -- Header.encrypt + encryptSelf extensions
    RadixNode+encrypt.swift -- RadixNode path-based encryption
    RadixHeader+encrypt.swift -- RadixHeader encryption delegation
    MerkleDictionary+encrypt.swift -- MerkleDictionary encryption delegation
  Proofs/
    SparseMerkleProof.swift -- .insertion/.mutation/.deletion/.existence enum
    ProofErrors.swift       -- ProofErrors enum
    Node+proofs.swift       -- Generic Node.proof
    Header+proofs.swift     -- Header.proof (fetches if needed)
    RadixNode+proofs.swift  -- RadixNode proof with prefix traversal + grandchild resolution
    RadixHeader+proofs.swift -- RadixHeader proof delegation
    MerkleDictionary+proofs.swift -- MerkleDictionary proof delegation
  ThreadSafeDictionary.swift -- Actor-based thread-safe dictionary
  DataErrors.swift          -- DataErrors enum
  DecodingErrors.swift      -- Internal DecodingError enum
  LosslessStringConvertible+data.swift -- Data/String conversion extensions
```

## Running Tests

```bash
swift test
```

277 tests across 15 test files covering resolution, transforms, proofs, headers, key enumeration, and encryption.

## License

MIT
