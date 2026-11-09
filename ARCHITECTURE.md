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
- Options: element type (`function` / `init` / `struct` / `class` / `enum` / `actor` / `protocol` / `extension` / `all`; with `--compare witnesses`, `function` / `init` / `property` / `subscript` / `all`), threshold, output format, output file, code previews, thread count, progress, statistics
- Extracts elements, then runs `SimilarityScanner` (`--compare tree`, the default), `MemberSimilarityScanner` (`--compare members`) or `WitnessSimilarityScanner` (`--compare witnesses`)
- `--advanced` adds structural / label / depth metrics (`AdvancedSimilarityMetrics`) for each reported pair; pairs are still selected by TSED

**OutputFormatter / OutputModels**
- Formats results as text or JSON (`ScanResult`, `SimilarPair`, `CodeElementLocation`)
- Optional code previews
- With `--show-ignored`, lists the declarations skipped by `similarity-ignore` comments
- `--format xcode` / `--format github` write one warning per declaration (`DiagnosticFormatter`)
- With `--group`, shows groups of mutually similar declarations (`SimilarityGrouping`, complete
  linkage over the reported pairs) and then the pairs between groups
- `--filter-name` / `--filter-code` keep the pairs involving a matching declaration (`PairFilter`
  in `Sources/swift-similarity/Output/`); every pair is still compared

### 2. AST Processing (`Sources/swift-similarity/AST/`)

**SwiftASTParser**
- Parses source files or strings with `SwiftParser`

**CodeElementExtractor**
- Parses and walks the files in parallel; elements are returned in file order
- `SyntaxVisitor` that collects functions, initializers, structs, classes, enums, actors, protocols and extensions
- Defines `CodeElement` (name, signature, file path, start/end line, code preview, `TreeNode`) and `CodeElementType`
- `extract(fromPaths:excluding:)` returns an `Extraction`: the elements, the `ConformanceIndex` and
  the `IgnoredDeclaration`s skipped by `similarity-ignore` comments

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
- Time O(|T1|·|T2|·min(depth, leaves)²), memory O(|T1|·|T2|)
- Runs on Int32 tables when all costs are whole numbers (the default), Double otherwise
- `lowerBound`: the larger of the preorder and postorder label-sequence edit distances. With a limit
  it only computes the band of cells a path within the limit can reach and stops once a row exceeds
  it; distances within the limit are exact

**PreparedTree / LabelInterner**
- Everything the distance and its bounds need from one tree (postorder indexes in both orientations,
  keyroots, label sequences, label histogram), with labels interned to scan-wide integer ids. A scan
  prepares each element once instead of once per pair; `APTED`, `SimilarityCalculator` and the
  histogram bound accept prepared trees
- Built from one preorder walk (`FlatTree`): postorder positions and leftmost leaves follow from
  subtree sizes and depths, and the mirror image's postorder is the reversed preorder

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
- `PreparedTree` computes the same bound from interned, sorted histograms; the scanner uses that one

**SimilarityScanner**
- One exact pipeline: prepare each element's tree once (in parallel), group elements with identical
  trees into classes (`PreparedTree.identityKey`), skip nested pairs, skip pairs whose TSED upper
  bound is below the threshold, then compute the bounded TSED via `SimilarityCalculator` in parallel
- Only the first element of each class is compared: copies score 1.0 with each other and share
  every other score, so each comparison yields a block of pairs (`Block`) with one score
- Splits the class pairs into cost-balanced tasks run on every core (see Scheduling below)
- `selectPairs` expands the blocks into pairs, sorted by score, ties in input order, skipping
  nested pairs and those the `including` predicate rejects; with `maxPairs` it keeps only the first
  pairs, holding at most twice that many at once, and still counts every matching pair
- Reports progress per phase (fingerprinting, comparing) through an optional handler

**ScanStatistics**
- How many pairs were nested, ruled out by the upper bound, compared with TSED or identical, the
  number of distinct trees and similar pairs, and the time of each phase; reported by `scan --stats`
  (without distinct trees and fingerprinting for `--compare members`, which compares no trees)

### 5b. Member Comparison (`Sources/swift-similarity/Members/`)

**TypeMember**
- A member declared directly in a type, protocol or extension: kind, `static`, name (with argument
  labels) and normalized type or signature. `CodeElementExtractor` records them in
  `CodeElement.members` for every declaration group.

**MemberSimilarity**
- `(exact + 0.5 × partial) / max(count1, count2)`: members matching in kind, `static`, name and
  type count 1; of the rest, those matching in name or in type count 0.5; each member matches once
- `upperBound(count1:count2:)` = `min / max` skips pairs whose member counts already rule them out

**ConformanceIndex**
- Built by `CodeElementExtractor.extractElementsAndConformances(fromPaths:excluding:)` from every
  type, extension and protocol in the scanned files (regardless of filters): type name → inherited
  protocols, protocol → requirements (kind, `static`, name), plus a table of common standard
  library protocols
- `membersExcludingWitnesses(of:)` leaves out members that satisfy a requirement of a protocol the
  type conforms to, directly or through protocol inheritance
- `declaredRequirements(forTypeNamed:)` maps the requirements of protocols declared in the scanned
  files that a type (or a protocol, for its extensions) conforms to, to the protocols declaring them

**MemberSimilarityScanner**
- With a `ConformanceIndex`, compares members after leaving out protocol witnesses
- Compares elements with at least two (remaining) members, within groups (concrete types, protocols,
  extensions), skipping nested pairs; returns the same `Result` and `ScanStatistics` as
  `SimilarityScanner`, in the same order (most similar first, ties in input order)

**WitnessSimilarityScanner / WitnessCandidate / Witness**
- With `Configuration.witnessCandidateTypes`, `CodeElementExtractor` collects members with a body
  (methods, initializers, computed properties, subscripts) of types and extensions as
  `WitnessCandidate`s, whose tree is the body only
- `witnessesByRequirement(_:conformances:)` keeps the candidates that implement a requirement of a
  protocol declared in the scanned files, sets `CodeElement.witness`, and groups them by requirement
- Each group is scanned with `SimilarityScanner` (TSED of bodies); pairs never cross requirements
- `Witness.advice(for:)` suggests a default implementation, or points at the existing one

### 6. Data Models (`Sources/swift-similarity/Models/`)

**TreeNode protocol / SimpleTreeNode**
- Generic `Sendable` labeled ordered tree used by the algorithm layer, independent of SwiftSyntax

### 7. Utilities (`Sources/swift-similarity/Utils/`)

**FileReader**
- Recursively finds `.swift` files in a directory (hidden files are skipped)

### 8. SwiftPM Plugin (`Plugins/SimilarityPlugin/`)

**SimilarityPlugin**
- Command plugin (`swift package similarity`): runs `swift-similarity-cli scan` on the source
  directories of the `--target`s (default: every Swift source target except tests), passing the
  other arguments through, with the package directory as the working directory

## Performance Strategy

1. **Exact prefiltering**: the label-histogram TSED upper bound removes pairs that cannot reach the
   threshold, without computing the edit distance. It works best at high thresholds.
2. **Parallel processing**: cost-balanced tasks on every core with Swift structured concurrency (see Scheduling).
3. **Efficient edit distance**: trees prepared once per scan; Zhang–Shasha with flat Int32 tables
   (for whole-number costs) and integer label ids; a banded, early-exit sequence lower bound.

### Scheduling

`SimilarityScanner` orders the elements by tree size, largest first. It compares each
element with the elements after it, and cuts each of these rows into tasks of roughly equal estimated
cost (the product of the two tree sizes). Tasks are submitted heaviest first to a `TaskGroup` with one
task per core (`--threads` overrides this). Results are sorted by score, highest first, with ties in
input order, so the output does not depend on which task finishes first.

Earlier versions had a second, "hierarchical" engine and per-scale configuration (block sizes, thread
caps, sampling, candidate caps, early termination). Every pair is independent and CPU-bound and the
filters are exact, so a single pipeline on every core finds the same pairs; that configuration was
removed together with the `--optimization` and `--hierarchical` options.

## Data Flow

1. **Input**: `FileReader` lists Swift files in the target directory
2. **Parsing & extraction**: `CodeElementExtractor` parses each file and collects the requested element types
3. **Conversion**: `ASTToTreeConverter` turns each element's syntax node into a labeled `TreeNode`
4. **Preparation**: a `PreparedTree` is built for each element
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
- **Trade-off**: Requires macOS 26+ (package platform) and Swift 6.2 tools

## Testing Strategy

`Tests/swift-similarityTests/` mirrors the source layout:
- AST: parser, extractor (filters, ignore comments) and converter (label convention) tests
- Algorithm: edit distance tests, and prepared trees giving the same results as per-pair preparation
- Calculator: TSED normalization and advanced metrics tests
- Config: `similarity.toml` parsing and the precedence of command-line options
- Members: member extraction, member similarity, the conformance index and the member scanner
- Optimization: fingerprint bounds, `SimilarityScanner` (a brute-force equivalence check, stable
  order, statistics), exact pruning with a non-default rename cost, nested pairs, and
  `TSEDPipelineTests` (soundness of the TSED upper bound)
- Output: ranking, pair filters, grouping and the Xcode / GitHub diagnostic formats
- Utils: file discovery, exclude patterns
- `Support/TestSupport.swift`: shared helpers (extraction from source text, seeded random trees)
