import Foundation

/// A point in a Merkle DAG where peers may store child blocks contiguously.
///
/// In v2, every ``Header`` is a potential Volume boundary. The resolver handles
/// Volume boundaries implicitly — no explicit enter/exit scope management.
public protocol Volume: Header { }

extension HeaderImpl: Volume { }

/// Backward-compatible alias. In v2, VolumeImpl is HeaderImpl — there is no
/// separate type. Every Header is a potential Volume boundary.
public typealias VolumeImpl<NodeType: Node> = HeaderImpl<NodeType>
