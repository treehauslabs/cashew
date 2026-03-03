import Crypto

public protocol KeyProvider {
    func key(for keyHash: String) -> SymmetricKey?
}
