public protocol RadixHeader: Header where NodeType: RadixNode, NodeType.ChildType == Self { }
