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

### Focusing on one declaration
```bash
# Pairs in which a declaration's name contains "parse" (ignoring case)
swift run swift-similarity-cli scan Sources/ --element-type all --filter-name parse

# Pairs in which a declaration's source contains "URLSession" (case-sensitive)
swift run swift-similarity-cli scan Sources/ --filter-code URLSession
```

A pair is reported when either of its declarations matches; with both options, one declaration
must match both. The filters only select which pairs are reported: every pair is still compared,
scores are unchanged, and `--fail-on-duplicates` counts the reported pairs.

### Listing ignored declarations
```bash
swift run swift-similarity-cli scan Sources/ --show-ignored
```

`--show-ignored` adds the declarations skipped because of a `similarity-ignore` comment (of the
selected element types) to the output, with their location and the comment, so you can review
them. In JSON they are in the `ignored` array.

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

### Comparing type members
`--compare members` compares types by their members instead of their syntax trees. It finds
types with the same shape, such as two DTOs with the same fields or an enum copied into another
module, even when the members are in a different order or the method bodies differ.

```bash
# Every kind of type (the element type defaults to all types in this mode)
swift run swift-similarity-cli scan Sources/ --compare members

# Only structs, with a lower threshold
swift run swift-similarity-cli scan Sources/ --compare members --element-type struct --threshold 0.6
```

Each member declared directly in a type, protocol or extension is reduced to its kind (property,
method, initializer, subscript, enum case, typealias, associated type), whether it is `static`, its
name (methods and initializers with their argument labels, such as `update(with:)`) and its type
(for methods the signature, for enum cases the associated values). Whitespace is ignored, and
`Optional<T>`, `Array<T>` and `Dictionary<K, V>` match `T?`, `[T]` and `[K: V]`. Bodies,
attributes, access modifiers and the types' own names are not compared. Nested types are not
members; they are compared as types of their own.

```
similarity = (exact + 0.5 × partial) / max(members of either type)
```

`exact` counts members that match in kind, `static`, name (ignoring case) and type. Among the
rest, `partial` counts those that match in kind and `static` and in either the name or the type,
so a renamed field or a changed type counts half. Each member matches at most once. A property
whose type is inferred (`var count = 0`) only matches a property with the same name.

Only types of the same group are compared: structs, classes, enums and actors with each other,
protocols with protocols, and extensions with extensions. Comparing a protocol with the types that
conform to it would mostly report the conformance.

Members that only satisfy a protocol requirement (protocol witnesses) are left out before
comparing, because every type conforming to the protocol declares them. Without this, extensions
that implement the same protocol for different types would all look alike. A member is a witness
when the type conforms to a protocol that requires a member of the same kind, `static` and name
(types are not compared, since associated types and `Self` are written differently). The
requirements come from:

- protocols declared in the scanned files, including the protocols they inherit from;
- common standard library protocols (`Equatable`, `Hashable`, `Comparable`, `Codable`,
  `Identifiable`, `CustomStringConvertible`, `RawRepresentable`, `CaseIterable`, `LocalizedError`,
  `Sequence`, `Collection`, the `ExpressibleBy…Literal` protocols and a few more).

A conformance counts wherever it is declared: on the type, or on any extension of it in the scanned
files (`extension Square: Shape {}` makes the members of every `Square` extension that implement
`Shape` witnesses). An enum with a raw type (`enum Status: String`) is `RawRepresentable`. Members
of a protocol extension that provide defaults for the protocol's own requirements are left out too.
Types are matched by simple name, so `Outer.Inner` and `Inner` are the same type. Requirements of
protocols from other modules that are not in the list above are unknown, and their witnesses are
compared like other members.

Types with fewer than two members left are skipped, as are `--min-lines` short declarations and
`similarity-ignore` ones.
`--rename-cost`, `--body-only`, `--min-tokens` and `--advanced` apply to `--compare tree` only.
In `similarity.toml`, set `compare = "members"`.

### Performance
`scan` uses every core. `--threads N` limits the number of parallel tasks. `--stats` shows how many
pairs were skipped by the exact filters and how long each phase took. `--optimization` and
`--hierarchical` are deprecated and have no effect.

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

## Using with AI assistants

The text output gives each pair's similarity, priority and `file:line` locations, which an AI
assistant can read directly. Ask it to run the tool and plan the refactoring, for example:

```
Run `swift-similarity-cli scan Sources --sort priority` to find similar Swift code. Read the code
of the reported pairs, separate real duplicates from code that only has the same shape, and write a
refactoring plan ordered by impact. See `swift-similarity-cli scan --help` for options.
```

```
`swift-similarity-cli scan Sources --sort priority` で構造的に似た Swift コードを検出できます。
実行して、報告されたペアのコードを読み、本当の重複と形が似ているだけのコードを区別したうえで、
効果の大きい順にリファクタリング計画を立ててください。オプションは `swift-similarity-cli scan --help` で確認できます。
```

For [Claude Code](https://claude.com/claude-code), this repository includes a skill,
[`.claude/skills/check-similarity/SKILL.md`](.claude/skills/check-similarity/SKILL.md), with the
same workflow in more detail: which scans to run, how to judge the pairs and how to write the plan.
Copy it to `.claude/skills/check-similarity/` in your project (or `~/.claude/skills/` for every
project) and ask Claude to check for duplicated code.

## Inspired

This project was inspired by [mizchi/similarity](https://github.com/mizchi/similarity).

## License
MIT