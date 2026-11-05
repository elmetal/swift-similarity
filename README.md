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

### Choosing files
`scan` takes one or more directories and `.swift` files. Directories are searched recursively;
hidden files and directories (such as `.build` and `.git`) are skipped. Each file is scanned once,
in path order, however the paths overlap.

```bash
# Several directories and files
swift run swift-similarity-cli scan Sources/App Sources/Core Scripts/build.swift

# Skip files and directories matching a glob pattern (repeatable)
swift run swift-similarity-cli scan . --exclude Tests --exclude '**/Generated/**' --exclude '*.generated.swift'
```

`*`, `?` and `[...]` match within one path component and `**` matches any number of components.
A pattern matches a path when it matches its last components, so `Tests` skips every file or
directory named `Tests`. Paths are matched relative to the directory being scanned: a directory you
name on the command line is always scanned (only its contents are filtered), while a file you name
is skipped if its path matches.

### Config file
`scan` reads the nearest `similarity.toml` in the current directory or one of its parents.
Command-line options override the file; `--exclude` patterns are added to the file's `exclude`.

```toml
# similarity.toml
threshold = 0.85                       # --threshold (default 0.8)
element_type = "all"                   # --element-type (default "function")
exclude = ["Tests", "**/Generated/**"] # --exclude
min_lines = 10                         # --min-lines (default 5)
min_tokens = 30                        # --min-tokens (default 0)
body_only = true                       # --body-only / --no-body-only (default false)
ignore_directives = false              # --ignore-directives / --no-ignore-directives (default true)
sort = "priority"                      # --sort (default "similarity")
fail_on_duplicates = true              # --fail-on-duplicates / --no-fail-on-duplicates (default false)
rename_cost = 1.0                      # --rename-cost (default 1.0)
```

`no_ignore_directives = true` is accepted as well, as the opposite of `ignore_directives`. Each
on/off option has a `--no-` form, so the command line can turn off what the file turns on (for
example `--no-fail-on-duplicates` for a local run).

The file supports top-level `key = value` lines, `#` comments, strings, numbers, booleans and
arrays of strings; keys may also be written with `-` (`element-type`). Tables are not supported.
Unknown keys are ignored with a warning, and a file that cannot be read or parsed is ignored with
a warning on stderr.

### Scoring
Similarity is TSED ([arXiv:2404.08817](https://arxiv.org/abs/2404.08817)): the tree edit
distance between the two syntax trees, divided by the size of the larger tree and subtracted from
1. Identifiers and literals are labeled by category only, so renaming a variable or changing a
number costs nothing. Deleting or inserting a syntax node costs 1. Renaming a node, which changes
its label (for example `+` to `-`, `let` to `var`, or one syntax kind to another), costs `--rename-cost`:

```bash
# Make changed syntax kinds cheaper, as mizchi/similarity does (its default is 0.3)
swift run swift-similarity-cli scan Sources/ --rename-cost 0.3
```

The default, 1.0, follows the TSED paper. A lower cost raises the score of pairs that differ in
labels but not in shape, so more pairs reach the threshold; a cost of 2 or more makes a rename no
cheaper than a deletion plus an insertion. The exact pre-filters use the same cost, so pruning
never drops a pair whatever the cost, but cheaper renames make them weaker and the scan slower.

On this repository, swift-argument-parser and swift-syntax, `--rename-cost 0.3` found 3–11% more
pairs at threshold 0.8 and dropped none. Almost all of the added pairs were unrelated code with the
same shape (for example two functions that each return a call with forwarded arguments), and the
result was about the same as keeping 1.0 and lowering the threshold by 0.01–0.03. To find more
pairs, lowering `--threshold` has much the same effect.

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