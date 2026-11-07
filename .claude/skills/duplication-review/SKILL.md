---
name: duplication-review
description: Find duplicated or near-duplicated Swift code with swift-similarity and plan refactorings. Use when asked to find duplicate code, copy-paste, similar functions or types, or refactoring opportunities in a Swift codebase.
---

# Review Swift code duplication

Use `swift-similarity-cli` to find similar Swift declarations, then turn the results into a
refactoring plan. Run the CLI yourself; don't ask the user to run it.

## Running the tool

Use `swift-similarity-cli` if it is on `PATH`. Otherwise build it from a checkout of
https://github.com/elmetal/swift-similarity (`swift build -c release`, then use
`.build/release/swift-similarity-cli`). Run `swift-similarity-cli scan --help` for every option.

Diagnostics go to stderr and results to stdout. A `similarity.toml` in the project (or a parent
directory) may already set the threshold, excludes and other defaults; command-line options win.

Start broad, then narrow:

```bash
# Functions (default), the most impactful duplicates first, copies grouped together
swift-similarity-cli scan Sources --sort priority --group

# Every kind of declaration, with code so you can judge each pair
swift-similarity-cli scan Sources --element-type all --sort priority --print

# Types with the same shape (same fields or requirements), ignoring member order and bodies
swift-similarity-cli scan Sources --compare members

# Same code implementing the same protocol requirement in several types: default implementation candidates
swift-similarity-cli scan Sources --compare witnesses

# What else looks like one function or type?
swift-similarity-cli scan Sources --element-type all --filter-name parseHeader --threshold 0.7

# Machine-readable output
swift-similarity-cli scan Sources --format json --sort priority
```

Useful knobs:
- `--threshold` (default 0.8): lower it (0.7) to see more candidates, raise it (0.9) for near copies.
- `--min-lines` (default 5) / `--min-tokens`: skip trivial declarations.
- `--body-only`: compare implementations only, ignoring names and signatures.
- `--exclude 'Tests'`, `--exclude '**/Generated/**'`: skip generated or irrelevant code.

## Judging the results

Similarity is structural: identifiers and literal values are ignored, so two functions can score
100% while doing different things with the same shape. Read the code of each pair (`--print` shows
the start of each declaration; open the file for the rest) before proposing a change. For each
group of similar declarations, decide whether it is:

- **a real duplicate**: the same logic copied and maybe tweaked. Extract a shared function,
  generic or protocol extension.
- **a shared shape with different meaning**, such as simple getters or mapping code. Leave it
  alone, or suggest a `// similarity-ignore: <reason>` comment if it keeps showing up.
- **intentional parallel code**, such as generated code, tests or platform variants. Leave it,
  and consider `--exclude`.

Prefer the pairs with the highest priority (`--sort priority`): similarity × lines, so large
duplicates come first. With `--group`, declarations that are all similar to each other are listed
as one group, followed by the pairs between groups.

## Writing the plan

Work from the groups that `--group` reports (every two declarations in a group are similar), and
check the pairs between groups for declarations that belong with a group. For each group, give the
declarations with `file:line` locations, what they share and how they differ, the proposed
refactoring, and its risk (behavior differences to preserve, public API changes, tests to run). Order the groups by expected benefit. Don't change code until the user has agreed to the
plan, unless they asked you to go ahead.
