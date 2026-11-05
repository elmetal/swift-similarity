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

### Ranking and CI
```bash
# Show the most impactful duplicates first
swift run swift-similarity-cli scan Sources/ --sort priority

# Exit with code 1 when any similar pair is found (results are still written)
swift run swift-similarity-cli scan Sources/ --fail-on-duplicates
```

`--sort similarity` (the default) orders pairs by similarity, highest first. `--sort priority`
orders them by **priority = similarity × lines**, where lines is the line span of the *smaller*
of the two declarations: at most that many lines can be duplicated, so a short helper that
resembles part of a long function is not ranked as if the whole long function were duplicated.
Ties are broken by similarity, then by the order the pairs were found in, so the output is
deterministic. Each pair shows its priority (for example `Priority: 8.5 (lines: 10)`), and the
JSON output has `priority` and `lines` fields plus `summary.sortOrder`.

With `--fail-on-duplicates` the exit code is 1 if at least one pair is found and 0 otherwise.
The results go to stdout (or `--output`) as usual and diagnostics to stderr; invalid arguments
exit with code 64.

## Inspired

This project was inspired by [mizchi/similarity](https://github.com/mizchi/similarity).

## License
MIT