import ArrayTrie

func evaluateExpression<D: MerkleDictionary>(
    _ dict: D,
    _ expression: CashewExpression
) throws -> (D, CashewResult) where D.ValueType: LosslessStringConvertible {
    switch expression {
    case .get(let key):
        let value = try dict.get(key: key)
        return (dict, .value(value.map { "\($0)" }))

    case .keys:
        return (dict, .list(Array(try dict.allKeys())))

    case .sortedKeys(let limit, let after):
        return (dict, .list(try dict.sortedKeys(limit: limit ?? .max, after: after)))

    case .values:
        let kvs = try dict.allKeysAndValues()
        return (dict, .entries(kvs.map { (key: $0.key, value: "\($0.value)") }))

    case .sortedValues(let limit, let after):
        let pairs = try dict.sortedKeysAndValues(limit: limit ?? .max, after: after)
        return (dict, .entries(pairs.map { (key: $0.key, value: "\($0.value)") }))

    case .count:
        return (dict, .count(dict.count))

    case .contains(let key):
        return (dict, .bool(try dict.get(key: key) != nil))

    case .set(let key, let value):
        guard let typed = D.ValueType(value) else {
            throw CashewQueryError.invalidValue(value)
        }
        let op: Transform = try dict.get(key: key) != nil ? .update(value) : .insert(value)
        var trie = ArrayTrie<Transform>()
        trie.set([key], value: op)
        guard let result = try dict.transform(transforms: trie) else {
            return (D(), .ok)
        }
        return (result, .ok)

    case .insert, .update, .delete:
        throw CashewQueryError.unsupportedOperation("Transforms should be compiled into ArrayTrie steps")

    case .getAt, .first, .last, .append:
        throw CashewQueryError.unsupportedOperation("Array operations require MerkleArray")
    }
}

public extension MerkleDictionary where ValueType: LosslessStringConvertible {
    func query(_ input: String) throws -> (Self, CashewResult) {
        let expressions = try CashewParser.parse(input)
        let plan = CashewPlan.compile(expressions)
        return try execute(plan: plan)
    }

    func execute(plan: CashewPlan) throws -> (Self, CashewResult) {
        var current = self
        var lastResult: CashewResult = .ok

        for step in plan.steps {
            switch step {
            case .transform(let trie):
                if let transformed = try current.transform(transforms: trie) {
                    current = transformed
                } else {
                    current = Self()
                }
                lastResult = .ok

            case .evaluate(let expr):
                let (next, result) = try evaluateExpression(current, expr)
                current = next
                lastResult = result
            }
        }

        return (current, lastResult)
    }

    func execute(_ expression: CashewExpression) throws -> (Self, CashewResult) {
        let plan = CashewPlan.compile([expression])
        return try execute(plan: plan)
    }

    func query(_ input: String, fetcher: Fetcher) async throws -> (Self, CashewResult) {
        let expressions = try CashewParser.parse(input)
        let plan = CashewPlan.compile(expressions)
        let paths = plan.resolutionPaths()
        let resolved = try await self.resolve(paths: paths, fetcher: fetcher)
        return try resolved.execute(plan: plan)
    }
}

public extension MerkleArray where ValueType: LosslessStringConvertible {
    func query(_ input: String) throws -> (Self, CashewResult) {
        let expressions = try CashewParser.parse(input)
        let plan = CashewPlan.compile(expressions)
        return try execute(plan: plan)
    }

    func execute(plan: CashewPlan) throws -> (Self, CashewResult) {
        var current = self
        var lastResult: CashewResult = .ok

        for step in plan.steps {
            switch step {
            case .transform(let trie):
                if let transformed = try current.transform(transforms: trie) {
                    current = transformed
                } else {
                    current = Self()
                }
                lastResult = .ok

            case .evaluate(let expr):
                switch expr {
                case .getAt(let index):
                    let value = try current.get(at: index)
                    lastResult = .value(value.map { "\($0)" })

                case .first:
                    let value = try current.first()
                    lastResult = .value(value.map { "\($0)" })

                case .last:
                    let value = try current.last()
                    lastResult = .value(value.map { "\($0)" })

                case .append(let value):
                    guard let typed = ValueType(value) else {
                        throw CashewQueryError.invalidValue(value)
                    }
                    var trie = ArrayTrie<Transform>()
                    trie.set([Self.binaryKey(current.count)], value: .insert(value))
                    if let transformed = try current.transform(transforms: trie) {
                        current = transformed
                    }
                    lastResult = .ok

                default:
                    let (next, result) = try evaluateExpression(current, expr)
                    current = next
                    lastResult = result
                }
            }
        }

        return (current, lastResult)
    }

    func execute(_ expression: CashewExpression) throws -> (Self, CashewResult) {
        let plan = CashewPlan.compile([expression])
        return try execute(plan: plan)
    }

    func query(_ input: String, fetcher: Fetcher) async throws -> (Self, CashewResult) {
        let expressions = try CashewParser.parse(input)
        let plan = CashewPlan.compile(expressions)
        let paths = plan.resolutionPaths()
        let resolved = try await self.resolve(paths: paths, fetcher: fetcher)
        return try resolved.execute(plan: plan)
    }
}
