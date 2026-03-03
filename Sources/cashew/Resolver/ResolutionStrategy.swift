/**
 * Resolution strategies define how MerkleDictionary data structures should be resolved
 * when fetching content from storage during deserialization operations.
 */
public enum ResolutionStrategy: Int, Codable {
    /// Resolves only the specific targeted path without loading child nodes
    case targeted = 1
    
    /// Recursively resolves all child nodes and their content by fully loading
    /// the entire subtree structure from storage
    case recursive
    
    /**
     * List resolution strategy resolves dictionary structures for traversal without 
     * automatically resolving downstream address values (IPFS links).
     * 
     * When .list strategy is applied to dictionary values that are addresses:
     * 1. **Address Resolution**: Resolves the address (IPFS link) to load the dictionary structure
     * 2. **Structure Loading**: Loads the radix tree node structure to enable key-based lookup
     * 3. **Selective Resolution**: Similar to recursive resolution but stops at the first level -
     *    does NOT automatically resolve nested addresses/links within the loaded dictionary
     * 4. **Prefix Matching**: Enables efficient lookup of keys with common prefixes 
     *    (e.g., path ["Fo"] matches keys "Foo", "Foobar")
     * 5. **Unresolved References**: Nested dictionary values remain as unresolved addresses,
     *    meaning their `.node` property will be nil until explicitly resolved
     * 
     * Key difference from .recursive:
     * - .recursive: Resolves addresses AND all their nested content recursively
     * - .list: Resolves addresses but leaves nested addresses unresolved for lazy loading
     * 
     * This strategy is particularly useful for:
     * - Directory-like operations where you need to list entries without loading their content
     * - Browsing large nested structures efficiently
     * - Cases where you want to resolve structure for navigation but defer expensive nested resolution
     * 
     * Example: With .list resolution, you can access dictionary keys and traverse the structure,
     * but nested dictionary values will have `node == nil` until explicitly resolved.
     */
    case list
}
