# swift-similarity Architecture

## Overview

swift-similarity is a Swift tool for detecting similar code elements (functions, structs, classes, enums) by comparing their syntax trees.

The similarity measure is **TSED (Tree Similarity of Edit Distance)** from
*"Revisiting Code Similarity Evaluation with Abstract Syntax Tree Edit Distance"*
([arXiv:2404.08817](https://arxiv.org/abs/2404.08817)). The paper parses code with tree-sitter, computes the
tree edit distance between the ASTs, and normalizes it by the size of the larger tree. This project
follows the same method, using SwiftSyntax instead of tree-sitter:

```
TSED(T1, T2) = max(1 - δ(T1, T2) / MaxNodes(T1, T2), 0)
```

- `δ` is the ordered, labeled tree edit distance (insert / delete / rename, unit cost by default; `--rename-cost` changes the rename cost).
- `MaxNodes` is the node count of the larger tree.

To avoid computing the edit distance for all O(n²) pairs, the tool first rejects pairs with a cheap
upper bound of TSED. The bound never rejects a pair that would reach the threshold, so the results
are the same as an exhaustive comparison.

## System Pipeline

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Swift Files   │───▶│ CodeElement      │───▶│ ASTToTreeConverter  │
│   (.swift)      │    │ Extractor        │    │ (TreeNode per elem.)│
│   FileReader    │    │ (SwiftSyntax)    │    │                     │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                                           │
                                                           ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ OutputFormatter │◀───│ SimilarityCalc.  │◀───│ ASTNodeFingerprint  │
│ (Text/JSON)     │    │ TSED = 1 - δ/Max │    │ TSED upper bound    │
│                 │    │ δ: APTED class   │    │ (exact prefilter)   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

Pair enumeration and parallelism are handled by `SimilarityScanner`.

## Core Components

### 1. CLI Layer (`Sources/swift-similarity-cli/`)

**SwiftSimilarityCLI**
- `@main` entry point (swift-argument-parser); `scan` is the default subcommand

**ScanCommand**
- Options: element type (`function` / `init` / `struct` / `class` / `enum` / `actor` / `protocol` / `extension` / `all`), threshold, output format, output file, code previews, thread count, progress, statistics
- Extracts elements, then runs `SimilarityScanner`
- `--optimization` and `--hierarchical` are deprecated no-ops kept for existing scripts; they print a notice on stderr
- `--advanced` adds structural / label / depth metrics (`AdvancedSimilarityMetrics`) for each reported pair; pairs are still selected by TSED

**OutputFormatter / OutputModels**
- Formats results as text or JSON (`ScanResult`, `SimilarPair`, `CodeElementLocation`)
- Optional code previews

### 2. AST Processing (`Sources/swift-similarity/AST/`)

**SwiftASTParser**
- Parses source files or strings with `SwiftParser`

**CodeElementExtractor**
- `SyntaxVisitor` that collects functions, initializers, structs, classes, enums, actors, protocols and extensions
- Defines `CodeElement` (name, signature, file path, start/end line, code preview, `TreeNode`) and `CodeElementType`

**ASTToTreeConverter**
- Converts any SwiftSyntax node to a `TreeNode`, using the label convention of the tree-sitter ASTs in TSED:
  - Syntax nodes → node type name without the `Syntax` suffix (e.g. `FunctionDecl`, `IfExpr`)
  - Keywords, punctuation, operators → their text (e.g. `func`, `{`, `+`)
  - Identifiers and literals → their category (`Identifier`, `IntegerLiteral`, ...), so renaming
    variables or changing constants does not change the score. `Options` can include names / values.
- Empty syntax collections are omitted

### 3. Algorithm Layer (`Sources/swift-similarity/Algorithm/`)

**APTED** (class name)
- Computes the ordered, labeled tree edit distance with configurable insert / delete / substitute costs
- Implemented with the **Zhang–Shasha** algorithm, which returns the same distance as APTED
  (Pawlik & Augsten); APTED only differs in its decomposition strategy, which affects running time
- Time O(|T1|·|T2|·min(depth, leaves)²), memory O(|T1|·|T2|); postorder indexing is iterative to handle deep ASTs

### 4. Similarity Engine (`Sources/swift-similarity/Calculator/`)

**SimilarityCalculator**
- Computes TSED: `max(1 - δ / MaxNodes, 0)`
- Returns the edit distance, score, threshold decision and node-count metadata

**AdvancedSimilarityMetrics** (library only, not used by the CLI)
- Weighted combination of a structural Jaccard score, a label Jaccard score, a depth score and the TSED score

### 5. Optimization Layer (`Sources/swift-similarity/Optimization/`)

**ASTNodeFingerprint**
- Label histogram, node count, depth and leaf count of a tree
- `treeEditDistanceLowerBound`: lower bound of δ from the label histograms (extra labels on each side
  must be deleted, inserted or renamed)
- `tsedUpperBound`: `max(1 - δ_lower / MaxNodes, 0)`. If it is below the threshold, the pair is skipped
  with no false negatives

**SimilarityScanner**
- One exact pipeline: fingerprint each element once, skip nested pairs, skip pairs whose TSED upper
  bound is below the threshold, then compute the bounded TSED via `SimilarityCalculator` in parallel
- Splits the pairs into cost-balanced tasks run on every core (see Scheduling below); results are
  sorted by score, ties in input order
- Reports progress per phase (fingerprinting, comparing) through an optional handler

**ScanStatistics**
- How many pairs were nested, ruled out by the upper bound or compared with TSED, the number of
  similar pairs, and the time of each phase; reported by `scan --stats`

### 6. Data Models (`Sources/swift-similarity/Models/`)

**TreeNode protocol / SimpleTreeNode**
- Generic `Sendable` labeled ordered tree used by the algorithm layer, independent of SwiftSyntax

### 7. Utilities (`Sources/swift-similarity/Utils/`)

**FileReader**
- Recursively finds `.swift` files in a directory (hidden files are skipped)

## Performance Strategy

1. **Exact prefiltering**: the label-histogram TSED upper bound removes pairs that cannot reach the
   threshold, without computing the edit distance. It works best at high thresholds.
2. **Parallel processing**: cost-balanced tasks on every core with Swift structured concurrency (see Scheduling).
3. **Efficient edit distance**: Zhang–Shasha with flat arrays, integer label ids and reused DP buffers.

### Scheduling

`SimilarityScanner` orders the elements by tree size, largest first. It compares each
element with the elements after it, and cuts each of these rows into tasks of roughly equal estimated
cost (the product of the two tree sizes). Tasks are submitted heaviest first to a `TaskGroup` with one
task per core (`--threads` overrides this). Results are sorted by score, highest first, with ties in
input order, so the output does not depend on which task finishes first.

Earlier versions had a second, "hierarchical" engine and per-scale configuration (block sizes, thread
caps, sampling, candidate caps, early termination). Every pair is independent and CPU-bound and the
filters are exact, so a single pipeline on every core finds the same pairs; that configuration was
removed, and `--optimization` / `--hierarchical` are accepted but ignored.

## Data Flow

1. **Input**: `FileReader` lists Swift files in the target directory
2. **Parsing & extraction**: `CodeElementExtractor` parses each file and collects the requested element types
3. **Conversion**: `ASTToTreeConverter` turns each element's syntax node into a labeled `TreeNode`
4. **Fingerprinting**: an `ASTNodeFingerprint` is built for each element
5. **Prefiltering**: pairs whose TSED upper bound is below the threshold are skipped
6. **Calculation**: `APTED` computes δ and `SimilarityCalculator` computes TSED
7. **Output**: `OutputFormatter` prints pairs at or above the threshold as text or JSON

## Key Design Decisions

### 1. TSED as the similarity measure
- **Benefit**: A published, evaluated measure (arXiv:2404.08817); scores are comparable to the paper
- **Trade-off**: Edit distance is expensive, so prefiltering is needed for large projects

### 2. SwiftSyntax instead of tree-sitter
- **Benefit**: Accurate Swift parsing from the official parser
- **Trade-off**: Node types differ from tree-sitter's; labels follow the same convention but are not identical

### 3. Generic TreeNode abstraction
- **Benefit**: The algorithm layer does not depend on SwiftSyntax and is easy to test
- **Trade-off**: Additional conversion step

### 4. Exact (lossless) prefiltering
- **Benefit**: The results are the same as comparing every pair
- **Trade-off**: Prunes less than heuristic filters (Bloom filter, size ratio) at low thresholds

### 5. Swift structured concurrency
- **Benefit**: Type-safe parallel processing (`Sendable` models, `TaskGroup`)
- **Trade-off**: Requires macOS 11+ (package platform) and Swift 6.1 tools

## Testing Strategy

`Tests/swift-similarityTests/` mirrors the source layout:
- AST: parser, extractor and converter (label convention) tests
- Algorithm: edit distance tests
- Calculator: TSED normalization and advanced metrics tests
- Optimization: fingerprint bounds, vectorized engine (including a brute-force equivalence check), hierarchical processor,
  adaptive configuration, and `TSEDPipelineTests` (soundness of the TSED upper bound, and that both
  CLI engines report the exact TSED score)
