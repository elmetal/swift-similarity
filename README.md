# swift-similarity

A Swift tool for detecting similar code patterns using tree edit distance algorithms.

## Usage

### Basic similarity detection
```bash
# Scan for similar functions with default settings
swift run swift-similarity-cli scan Sources/

# Scan with custom threshold
swift run swift-similarity-cli scan Sources/ --threshold 0.7

# Scan for similar structs or classes
swift run swift-similarity-cli scan Sources/ --element-type struct
swift run swift-similarity-cli scan Sources/ --element-type class

# Other element types: init, enum, actor, protocol, extension, or all of them
swift run swift-similarity-cli scan Sources/ --element-type init
swift run swift-similarity-cli scan Sources/ --element-type all
```

### Filtering
```bash
# Declarations shorter than 5 lines are skipped by default; change or disable (0) the limit
swift run swift-similarity-cli scan Sources/ --min-lines 10
swift run swift-similarity-cli scan Sources/ --min-lines 0

# Skip declarations with fewer than 30 tokens
swift run swift-similarity-cli scan Sources/ --min-tokens 30

# Compare only bodies (function code blocks, type member blocks), ignoring names,
# attributes, modifiers, signatures and inheritance clauses
swift run swift-similarity-cli scan Sources/ --body-only
```

A comment containing `similarity-ignore` directly before a declaration excludes it (but not the
declarations nested in it). `--no-ignore-directives` compares them anyway.

```swift
// similarity-ignore: generated code
func generatedHelper() { ... }
```

### Performance
`scan` uses every core. `--threads N` limits the number of parallel tasks. `--optimization` is
deprecated and has no effect.

### Advanced options
```bash
# Show progress and detailed statistics
swift run swift-similarity-cli scan Sources/ --progress --stats

# Include code previews in output
swift run swift-similarity-cli scan Sources/ --print

# Also report structural, label and depth similarity for each pair
swift run swift-similarity-cli scan Sources/ --advanced
```

## Inspired

This project was inspired by [mizchi/similarity](https://github.com/mizchi/similarity).

## License
MIT