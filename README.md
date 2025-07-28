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
```

### Performance optimization
```bash
# Fast scanning for large projects
swift run swift-similarity-cli scan Sources/ --optimization aggressive

# High precision scanning
swift run swift-similarity-cli scan Sources/ --optimization conservative
```

### Advanced options
```bash
# Show progress and detailed statistics
swift run swift-similarity-cli scan Sources/ --progress --stats

# Include code previews in output
swift run swift-similarity-cli scan Sources/ --print

# Use advanced similarity metrics
swift run swift-similarity-cli scan Sources/ --advanced
```

## Inspired

This project was inspired by [mizchi/similarity](https://github.com/mizchi/similarity).

## License
MIT