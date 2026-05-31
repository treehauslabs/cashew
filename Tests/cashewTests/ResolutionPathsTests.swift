import Testing
import Foundation
import ArrayTrie
@testable import cashew

@Suite("ResolutionPaths")
struct ResolutionPathsTests {
    @Test("ResolutionPaths is stable and converts to ArrayTrie")
    func stableAndTrieBacked() {
        let paths = ResolutionPaths([
            ResolutionPath(["transactions"], strategy: .recursive),
            ResolutionPath(["children", ""], strategy: .list),
            ResolutionPath(["spec"], strategy: .targeted),
        ])

        #expect(paths.entries.map(\.components) == [
            ["children", ""],
            ["spec"],
            ["transactions"],
        ])

        let trie = paths.asTrie()
        #expect(trie.get(["spec"]) == .targeted)
        #expect(trie.get(["transactions"]) == .recursive)
        #expect(trie.get(["children", ""]) == .list)
    }

    @Test("ResolutionPaths round-trips through Codable")
    func codableRoundTrip() throws {
        let paths = ResolutionPaths([
            ResolutionPath([], strategy: .targeted),
            ResolutionPath(["accounts"], strategy: .range(after: "alice", limit: 10)),
            ResolutionPath(["transactions"], strategy: .recursive),
        ])

        let data = try JSONEncoder().encode(paths)
        let decoded = try JSONDecoder().decode(ResolutionPaths.self, from: data)

        #expect(decoded == paths)
        #expect(decoded.asTrie().get([]) == .targeted)
        #expect(decoded.asTrie().get(["accounts"]) == .range(after: "alice", limit: 10))
    }
}
