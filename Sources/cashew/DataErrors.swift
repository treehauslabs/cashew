/// Errors from data serialization, CID computation, and encryption operations.
public enum DataErrors: Error {
    case nodeNotAvailable
    case serializationFailed
    case cidCreationFailed
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case invalidIV
}

