# Swift Similarity Optimization TODO

## Bloom Filter Performance Optimization Implementation Plan

### ✅ Phase 1: ASTNodeFingerprint Implementation (COMPLETED)
- [x] Implement ASTNodeFingerprint struct with node type counts and structural metrics
- [x] Add distance and similarity calculation methods
- [x] Implement TreeNode extension for fingerprint extraction
- [x] Add hash value generation for bloom filter support
- [x] Create comprehensive test suite
- [x] Commit: "Implement ASTNodeFingerprint for optimization Phase 1"

### ✅ Phase 2: BloomFilter Implementation (COMPLETED)
- [x] Implement BloomFilter struct with configurable size and hash functions
- [x] Add insertion and lookup methods
- [x] Implement multiple hash functions using different seeds
- [x] Add similarity checking methods between fingerprints
- [x] Create BloomFilterTests with test cases for various scenarios
- [x] Commit: "Implement BloomFilter for optimization Phase 2"

### ✅ Phase 3: PrefilteringEngine Implementation (COMPLETED)
- [x] Implement PrefilteringEngine class
- [x] Add candidate pair selection using bloom filter
- [x] Implement fingerprint-based pre-screening
- [x] Add configurable thresholds and size ratio checks
- [x] Create PrefilteringEngineTests
- [x] Commit: "Implement PrefilteringEngine for optimization Phase 3"

### ✅ Phase 4: PerformanceOptimizedCalculator Implementation (COMPLETED)
- [x] Implement PerformanceOptimizedCalculator class
- [x] Integrate prefiltering engine with similarity calculator
- [x] Add parallel processing support with DispatchQueue
- [x] Implement progressive similarity calculation with progress reporting
- [x] Add performance monitoring and statistics
- [x] Implement configurable performance levels (aggressive/balanced/conservative)
- [x] Create PerformanceOptimizedCalculatorTests
- [x] Commit: "Implement PerformanceOptimizedCalculator for optimization Phase 4"

### ✅ Phase 5: ScanCommand Integration (COMPLETED)
- [x] Add optimization configuration to ScanCommand
- [x] Implement automatic selection between optimized and standard calculation
- [x] Add command-line options for optimization settings (--optimization, --progress, --threads, --stats)
- [x] Implement performance statistics display with detailed metrics
- [x] Add progress reporting with real-time updates
- [x] Implement backward compatibility with legacy calculation mode
- [x] Test integration with existing CLI functionality
- [x] Commit: "Integrate optimization into ScanCommand for Phase 5"

### 🔄 Phase 6: Performance Testing and Benchmarking
- [ ] Create performance benchmarking test suite
- [ ] Test with various dataset sizes (100, 1000, 5000+ elements)
- [ ] Measure and compare execution times between standard and optimized calculation
- [ ] Create benchmark reports with performance metrics
- [ ] Validate accuracy vs speed trade-offs for different optimization levels

## SwiftSyntax Node Coverage Enhancement

**Goal**: Improve AST representation accuracy to reduce false-positive similarity detection

**Current Problem**: 
- ✅ 20+ node types supported with semantic labels
- ⚠️ Issue: Basic similarity still 99.2% for different functions (target: 80-90%)
- ⚠️ Many empty labels causing insufficient differentiation
- ⚠️ Duplicate MemberAccessExprSyntax definitions in ASTToTreeConverter

### 🔥 Priority 1: Basic Declaration Types (High Priority)
- [ ] Add StructDeclSyntax with member count and inheritance info
- [ ] Add ClassDeclSyntax with inheritance and modifier detection
- [ ] Add EnumDeclSyntax with case count and associated values
- [ ] Add ProtocolDeclSyntax with requirement count
- [ ] Add InitializerDeclSyntax with parameter signature
- [ ] Add PropertyDeclSyntax with getter/setter info
- [ ] Fix duplicate MemberAccessExprSyntax definitions in createSemanticLabel
- [ ] Add comprehensive control flow: IfStmtSyntax, WhileStmtSyntax, GuardStmtSyntax, SwitchStmtSyntax
- [ ] Test similarity detection improvement (target: reduce false positives by 50%)

### ⚡ Priority 2: Expression and Literal Types (Medium Priority)  
- [ ] Add binary/unary operators with operator type detection
- [ ] Add literal expressions (String, Integer, Boolean, Nil) with value info
- [ ] Add collection expressions (Array, Dictionary) with element count
- [ ] Add ClosureExprSyntax with parameter and capture analysis
- [ ] Add type expressions (Array, Dictionary, Optional, Tuple types)
- [ ] Implement operator precedence and associativity info
- [ ] Test with complex expression similarity scenarios

### 🚀 Priority 3: Advanced Language Features (Low Priority)
- [ ] Add async/await support (TryExprSyntax, AwaitExprSyntax)
- [ ] Add error handling (DoStmtSyntax, ThrowStmtSyntax, CatchClauseSyntax)
- [ ] Add pattern matching (TuplePattern, WildcardPattern, OptionalPattern)
- [ ] Add generics support (GenericArgument, WhereClause)
- [ ] Add access control and modifiers
- [ ] Add comprehensive attribute and annotation support

**Success Criteria**:
- Basic similarity for different functions: < 90%
- Advanced similarity overall: < 85% 
- Maintain performance within 10% of current speed
- Zero false 100% similarity cases
- Comprehensive test coverage for all new node types

**Implementation Strategy**:
- Incremental implementation with immediate testing after each priority group
- Benchmark similarity detection accuracy after each major addition
- Maintain backward compatibility with existing functionality
- Use semantic information (names, counts, types) rather than just structure
- Focus on eliminating empty labels and improving node differentiation

---

## Implementation Notes

### Expected Performance Improvements
- **Before**: O(n²) comparisons for n elements
- **After**: O(n + k) where k << n² (candidate pairs only)
- **Target**: 10x-100x speedup for large datasets (1000+ elements)

### Key Components Structure
```
Sources/swift-similarity/Optimization/
├── ASTNodeFingerprint.swift     ✅ DONE
├── BloomFilter.swift            ✅ DONE
├── PrefilteringEngine.swift     ✅ DONE
└── PerformanceOptimizedCalculator.swift ✅ DONE
```

### Configuration Parameters
- Bloom filter false positive rate: 0.1 (default)
- Fingerprint similarity threshold: 0.7 (default)
- Size ratio threshold: 0.3 (default)
- Optimization activation threshold: 500+ elements

### Testing Strategy
- Unit tests for each component
- Integration tests with existing similarity calculation
- Performance benchmarks with real Swift code
- Regression tests to ensure accuracy is maintained
