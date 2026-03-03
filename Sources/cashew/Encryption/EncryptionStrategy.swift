@preconcurrency import Crypto

public enum EncryptionStrategy: @unchecked Sendable {
    case targeted(SymmetricKey)
    case list(SymmetricKey)
    case recursive(SymmetricKey)

    public var key: SymmetricKey {
        switch self {
        case .targeted(let key): return key
        case .list(let key): return key
        case .recursive(let key): return key
        }
    }
}
