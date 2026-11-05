# Changelog

All notable changes to this project are documented in this file. Versions follow
[Semantic Versioning](https://semver.org); before 1.0.0, any release may change the command-line
interface, the output formats or the library API.

## 0.0.1

The first release. `swift-similarity-cli scan` finds similar Swift declarations by comparing their
syntax trees.

### Scanning
- Similarity is TSED ([arXiv:2404.08817](https://arxiv.org/abs/2404.08817)): the tree edit
  distance between SwiftSyntax trees, normalized by the larger tree. Identifiers and literals are
  compared by category only, so renaming a variable costs nothing (#1, #3).
- Element types: functions (default), initializers, structs, classes, enums, actors, protocols,
  extensions, or `all` (#14). A declaration is never compared with one nested inside it (#8).
- Exact pre-filters (label histograms, pre- and postorder sequence bounds) skip pairs that cannot
  reach the threshold without ever dropping one. Scans use every core and return results in a
  stable order (#3, #10, #15, #16, #21, #22).
- `--rename-cost` sets the cost of a node rename (default 1.0, as in the TSED paper) (#20).
- `--compare members` compares types, protocols and extensions by their members (kind, name and
  type), ignoring member order and bodies, and leaves protocol witnesses out (#23, #24).

### Choosing what to compare
- Several directories and `.swift` files, `--exclude` glob patterns, and a `similarity.toml`
  config file found in the current directory or a parent (#19).
- `--min-lines` (default 5) and `--min-tokens` skip small declarations, `--body-only` compares
  bodies only, and a `// similarity-ignore` comment skips a declaration (#17).

### Reporting
- Text and JSON output. Results go to stdout and diagnostics to stderr (#12).
- `--sort priority` puts large duplicates first, and `--fail-on-duplicates` exits with code 1 for
  CI (#18).
- `--group` reports declarations that are all similar to each other as one group (#27).
- `--filter-name` / `--filter-code` report the pairs involving a declaration of interest, and
  `--show-ignored` lists the declarations skipped by `similarity-ignore` (#25).
- `--advanced` adds structural, label and depth metrics to each pair (#7).
- `--format xcode` and `--format github` write warnings for Xcode build phases and GitHub Actions
  annotations (#28).

### Integration
- `swift package similarity`, a SwiftPM command plugin that scans the package's targets (#28).
- A Claude Code skill and prompts for using the results with AI assistants (#25).

### Removed
- The `--optimization` and `--hierarchical` options. They had no effect since every scan runs the
  same pipeline; passing them is now an error (exit code 64). Remove them from scripts.
