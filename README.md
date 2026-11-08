# swift-similarity

A Swift tool for detecting similar code patterns using tree edit distance algorithms.

## Installation

Requires Swift 6.1 or later, on macOS 11 or later or Linux. The latest release is
[0.0.2](https://github.com/elmetal/swift-similarity/releases/tag/0.0.2).

### Command-line tool
Build it from source and copy the binary to a directory on your `PATH`:

```bash
git clone --branch 0.0.2 https://github.com/elmetal/swift-similarity.git
cd swift-similarity
swift build -c release
cp .build/release/swift-similarity-cli /usr/local/bin/
```

Copying to `/usr/local/bin` may need `sudo`; any other directory on `PATH` works too. Then run
`swift-similarity-cli scan <paths>` (`swift-similarity-cli scan --help` lists every option).

### SwiftPM command plugin
To scan a Swift package without installing anything, add this package as a dependency and run
`swift package similarity` (see [SwiftPM command plugin](#swiftpm-command-plugin)):

```swift
dependencies: [
    .package(url: "https://github.com/elmetal/swift-similarity.git", from: "0.0.2"),
],
```

## Usage

The examples below run the tool from a checkout of this repository with `swift run
swift-similarity-cli`. With the tool installed, use `swift-similarity-cli` instead.

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
scores are unchanged, and `--fail-on-duplicates` counts the matching pairs.

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
compare = "members"                    # --compare: "tree" (default), "members" or "witnesses"
group = true                           # --group / --no-group (default false)
max_pairs = 0                          # --max-pairs (default 10000; 0 for no limit)
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

The tree edit distance is ordered: children are matched in source order. Moving a statement or a
member elsewhere costs a deletion plus an insertion of its whole subtree, so two copies whose
statements were reordered can score well below two copies with an edited line. To find types
whose members are in a different order, use [`--compare members`](#comparing-type-members).

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
`--rename-cost`, `--body-only`, `--min-tokens` and `--advanced` do not apply to `--compare members`.
In `similarity.toml`, set `compare = "members"`.

### Comparing protocol implementations
`--compare witnesses` compares implementations of the same protocol requirement in different
types. When several types implement a requirement with the same code, that code could become one
default implementation in an extension of the protocol; when a type repeats a default
implementation that already exists, its own implementation may be unnecessary.

```bash
swift run swift-similarity-cli scan Sources/ --compare witnesses
```

```swift
protocol Named { var name: String { get }; var label: String { get } }

struct User: Named {
    let name: String
    var label: String { "[\(name)]" }   // ┐ both implement Named.label:
}                                       // │ consider a default implementation
struct Team: Named {                    // │ in an extension of Named
    let name: String                    // │
    var label: String { "[\(name)]" }   // ┘
}
```

Methods, initializers, computed properties and subscripts that have a body are compared by their
bodies only (the requirement already fixes the name and signature), with TSED as in
`--compare tree`, and only with other implementations of the same requirement. Members of a
protocol's extensions that implement its requirements are its default implementations and are
compared too. A member implements a requirement as described under
[Comparing type members](#comparing-type-members), except that only protocols declared in the
scanned files count: requirements of standard library protocols such as `description` or `==`
cannot share one default implementation.

Each pair says which requirement both declarations implement and what to do about it, in the text,
JSON (`requirement`, `advice`), Xcode and GitHub output.

`--element-type` selects the kinds of members: `function` (methods), `init`, `property`,
`subscript` or `all` (the default in this mode). Implementations are often one-liners, so
`--min-lines` defaults to 0 here; `--min-tokens`, `--rename-cost`, `--threshold` and
`similarity-ignore` comments apply as usual. In `similarity.toml`, set `compare = "witnesses"`.

### Performance
`scan` uses every core. `--threads N` limits the number of parallel tasks. `--stats` shows how many
pairs were skipped by the exact filters and how long each phase took.

Declarations with identical syntax trees, common in generated code, are compared once: copies
score 100% with each other, and every copy scores the same against any other declaration. The
results are the same as comparing every pair. On swift-syntax's `SwiftSyntax` sources,
`--compare witnesses` finds 135,048 pairs among 1,399 implementations with only 99 distinct
trees, in 2 seconds instead of almost 5 minutes.

### Limiting the number of pairs
At most 10,000 pairs are reported, the most similar first, so that a codebase with many copies
does not produce a report nobody can read. The number of pairs found is still shown, filters
(`--filter-name`, `--filter-code`) apply before the limit, and `--fail-on-duplicates` counts every
matching pair. `--max-pairs N` changes the limit, and `--max-pairs 0` removes it (`max_pairs` in
`similarity.toml`). When the limit is reached, `--group`, `--exclude` for generated code, or a
higher `--threshold` or `--min-lines` usually help more than a higher limit.

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

### Grouping copies
```bash
swift run swift-similarity-cli scan Sources/ --group
```

When n declarations are copies of each other, there are n(n−1)/2 similar pairs. `--group` reports
them as one group instead:

```
1. 4 Structs, similarity 100.00%
   Priority: 30.0 (lines: 10)
   - SplitMix64  Tests/.../APTEDTests.swift:189-198
   - SplitMix64  Tests/.../PreparedTreeTests.swift:45-54
   - SeededGenerator  Tests/.../RenameCostPruningTests.swift:13-22
   - SeededGenerator  Tests/.../TSEDPipelineTests.swift:20-29
```

**Every two declarations in a group are similar** (complete linkage): pairs are taken from most to
least similar, and two groups are merged only if every declaration of one is similar to every
declaration of the other. So `A ~ B` and `B ~ C` do not put `A` and `C` in one group unless
`A ~ C` too. A declaration is in one group only; the pairs between declarations of different groups
are listed after the groups, so no pair is dropped.

Groups are sorted by their most similar pair, or with `--sort priority` by
**(declarations − 1) × lines of the smallest × lowest similarity**, roughly the lines that merging
the copies would remove (for two declarations, the same as the pair's priority). In JSON,
`groups` lists each group's members, similarity range, priority and lines, and `similarPairs`
still lists every reported pair. `--fail-on-duplicates` still counts pairs.

On swift-syntax (functions at 0.8), 375 pairs become 109 groups plus 36 pairs between groups.

## Xcode, CI and SwiftPM

### Warnings in Xcode and GitHub
`--format xcode` and `--format github` write one warning per declaration that has similar
declarations, naming them, most similar first:

```
/path/Sources/A.swift:10:1: warning: function load is similar to function fetch (Sources/B.swift:5, 95.0%), function reload (line 30, 90.0%) [swift-similarity]
```

- `xcode` is the `path:line:column: warning:` format that Xcode shows in the editor and the issue
  navigator when a Run Script build phase prints it. Most editors and CI logs understand it too.
- `github` writes [workflow commands](https://docs.github.com/actions/reference/workflow-commands-for-github-actions)
  (`::warning file=...,line=...::...`) that annotate the lines in a pull request. Paths are made
  relative to the current directory, which is the repository root in a workflow step.

All scan options apply. `--group`, `--show-ignored`, `--print` and `--advanced` do not change these
formats. Add `--fail-on-duplicates` to fail the build or the job when anything is found.

### SwiftPM command plugin
Add the package as a dependency, then run `swift package similarity`:

```swift
// Package.swift of your package
dependencies: [
    .package(url: "https://github.com/elmetal/swift-similarity.git", from: "0.0.2"),
],
```

```bash
# Every Swift source target except test targets
swift package similarity

# Some targets, with any scan option
swift package similarity --target App --target Core --group --sort priority
swift package similarity --format github --fail-on-duplicates
```

The plugin scans the source directories of the targets and passes every other argument to `scan`.
It runs in the package directory, so a `similarity.toml` there applies. It only reads files; with
`--output` inside the package, add `--allow-writing-to-package-directory`.

### Xcode Run Script build phase
With `swift-similarity-cli` installed (see [Installation](#installation)), add a Run Script phase:

```bash
if command -v swift-similarity-cli >/dev/null; then
  swift-similarity-cli scan "$SRCROOT/Sources" --format xcode
else
  echo "warning: swift-similarity-cli is not installed"
fi
```

Xcode runs build scripts in a sandbox that cannot read the sources (`ENABLE_USER_SCRIPT_SANDBOXING`);
set it to `NO` for the target, or list the source directories as input files of the phase. The
scan reads every file on each build, so for large projects consider running it only in CI.

### GitHub Actions
```yaml
- name: Check for similar code
  run: swift package similarity --format github
```

Warnings show up on the changed lines of the pull request. Add `--fail-on-duplicates` to fail the
job, or use `similarity.toml` to share the threshold and excludes with local runs.

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
[`.claude/skills/duplication-review/SKILL.md`](.claude/skills/duplication-review/SKILL.md), with the
same workflow in more detail: which scans to run, how to judge the pairs and how to write the plan.
Copy it to `.claude/skills/duplication-review/` in your project (or `~/.claude/skills/` for every
project) and ask Claude to check for duplicated code.

## Inspired

This project was inspired by [mizchi/similarity](https://github.com/mizchi/similarity).

## License
MIT