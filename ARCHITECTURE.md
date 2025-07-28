# swift-similarity Architecture

## Overview

swift-similarity is a Swift tool for detecting similar code patterns using tree edit distance algorithms. The system uses SwiftSyntax for AST parsing and implements the APTED (All-Pairs Tree Edit Distance) algorithm with performance optimizations including Bloom filters and parallel processing.

## System Pipeline

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Swift Files   │───▶│  SwiftSyntax     │───▶│   AST Structures    │
│   (.swift)      │    │  Parser          │    │                     │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                                           │
                                                           ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ Similar Pairs   │◀───│  APTED Algorithm │◀───│   Tree Nodes        │
│   (Results)     │    │  (Edit Distance) │    │   (Generic Tree)    │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
          │                       ▲                       ▲
          ▼                       │                       │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ Output Format   │    │ Similarity       │    │ Code Elements       │
│ (Text/JSON)     │    │ Calculator       │    │ (Function/Struct)   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                  ▲                       ▲
                                  │                       │
                       ┌──────────────────┐    ┌─────────────────────┐
                       │ Optimization     │    │ Element Extractor   │
                       │ (Bloom Filter)   │    │                     │
                       └──────────────────┘    └─────────────────────┘
```

## Core Components

### 1. CLI Layer (`swift-similarity-cli/`)

**ScanCommand**
- Entry point for similarity detection
- Handles command-line arguments and options
- Orchestrates the entire pipeline

**OutputFormatter**
- Formats results as text or JSON
- Provides human-readable similarity reports
- Supports code preview display

### 2. AST Processing (`Sources/swift-similarity/AST/`)

**SwiftASTParser**
- Parses Swift source files using SwiftSyntax
- Converts source code to SwiftSyntax AST structures

**ASTToTreeConverter**
- Converts SwiftSyntax AST to generic TreeNode structures
- Implements semantic labeling for 85+ SwiftSyntax node types
- Preserves essential structural and semantic information

**CodeElementExtractor**
- Extracts specific code elements (functions, structs, classes, enums)
- Provides precise line number tracking
- Generates code previews for similarity results

### 3. Algorithm Layer (`Sources/swift-similarity/Algorithm/`)

**APTED (All-Pairs Tree Edit Distance)**
- Implements tree edit distance calculation
- Supports custom operation costs (insert, delete, substitute)
- Core algorithm for measuring structural similarity

### 4. Similarity Engine (`Sources/swift-similarity/Calculator/`)

**SimilarityCalculator**
- Converts edit distance to normalized similarity scores (0.0-1.0)
- Configurable similarity thresholds
- Handles basic similarity calculations

**AdvancedSimilarityMetrics**
- Combines multiple similarity dimensions:
  - Structural similarity (tree shape)
  - Label similarity (node content)
  - Depth similarity (tree depth patterns)
- Uses Jaccard similarity for set-based comparisons
- Configurable weight combinations

### 5. Optimization Layer (`Sources/swift-similarity/Optimization/`)

**PerformanceOptimizedCalculator**
- High-performance similarity calculation with prefiltering
- Parallel processing using Swift Structured Concurrency
- Performance levels: aggressive, balanced, conservative
- Progress reporting and performance statistics

**PrefilteringEngine**
- Reduces O(n²) comparisons using probabilistic filtering
- AST fingerprint-based candidate pair selection
- Configurable reduction ratios (80-95%)

**BloomFilter**
- Probabilistic data structure for efficient set membership testing
- Reduces memory usage and improves filtering performance
- Configurable false positive rates

**ASTNodeFingerprint**
- Compact representation of AST characteristics
- Node type counts, tree depth, structural patterns
- Enables fast similarity estimation

### 6. Data Models (`Sources/swift-similarity/Models/`)

**TreeNode Protocol**
- Generic tree representation for APTED algorithm
- Sendable-compliant for concurrent processing
- Abstraction layer over SwiftSyntax AST

**CodeElement Struct**
- Represents extracted code elements
- Contains metadata: name, type, location, code preview
- Sendable-compliant for parallel processing

### 7. Utilities (`Sources/swift-similarity/Utils/`)

**FileReader**
- Swift file discovery and content reading
- Directory traversal for project scanning

## Performance Optimization Strategy

### Three-Tier Optimization

1. **Prefiltering (95% reduction)**
   - Bloom filter-based elimination
   - AST fingerprint similarity
   - Size ratio thresholds

2. **Parallel Processing**
   - Swift Structured Concurrency
   - Configurable thread counts
   - Batch processing for candidate pairs

3. **Algorithmic Efficiency**
   - Optimized APTED implementation
   - Early termination strategies
   - Memory-efficient data structures

### Optimization Levels

| Level | Reduction | Threads | Batch Size | Use Case |
|-------|-----------|---------|------------|----------|
| `aggressive` | 95% | All cores | 200 | Large projects (10K+ elements) |
| `balanced` | 90% | All-1 cores | 100 | General use (recommended) |
| `conservative` | 80% | Half cores | 50 | High precision requirements |

## Data Flow

1. **Input**: Swift source files from target directory
2. **Parsing**: SwiftSyntax generates AST structures
3. **Extraction**: CodeElementExtractor identifies functions/structs/classes
4. **Conversion**: ASTToTreeConverter creates generic tree representations
5. **Fingerprinting**: ASTNodeFingerprint generates compact signatures
6. **Prefiltering**: BloomFilter eliminates obviously dissimilar pairs
7. **Calculation**: APTED computes tree edit distances
8. **Scoring**: SimilarityCalculator normalizes scores (0.0-1.0)
9. **Advanced Metrics**: Multi-dimensional similarity analysis (optional)
10. **Output**: Formatted results with similarity percentages and locations

## Key Design Decisions

### 1. SwiftSyntax Integration
- **Benefit**: Accurate Swift language parsing
- **Trade-off**: Dependency on Apple's SwiftSyntax library

### 2. Generic TreeNode Abstraction
- **Benefit**: Algorithm independence from SwiftSyntax specifics
- **Trade-off**: Additional conversion layer

### 3. Bloom Filter Optimization
- **Benefit**: Dramatic performance improvement (10-100x faster)
- **Trade-off**: Probabilistic nature may miss some similar pairs

### 4. Swift Structured Concurrency
- **Benefit**: Type-safe parallel processing
- **Trade-off**: Requires iOS 13+/macOS 10.15+

### 5. Multi-Level Configuration
- **Benefit**: Adaptable to different project sizes and requirements
- **Trade-off**: Increased complexity in configuration management

## Testing Strategy

The system includes comprehensive test coverage across all layers:
- Unit tests for core algorithms (APTED, similarity calculation)
- Integration tests for AST processing pipeline
- Performance tests for optimization components
- End-to-end CLI functionality tests

## Extensibility Points

1. **New Language Support**: Extend ASTToTreeConverter for other languages
2. **Additional Similarity Metrics**: Implement new similarity calculation strategies
3. **Alternative Algorithms**: Replace APTED with other tree comparison algorithms
4. **Output Formats**: Add new result formatting options
5. **Optimization Strategies**: Implement additional prefiltering techniques 