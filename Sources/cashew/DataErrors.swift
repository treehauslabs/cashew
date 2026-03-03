public enum DataErrors: Error {
    case nodeNotAvailable
    case serializationFailed
    case cidCreationFailed
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case invalidIV
}

