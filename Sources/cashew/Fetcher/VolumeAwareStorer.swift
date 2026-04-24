/// A ``Storer`` that receives context when a ``Volume`` boundary is crossed
/// during recursive storage.
///
/// Before writing the child CIDs that make up a Volume's contiguous data,
/// the walker calls ``provide(rootCID:)`` so the storer can group per-Volume
/// writes for locality (e.g., batched sequential disk append) and downstream
/// systems can index which Volume root each non-boundary CID belongs to.
public protocol VolumeAwareStorer: Storer {
    /// Called at the start of a Volume subtree walk, before any child
    /// ``store(rawCid:data:)`` call for CIDs inside this Volume. Nested
    /// Volumes fire their own `provide` before their children are stored,
    /// so every non-Volume CID is stored under exactly one enclosing
    /// rootCID — the one most recently provided.
    func provide(rootCID: String) throws
}
