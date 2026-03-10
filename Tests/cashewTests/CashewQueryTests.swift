import Testing
import Foundation
import ArrayTrie
@testable import cashew

@Suite("Cashew Query Language")
struct CashewQueryTests {

    typealias Dict = MerkleDictionaryImpl<String>
    typealias Arr = MerkleArrayImpl<String>

    @Suite("Parser")
    struct ParserTests {

        @Test("Parses get with quoted key")
        func testParseGet() throws {
            let exprs = try CashewParser.parse(#"get "alice""#)
            #expect(exprs == [.get("alice")])
        }

        @Test("Parses get at index")
        func testParseGetAt() throws {
            let exprs = try CashewParser.parse("get at 5")
            #expect(exprs == [.getAt(5)])
        }

        @Test("Parses keys and keys sorted")
        func testParseKeys() throws {
            #expect(try CashewParser.parse("keys") == [.keys])
            #expect(try CashewParser.parse("keys sorted") == [.sortedKeys(limit: nil, after: nil)])
            #expect(try CashewParser.parse("keys sorted limit 10") == [.sortedKeys(limit: 10, after: nil)])
            #expect(try CashewParser.parse(#"keys sorted limit 5 after "bob""#) == [.sortedKeys(limit: 5, after: "bob")])
            #expect(try CashewParser.parse(#"keys sorted after "z""#) == [.sortedKeys(limit: nil, after: "z")])
        }

        @Test("Parses values and values sorted")
        func testParseValues() throws {
            #expect(try CashewParser.parse("values") == [.values])
            #expect(try CashewParser.parse("values sorted") == [.sortedValues(limit: nil, after: nil)])
            #expect(try CashewParser.parse("values sorted limit 3") == [.sortedValues(limit: 3, after: nil)])
        }

        @Test("Parses count and contains")
        func testParseCountContains() throws {
            #expect(try CashewParser.parse("count") == [.count])
            #expect(try CashewParser.parse(#"contains "alice""#) == [.contains("alice")])
        }

        @Test("Parses insert, update, set, delete")
        func testParseTransforms() throws {
            #expect(try CashewParser.parse(#"insert "alice" = "engineer""#) == [.insert(key: "alice", value: "engineer")])
            #expect(try CashewParser.parse(#"update "alice" = "lead""#) == [.update(key: "alice", value: "lead")])
            #expect(try CashewParser.parse(#"set "alice" = "cto""#) == [.set(key: "alice", value: "cto")])
            #expect(try CashewParser.parse(#"delete "alice""#) == [.delete("alice")])
        }

        @Test("Parses append, first, last")
        func testParseArrayOps() throws {
            #expect(try CashewParser.parse(#"append "hello""#) == [.append("hello")])
            #expect(try CashewParser.parse("first") == [.first])
            #expect(try CashewParser.parse("last") == [.last])
        }

        @Test("Parses pipeline with pipe operator")
        func testParsePipeline() throws {
            let exprs = try CashewParser.parse(#"insert "a" = "1" | insert "b" = "2" | keys sorted"#)
            #expect(exprs == [
                .insert(key: "a", value: "1"),
                .insert(key: "b", value: "2"),
                .sortedKeys(limit: nil, after: nil)
            ])
        }

        @Test("Parses command aliases")
        func testAliases() throws {
            #expect(try CashewParser.parse("members") == [.keys])
            #expect(try CashewParser.parse("size") == [.count])
            #expect(try CashewParser.parse(#"has "x""#) == [.contains("x")])
            #expect(try CashewParser.parse(#"add "x" = "y""#) == [.insert(key: "x", value: "y")])
            #expect(try CashewParser.parse(#"remove "x""#) == [.delete("x")])
            #expect(try CashewParser.parse(#"put "x" = "y""#) == [.set(key: "x", value: "y")])
        }

        @Test("Case insensitive commands")
        func testCaseInsensitive() throws {
            #expect(try CashewParser.parse("COUNT") == [.count])
            #expect(try CashewParser.parse("Keys Sorted") == [.sortedKeys(limit: nil, after: nil)])
        }

        @Test("Supports single-quoted strings")
        func testSingleQuotes() throws {
            #expect(try CashewParser.parse("get 'alice'") == [.get("alice")])
        }

        @Test("Handles escaped quotes in strings")
        func testEscapedQuotes() throws {
            let exprs = try CashewParser.parse(#"get "say \"hi\"""#)
            #expect(exprs == [.get(#"say "hi""#)])
        }

        @Test("Empty input throws emptyExpression")
        func testEmptyInput() {
            #expect(throws: CashewQueryError.emptyExpression) {
                try CashewParser.parse("")
            }
            #expect(throws: CashewQueryError.emptyExpression) {
                try CashewParser.parse("   ")
            }
        }

        @Test("Unknown command throws parseError")
        func testUnknownCommand() {
            #expect(throws: CashewQueryError.self) {
                try CashewParser.parse("foobar")
            }
        }

        @Test("Unterminated string throws parseError")
        func testUnterminatedString() {
            #expect(throws: CashewQueryError.self) {
                try CashewParser.parse(#"get "unterminated"#)
            }
        }

        @Test("Empty pipeline segment throws parseError")
        func testEmptyPipelineSegment() {
            #expect(throws: CashewQueryError.self) {
                try CashewParser.parse("keys | | count")
            }
        }
    }

    @Suite("Dictionary Queries")
    struct DictionaryQueryTests {

        @Test("get returns a value")
        func testGet() throws {
            let dict = try Dict()
                .inserting(key: "alice", value: "engineer")
            let (_, result) = try dict.query(#"get "alice""#)
            #expect(result == .value("engineer"))
        }

        @Test("get missing key returns nil")
        func testGetMissing() throws {
            let dict = Dict()
            let (_, result) = try dict.query(#"get "missing""#)
            #expect(result == .value(nil))
        }

        @Test("keys returns all keys")
        func testKeys() throws {
            let dict = try Dict()
                .inserting(key: "alice", value: "1")
                .inserting(key: "bob", value: "2")
            let (_, result) = try dict.query("keys")
            if case .list(let keys) = result {
                #expect(Set(keys) == Set(["alice", "bob"]))
            } else {
                Issue.record("Expected .list result")
            }
        }

        @Test("keys sorted returns lexicographic order")
        func testKeysSorted() throws {
            let dict = try Dict()
                .inserting(key: "cherry", value: "3")
                .inserting(key: "apple", value: "1")
                .inserting(key: "banana", value: "2")
            let (_, result) = try dict.query("keys sorted")
            #expect(result == .list(["apple", "banana", "cherry"]))
        }

        @Test("keys sorted with limit and after")
        func testKeysSortedLimitAfter() throws {
            let dict = try Dict()
                .inserting(key: "a", value: "1")
                .inserting(key: "b", value: "2")
                .inserting(key: "c", value: "3")
                .inserting(key: "d", value: "4")
            let (_, result) = try dict.query(#"keys sorted limit 2 after "a""#)
            #expect(result == .list(["b", "c"]))
        }

        @Test("values sorted returns ordered entries")
        func testValuesSorted() throws {
            let dict = try Dict()
                .inserting(key: "banana", value: "yellow")
                .inserting(key: "apple", value: "red")
            let (_, result) = try dict.query("values sorted")
            #expect(result == .entries([(key: "apple", value: "red"), (key: "banana", value: "yellow")]))
        }

        @Test("count returns number of entries")
        func testCount() throws {
            let dict = try Dict()
                .inserting(key: "a", value: "1")
                .inserting(key: "b", value: "2")
            let (_, result) = try dict.query("count")
            #expect(result == .count(2))
        }

        @Test("contains returns bool")
        func testContains() throws {
            let dict = try Dict().inserting(key: "alice", value: "1")
            let (_, yes) = try dict.query(#"contains "alice""#)
            let (_, no) = try dict.query(#"contains "bob""#)
            #expect(yes == .bool(true))
            #expect(no == .bool(false))
        }
    }

    @Suite("Dictionary Transforms")
    struct DictionaryTransformTests {

        @Test("insert adds a new key")
        func testInsert() throws {
            let dict = Dict()
            let (updated, result) = try dict.query(#"insert "alice" = "engineer""#)
            #expect(result == .ok)
            #expect(try updated.get(key: "alice") == "engineer")
            #expect(updated.count == 1)
        }

        @Test("update changes an existing key")
        func testUpdate() throws {
            let dict = try Dict().inserting(key: "alice", value: "engineer")
            let (updated, _) = try dict.query(#"update "alice" = "lead""#)
            #expect(try updated.get(key: "alice") == "lead")
        }

        @Test("set inserts or updates")
        func testSet() throws {
            let dict = Dict()
            let (d1, _) = try dict.query(#"set "alice" = "engineer""#)
            #expect(try d1.get(key: "alice") == "engineer")
            let (d2, _) = try d1.query(#"set "alice" = "lead""#)
            #expect(try d2.get(key: "alice") == "lead")
            #expect(d2.count == 1)
        }

        @Test("delete removes a key")
        func testDelete() throws {
            let dict = try Dict().inserting(key: "alice", value: "1")
            let (updated, _) = try dict.query(#"delete "alice""#)
            #expect(updated.count == 0)
        }
    }

    @Suite("Pipeline")
    struct PipelineTests {

        @Test("Pipeline builds up data then queries")
        func testBuildAndQuery() throws {
            let (_, result) = try Dict().query(
                #"insert "cherry" = "3" | insert "apple" = "1" | insert "banana" = "2" | keys sorted"#
            )
            #expect(result == .list(["apple", "banana", "cherry"]))
        }

        @Test("Pipeline with transforms and count")
        func testTransformAndCount() throws {
            let (_, result) = try Dict().query(
                #"insert "a" = "1" | insert "b" = "2" | insert "c" = "3" | delete "b" | count"#
            )
            #expect(result == .count(2))
        }

        @Test("Pipeline set then get")
        func testSetThenGet() throws {
            let (_, result) = try Dict().query(
                #"set "name" = "alice" | set "name" = "bob" | get "name""#
            )
            #expect(result == .value("bob"))
        }

        @Test("Pipeline preserves data through transforms")
        func testPipelinePreservesData() throws {
            let (dict, _) = try Dict().query(
                #"insert "x" = "1" | insert "y" = "2" | insert "z" = "3""#
            )
            #expect(dict.count == 3)
            #expect(try dict.get(key: "x") == "1")
            #expect(try dict.get(key: "y") == "2")
            #expect(try dict.get(key: "z") == "3")
        }

        @Test("Long pipeline paginated query")
        func testPaginatedPipeline() throws {
            var q = (0..<20).map { String(format: #"insert "key_%02d" = "v""#, $0) }.joined(separator: " | ")
            q += #" | keys sorted limit 5"#
            let (_, result) = try Dict().query(q)
            #expect(result == .list(["key_00", "key_01", "key_02", "key_03", "key_04"]))
        }
    }

    @Suite("MerkleSet Queries")
    struct MerkleSetQueryTests {

        @Test("Insert and contains on set")
        func testSetInsertContains() throws {
            let (set, _) = try MerkleSetImpl().query(
                #"insert "alice" = "" | insert "bob" = """#
            )
            let (_, result) = try set.query(#"contains "alice""#)
            #expect(result == .bool(true))
        }

        @Test("Members via keys sorted")
        func testSetMembers() throws {
            let set = try MerkleSetImpl().insert("cherry").insert("apple").insert("banana")
            let (_, result) = try set.query("keys sorted")
            #expect(result == .list(["apple", "banana", "cherry"]))
        }

        @Test("Delete from set")
        func testSetDelete() throws {
            let set = try MerkleSetImpl().insert("a").insert("b").insert("c")
            let (updated, _) = try set.query(#"delete "b""#)
            #expect(updated.count == 2)
            let (_, result) = try updated.query(#"contains "b""#)
            #expect(result == .bool(false))
        }
    }

    @Suite("MerkleArray Queries")
    struct MerkleArrayQueryTests {

        @Test("Append and get at index")
        func testAppendAndGetAt() throws {
            let (arr, _) = try Arr().query(#"append "hello" | append "world""#)
            let (_, result) = try arr.query("get at 0")
            #expect(result == .value("hello"))
            let (_, result2) = try arr.query("get at 1")
            #expect(result2 == .value("world"))
        }

        @Test("First and last")
        func testFirstLast() throws {
            let arr = try Arr().append("alpha").append("beta").append("gamma")
            let (_, first) = try arr.query("first")
            #expect(first == .value("alpha"))
            let (_, last) = try arr.query("last")
            #expect(last == .value("gamma"))
        }

        @Test("Count on array")
        func testArrayCount() throws {
            let arr = try Arr().append("a").append("b").append("c")
            let (_, result) = try arr.query("count")
            #expect(result == .count(3))
        }

        @Test("Append pipeline then count")
        func testAppendPipelineCount() throws {
            let (_, result) = try Arr().query(
                #"append "x" | append "y" | append "z" | count"#
            )
            #expect(result == .count(3))
        }

        @Test("Array operations throw on dictionary")
        func testArrayOpsOnDict() {
            let dict = Dict()
            #expect(throws: CashewQueryError.self) {
                try dict.query("get at 0")
            }
            #expect(throws: CashewQueryError.self) {
                try dict.query("first")
            }
            #expect(throws: CashewQueryError.self) {
                try dict.query(#"append "x""#)
            }
        }
    }

    @Suite("Error Handling")
    struct ErrorHandlingTests {

        @Test("Insert duplicate key throws")
        func testInsertDuplicate() {
            let dict = try! Dict().inserting(key: "alice", value: "1")
            #expect(throws: (any Error).self) {
                try dict.query(#"insert "alice" = "2""#)
            }
        }

        @Test("Update missing key throws")
        func testUpdateMissing() {
            #expect(throws: (any Error).self) {
                try Dict().query(#"update "missing" = "value""#)
            }
        }

        @Test("Delete missing key throws")
        func testDeleteMissing() {
            #expect(throws: (any Error).self) {
                try Dict().query(#"delete "missing""#)
            }
        }
    }

    @Suite("Result Description")
    struct ResultDescriptionTests {

        @Test("Result descriptions are human-readable")
        func testDescriptions() {
            #expect(CashewResult.value("hello").description == "hello")
            #expect(CashewResult.value(nil).description == "nil")
            #expect(CashewResult.bool(true).description == "true")
            #expect(CashewResult.count(42).description == "42")
            #expect(CashewResult.list(["a", "b"]).description == "a\nb")
            #expect(CashewResult.ok.description == "ok")
            #expect(CashewResult.entries([(key: "a", value: "1")]).description == "a: 1")
        }
    }

    @Suite("Plan Compilation")
    struct PlanCompilationTests {

        @Test("Consecutive inserts batch into one transform step")
        func testBatchInserts() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | insert "b" = "2" | insert "c" = "3""#
            )
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 1)
            if case .transform(let trie) = plan.steps[0] {
                #expect(trie.get(["a"]) == .insert("1"))
                #expect(trie.get(["b"]) == .insert("2"))
                #expect(trie.get(["c"]) == .insert("3"))
            } else {
                Issue.record("Expected .transform step")
            }
        }

        @Test("Mixed insert/update/delete batch into one step")
        func testBatchMixed() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | update "b" = "2" | delete "c""#
            )
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 1)
            if case .transform(let trie) = plan.steps[0] {
                #expect(trie.get(["a"]) == .insert("1"))
                #expect(trie.get(["b"]) == .update("2"))
                #expect(trie.get(["c"]) == .delete)
            } else {
                Issue.record("Expected .transform step")
            }
        }

        @Test("Read flushes pending transforms into separate steps")
        func testReadFlushes() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | insert "b" = "2" | keys sorted"#
            )
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 2)
            if case .transform = plan.steps[0] {} else {
                Issue.record("Expected .transform as first step")
            }
            if case .evaluate(.sortedKeys) = plan.steps[1] {} else {
                Issue.record("Expected .evaluate(.sortedKeys) as second step")
            }
        }

        @Test("Same key used twice splits into two transform batches")
        func testConflictingSplits() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | insert "b" = "2" | delete "a""#
            )
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 2)
            if case .transform(let t1) = plan.steps[0] {
                #expect(t1.get(["a"]) == .insert("1"))
                #expect(t1.get(["b"]) == .insert("2"))
            } else {
                Issue.record("Expected first .transform step")
            }
            if case .transform(let t2) = plan.steps[1] {
                #expect(t2.get(["a"]) == .delete)
            } else {
                Issue.record("Expected second .transform step")
            }
        }

        @Test("Set flushes pending transforms and becomes evaluate step")
        func testSetFlushesBatch() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | set "b" = "2""#
            )
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 2)
            if case .transform = plan.steps[0] {} else {
                Issue.record("Expected .transform step")
            }
            if case .evaluate(.set(let key, let value)) = plan.steps[1] {
                #expect(key == "b")
                #expect(value == "2")
            } else {
                Issue.record("Expected .evaluate(.set) step")
            }
        }

        @Test("Pure reads produce only evaluate steps")
        func testPureReads() throws {
            let exprs = try CashewParser.parse(#"count | keys sorted | get "x""#)
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 3)
            for step in plan.steps {
                if case .evaluate = step {} else {
                    Issue.record("Expected all steps to be .evaluate")
                }
            }
        }
    }

    @Suite("Resolution Paths")
    struct ResolutionPathTests {

        @Test("get builds targeted resolution path")
        func testGetResolutionPath() throws {
            let exprs = try CashewParser.parse(#"get "alice""#)
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get(["alice"]) == .targeted)
        }

        @Test("contains builds targeted resolution path")
        func testContainsResolutionPath() throws {
            let exprs = try CashewParser.parse(#"contains "key""#)
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get(["key"]) == .targeted)
        }

        @Test("keys sorted builds recursive resolution")
        func testKeysSortedResolution() throws {
            let exprs = try CashewParser.parse("keys sorted")
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get([""]) == .recursive)
        }

        @Test("count builds list resolution")
        func testCountResolution() throws {
            let exprs = try CashewParser.parse("count")
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get([""]) == .list)
        }

        @Test("setKey builds targeted resolution for key existence check")
        func testSetKeyResolution() throws {
            let exprs = try CashewParser.parse(#"set "mykey" = "val""#)
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get(["mykey"]) == .targeted)
        }

        @Test("Multiple reads merge resolution paths")
        func testMergedResolution() throws {
            let exprs = try CashewParser.parse(#"get "a" | get "b" | contains "c""#)
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get(["a"]) == .targeted)
            #expect(paths.get(["b"]) == .targeted)
            #expect(paths.get(["c"]) == .targeted)
        }

        @Test("Transform-only pipeline produces empty resolution paths")
        func testTransformOnlyNoResolution() throws {
            let exprs = try CashewParser.parse(
                #"insert "a" = "1" | insert "b" = "2""#
            )
            let plan = CashewPlan.compile(exprs)
            let paths = plan.resolutionPaths()
            #expect(paths.get(["a"]) == nil)
            #expect(paths.get(["b"]) == nil)
        }
    }

    @Suite("Async Query with Resolution")
    struct AsyncQueryTests {

        @Test("Async query resolves then reads")
        func testAsyncQueryResolve() async throws {
            let dict = try Dict()
                .inserting(key: "alice", value: "engineer")
                .inserting(key: "bob", value: "designer")

            let store = TestStoreFetcher()
            let header = HeaderImpl(node: dict)
            try header.storeRecursively(storer: store)

            let unresolved = HeaderImpl<Dict>(rawCID: header.rawCID)
            let resolvedHeader = try await unresolved.resolveRecursive(fetcher: store)
            let resolvedDict = resolvedHeader.node!

            let (_, result) = try await resolvedDict.query(#"get "alice""#, fetcher: store)
            #expect(result == .value("engineer"))
        }

        @Test("Async query with pipeline: transforms then read")
        func testAsyncPipelineTransformRead() async throws {
            let dict = try Dict()
                .inserting(key: "existing", value: "old")

            let store = TestStoreFetcher()
            let header = HeaderImpl(node: dict)
            try header.storeRecursively(storer: store)

            let resolved = try await HeaderImpl<Dict>(rawCID: header.rawCID)
                .resolveRecursive(fetcher: store).node!

            let (updated, result) = try await resolved.query(
                #"insert "new" = "fresh" | keys sorted"#,
                fetcher: store
            )
            #expect(result == .list(["existing", "new"]))
            #expect(updated.count == 2)
        }
    }

    @Suite("Batched Transform Correctness")
    struct BatchedTransformTests {

        @Test("Batched inserts produce same result as sequential inserts")
        func testBatchedMatchesSequential() throws {
            let sequential = try Dict()
                .inserting(key: "a", value: "1")
                .inserting(key: "b", value: "2")
                .inserting(key: "c", value: "3")

            let (batched, _) = try Dict().query(
                #"insert "a" = "1" | insert "b" = "2" | insert "c" = "3""#
            )

            #expect(batched.count == sequential.count)
            #expect(try batched.get(key: "a") == "1")
            #expect(try batched.get(key: "b") == "2")
            #expect(try batched.get(key: "c") == "3")
            #expect(HeaderImpl(node: batched).rawCID == HeaderImpl(node: sequential).rawCID)
        }

        @Test("Batched transforms produce same CID as manual ArrayTrie transform")
        func testBatchedMatchesArrayTrie() throws {
            let dict = try Dict()
                .inserting(key: "a", value: "old_a")
                .inserting(key: "b", value: "old_b")
                .inserting(key: "c", value: "old_c")

            var trie = ArrayTrie<Transform>()
            trie.set(["a"], value: .update("new_a"))
            trie.set(["b"], value: .delete)
            let manual = try dict.transform(transforms: trie)!

            let (queried, _) = try dict.query(
                #"update "a" = "new_a" | delete "b""#
            )

            #expect(HeaderImpl(node: queried).rawCID == HeaderImpl(node: manual).rawCID)
        }

        @Test("20 inserts batch into single transform step")
        func testLargeBatch() throws {
            let exprs = (0..<20).map {
                CashewExpression.insert(key: "key_\($0)", value: "val_\($0)")
            }
            let plan = CashewPlan.compile(exprs)
            #expect(plan.steps.count == 1)

            let dict = Dict()
            let (result, _) = try dict.execute(plan: plan)
            #expect(result.count == 20)
        }
    }

    @Suite("Multi-Round Dictionary Workflows")
    struct MultiRoundDictionaryTests {

        @Test("Build a user directory over multiple rounds")
        func testUserDirectory() throws {
            let (d1, _) = try Dict().query(
                #"insert "alice" = "engineer" | insert "bob" = "designer" | insert "carol" = "manager""#
            )
            #expect(d1.count == 3)

            let (d2, _) = try d1.query(#"update "alice" = "senior engineer" | insert "dave" = "intern""#)
            #expect(d2.count == 4)
            #expect(try d2.get(key: "alice") == "senior engineer")

            let (d3, result) = try d2.query(#"delete "bob" | keys sorted"#)
            #expect(result == .list(["alice", "carol", "dave"]))
            #expect(d3.count == 3)

            let (_, lookup) = try d3.query(#"get "carol""#)
            #expect(lookup == .value("manager"))
        }

        @Test("Repeated set on same key across rounds")
        func testRepeatedSet() throws {
            let (d1, _) = try Dict().query(#"set "counter" = "0""#)
            let (d2, _) = try d1.query(#"set "counter" = "1""#)
            let (d3, _) = try d2.query(#"set "counter" = "2""#)
            let (_, result) = try d3.query(#"get "counter""#)
            #expect(result == .value("2"))
            #expect(d3.count == 1)
        }

        @Test("Interleaved transforms and reads across multiple queries")
        func testInterleavedTransformsReads() throws {
            let (d1, r1) = try Dict().query(
                #"insert "a" = "1" | insert "b" = "2" | count"#
            )
            #expect(r1 == .count(2))

            let (d2, r2) = try d1.query(
                #"insert "c" = "3" | delete "a" | keys sorted"#
            )
            #expect(r2 == .list(["b", "c"]))

            let (d3, r3) = try d2.query(
                #"update "b" = "20" | insert "d" = "4" | values sorted"#
            )
            #expect(r3 == .entries([
                (key: "b", value: "20"),
                (key: "c", value: "3"),
                (key: "d", value: "4")
            ]))
            #expect(d3.count == 3)
        }

        @Test("CID changes with each mutation round")
        func testCIDEvolution() throws {
            let d0 = Dict()
            let (d1, _) = try d0.query(#"insert "x" = "1""#)
            let (d2, _) = try d1.query(#"insert "y" = "2""#)
            let (d3, _) = try d2.query(#"delete "x""#)

            let cid0 = HeaderImpl(node: d0).rawCID
            let cid1 = HeaderImpl(node: d1).rawCID
            let cid2 = HeaderImpl(node: d2).rawCID
            let cid3 = HeaderImpl(node: d3).rawCID

            #expect(cid0 != cid1)
            #expect(cid1 != cid2)
            #expect(cid2 != cid3)
        }

        @Test("Paginated cursor across multiple query rounds")
        func testPaginatedCursor() throws {
            let insertParts = (0..<26).map { i -> String in
                let letter = String(UnicodeScalar(UInt8(65 + i)))
                return #"insert "\#(letter)" = "\#(i)""#
            }
            let (dict, _) = try Dict().query(insertParts.joined(separator: " | "))
            #expect(dict.count == 26)

            let (_, page1) = try dict.query("keys sorted limit 10")
            guard case .list(let p1) = page1 else { Issue.record("Expected list"); return }
            #expect(p1.count == 10)
            #expect(p1.first == "A")

            let lastKey = p1.last!
            let (_, page2) = try dict.query(#"keys sorted limit 10 after "\#(lastKey)""#)
            guard case .list(let p2) = page2 else { Issue.record("Expected list"); return }
            #expect(p2.count == 10)
            #expect(p2.first! > lastKey)

            let lastKey2 = p2.last!
            let (_, page3) = try dict.query(#"keys sorted limit 10 after "\#(lastKey2)""#)
            guard case .list(let p3) = page3 else { Issue.record("Expected list"); return }
            #expect(p3.count == 6)

            let all = p1 + p2 + p3
            #expect(all.count == 26)
            #expect(all == all.sorted())
        }

        @Test("Large pipeline: 50 inserts, selective deletes, then query")
        func testLargePipeline() throws {
            let inserts = (0..<50).map { i in
                #"insert "item_\#(String(format: "%02d", i))" = "\#(i)""#
            }.joined(separator: " | ")
            let (d1, _) = try Dict().query(inserts)
            #expect(d1.count == 50)

            let deletes = stride(from: 0, to: 50, by: 2).map { i in
                #"delete "item_\#(String(format: "%02d", i))""#
            }.joined(separator: " | ")
            let (d2, _) = try d1.query(deletes)
            #expect(d2.count == 25)

            let (_, result) = try d2.query("keys sorted limit 5")
            guard case .list(let keys) = result else { Issue.record("Expected list"); return }
            #expect(keys == ["item_01", "item_03", "item_05", "item_07", "item_09"])
        }
    }

    @Suite("Multi-Round MerkleArray Workflows")
    struct MultiRoundArrayTests {

        @Test("Build array over multiple rounds, verify order")
        func testArrayBuildUp() throws {
            let (a1, _) = try Arr().query(#"append "first" | append "second""#)
            let (a2, _) = try a1.query(#"append "third""#)
            let (a3, _) = try a2.query(#"append "fourth" | append "fifth""#)

            #expect(a3.count == 5)
            let (_, first) = try a3.query("first")
            #expect(first == .value("first"))
            let (_, last) = try a3.query("last")
            #expect(last == .value("fifth"))

            for i in 0..<5 {
                let (_, val) = try a3.query("get at \(i)")
                let expected = ["first", "second", "third", "fourth", "fifth"][i]
                #expect(val == .value(expected))
            }
        }

        @Test("Array append then count across rounds")
        func testArrayCountAcrossRounds() throws {
            let (a1, r1) = try Arr().query(#"append "a" | append "b" | count"#)
            #expect(r1 == .count(2))

            let (a2, r2) = try a1.query(#"append "c" | append "d" | append "e" | count"#)
            #expect(r2 == .count(5))

            let (_, r3) = try a2.query("count")
            #expect(r3 == .count(5))
        }

        @Test("Array CID changes with appends")
        func testArrayCIDEvolution() throws {
            let a0 = Arr()
            let (a1, _) = try a0.query(#"append "x""#)
            let (a2, _) = try a1.query(#"append "y""#)

            let cid0 = HeaderImpl(node: a0).rawCID
            let cid1 = HeaderImpl(node: a1).rawCID
            let cid2 = HeaderImpl(node: a2).rawCID

            #expect(cid0 != cid1)
            #expect(cid1 != cid2)
        }
    }

    @Suite("Multi-Round MerkleSet Workflows")
    struct MultiRoundSetTests {

        typealias MSet = MerkleSetImpl

        @Test("Build set over multiple rounds, check membership")
        func testSetBuildUp() throws {
            let (s1, _) = try MSet().query(#"insert "apple" = "" | insert "banana" = """#)
            let (s2, _) = try s1.query(#"insert "cherry" = "" | insert "date" = """#)

            #expect(s2.count == 4)
            let (_, has) = try s2.query(#"contains "cherry""#)
            #expect(has == .bool(true))
            let (_, missing) = try s2.query(#"contains "elderberry""#)
            #expect(missing == .bool(false))
        }

        @Test("Set insert and delete across rounds")
        func testSetInsertDelete() throws {
            let (s1, _) = try MSet().query(
                #"insert "a" = "" | insert "b" = "" | insert "c" = "" | insert "d" = """#
            )
            #expect(s1.count == 4)

            let (s2, _) = try s1.query(#"delete "b" | delete "d""#)
            #expect(s2.count == 2)

            let (_, result) = try s2.query("keys sorted")
            #expect(result == .list(["a", "c"]))
        }

        @Test("Set CID is deterministic regardless of insertion order")
        func testSetCIDDeterminism() throws {
            let (s1, _) = try MSet().query(
                #"insert "x" = "" | insert "y" = "" | insert "z" = """#
            )
            let (s2, _) = try MSet().query(
                #"insert "z" = "" | insert "x" = "" | insert "y" = """#
            )
            #expect(HeaderImpl(node: s1).rawCID == HeaderImpl(node: s2).rawCID)
        }
    }

    @Suite("Content Addressability Through Queries")
    struct ContentAddressabilityTests {

        @Test("Same operations produce same CID regardless of pipeline grouping")
        func testPipelineGroupingInvariance() throws {
            let (d1, _) = try Dict().query(
                #"insert "a" = "1" | insert "b" = "2" | insert "c" = "3""#
            )
            var d2 = Dict()
            (d2, _) = try d2.query(#"insert "a" = "1""#)
            (d2, _) = try d2.query(#"insert "b" = "2""#)
            (d2, _) = try d2.query(#"insert "c" = "3""#)

            #expect(HeaderImpl(node: d1).rawCID == HeaderImpl(node: d2).rawCID)
        }

        @Test("Query via set produces same CID as insert for new key")
        func testSetMatchesInsertForNew() throws {
            let (d1, _) = try Dict().query(#"insert "key" = "val""#)
            let (d2, _) = try Dict().query(#"set "key" = "val""#)
            #expect(HeaderImpl(node: d1).rawCID == HeaderImpl(node: d2).rawCID)
        }

        @Test("Query via set produces same CID as update for existing key")
        func testSetMatchesUpdateForExisting() throws {
            let base = try Dict().inserting(key: "key", value: "old")
            let (d1, _) = try base.query(#"update "key" = "new""#)
            let (d2, _) = try base.query(#"set "key" = "new""#)
            #expect(HeaderImpl(node: d1).rawCID == HeaderImpl(node: d2).rawCID)
        }

        @Test("Delete then re-insert same key/value restores original CID")
        func testDeleteReinsertRestoresCID() throws {
            let (original, _) = try Dict().query(#"insert "a" = "1" | insert "b" = "2""#)
            let cidOriginal = HeaderImpl(node: original).rawCID

            let (deleted, _) = try original.query(#"delete "b""#)
            let cidDeleted = HeaderImpl(node: deleted).rawCID
            #expect(cidOriginal != cidDeleted)

            let (restored, _) = try deleted.query(#"insert "b" = "2""#)
            let cidRestored = HeaderImpl(node: restored).rawCID
            #expect(cidOriginal == cidRestored)
        }
    }

    @Suite("Store Round-Trip with Queries")
    struct StoreRoundTripTests {

        @Test("Store, resolve, then query modified dictionary")
        func testStoreResolveQuery() async throws {
            let (dict, _) = try Dict().query(
                #"insert "name" = "alice" | insert "role" = "engineer" | insert "team" = "platform""#
            )
            let store = TestStoreFetcher()
            let header = HeaderImpl(node: dict)
            try header.storeRecursively(storer: store)

            let resolved = try await HeaderImpl<Dict>(rawCID: header.rawCID)
                .resolveRecursive(fetcher: store).node!

            let (_, result) = try await resolved.query(
                #"update "role" = "lead" | insert "level" = "senior" | keys sorted"#,
                fetcher: store
            )
            #expect(result == .list(["level", "name", "role", "team"]))
        }

        @Test("Multiple store-resolve-query cycles")
        func testMultipleCycles() async throws {
            let store = TestStoreFetcher()

            let (d1, _) = try Dict().query(#"insert "a" = "1" | insert "b" = "2""#)
            let h1 = HeaderImpl(node: d1)
            try h1.storeRecursively(storer: store)

            let r1 = try await HeaderImpl<Dict>(rawCID: h1.rawCID)
                .resolveRecursive(fetcher: store).node!
            let (d2, _) = try r1.query(#"insert "c" = "3" | delete "a""#)

            let h2 = HeaderImpl(node: d2)
            try h2.storeRecursively(storer: store)

            let r2 = try await HeaderImpl<Dict>(rawCID: h2.rawCID)
                .resolveRecursive(fetcher: store).node!
            let (_, result) = try r2.query("keys sorted")
            #expect(result == .list(["b", "c"]))
        }
    }
}
