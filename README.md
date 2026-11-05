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
```

The file supports top-level `key = value` lines, `#` comments, strings, numbers, booleans and
arrays of strings; keys may also be written with `-` (`element-type`). Tables are not supported.
Unknown keys are ignored with a warning, and a file that cannot be read or parsed is ignored with
a warning on stderr.

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