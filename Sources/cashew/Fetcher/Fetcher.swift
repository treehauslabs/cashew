import CID
import Foundation

public protocol Fetcher: Sendable {
    func fetch(rawCid: String) async throws -> Data
}
