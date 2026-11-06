import Foundation
import ArgumentParser
import swift_similarity

// MARK: - Scan Command

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan directories and files for similar Swift declarations (functions, initializers, types, protocols, extensions) or protocol witnesses",
        discussion: """
            Settings are also read from the nearest \(SimilarityConfig.fileName) in the current directory \
            or one of its parents. Command-line options override it; see the README for the supported keys.
            """
    )
    
    @Argument(help: "Directories and .swift files to scan")
    var paths: [String]
    
    @Option(name: .long, help: ArgumentHelp("Skip files and directories matching a glob pattern (repeatable), such as 'Tests', '**/Generated/**' or '*.generated.swift'", valueName: "pattern"))
    var exclude: [String] = []
    
    @Option(name: .shortAndLong, help: "Type of code element to search (\(ScanCommand.elementTypeNames); default: \(ScanSettings.defaultElementType)). With --compare witnesses: \(ScanCommand.witnessElementTypeNames)")
    var elementType: String?
    
    @Option(name: .shortAndLong, help: "Similarity threshold (0.0-1.0; default: \(ScanSettings.defaultThreshold))")
    var threshold: Double?
    
    @Flag(name: .shortAndLong, help: "Also report structural, label and depth similarity for each pair (does not change which pairs are found)")
    var advanced: Bool = false
    
    @Option(name: .shortAndLong, help: "Output format: text, json, xcode (path:line:column: warning: lines for an Xcode Run Script phase) or github (GitHub Actions annotations); xcode and github write one warning per declaration that has similar declarations")
    var format: String = "text"
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?
    
    @Flag(name: [.customShort("p"), .customLong("print")], help: "Print code previews for similar elements")
    var showCode: Bool = false

    // MARK: - Filtering Options

    @Option(name: [.customShort("m"), .long], help: "Skip declarations shorter than this many lines (0 keeps all; default: \(ScanSettings.defaultMinLines))")
    var minLines: Int?

    @Option(name: .long, help: "Skip declarations with fewer tokens than this (0 keeps all; with --body-only, only the body's tokens count; default: \(ScanSettings.defaultMinTokens))")
    var minTokens: Int?

    @Flag(inversion: .prefixedNo, help: "Compare only bodies: code blocks of functions and initializers, member blocks of types (declarations without a body are skipped; default: off)")
    var bodyOnly: Bool?

    @Flag(inversion: .prefixedNo, help: "Skip declarations preceded by a 'similarity-ignore' comment; --no-ignore-directives compares them too (default: on)")
    var ignoreDirectives: Bool?

    // MARK: - Scoring Options

    @Option(name: .long, help: ArgumentHelp("What to compare: 'tree' (whole syntax trees, TSED), 'members' (the members of types, protocols and extensions: kind, name and type, ignoring order and bodies; element type defaults to all types) or 'witnesses' (bodies of implementations of the same requirement of a protocol declared in the scanned files, to find default implementation candidates; element type defaults to all members, minimum lines to 0) (default: \(ScanSettings.defaultCompare))", valueName: "mode"))
    var compare: String?

    @Option(name: .long, help: ArgumentHelp("Cost of renaming a node (changing its label, such as + to - or one syntax kind to another) in the tree edit distance; insertions and deletions cost 1. Lower values make structural variants score higher (default: \(ScanSettings.defaultRenameCost))", valueName: "cost"))
    var renameCost: Double?
    
    // MARK: - Performance Options
    
    @Flag(name: .long, help: "Show progress during similarity calculation")
    var progress: Bool = false
    
    @Option(name: .long, help: "Number of threads for parallel processing (0 for automatic)")
    var threads: Int = 0
    
    @Flag(name: .long, help: "Show pair counts and timings of the scan")
    var stats: Bool = false
    
    // MARK: - Reporting Options
    
    @Option(name: .long, help: "Result order: 'similarity' (score, highest first) or 'priority' (similarity × lines of the smaller declaration, so large duplicates come first; default: \(ScanSettings.defaultSort))")
    var sort: String?
    
    @Flag(inversion: .prefixedNo, help: "Exit with code 1 if any similar pair is found (for CI); results are still written (default: off)")
    var failOnDuplicates: Bool?
    
    @Option(name: .long, help: ArgumentHelp("Only report pairs in which a declaration's name contains this text (ignoring case)", valueName: "text"))
    var filterName: String?
    
    @Option(name: .long, help: ArgumentHelp("Only report pairs in which a declaration's source contains this text (case-sensitive); combined with --filter-name, one declaration must match both", valueName: "text"))
    var filterCode: String?
    
    @Flag(name: .long, help: "Also list the declarations skipped because of a 'similarity-ignore' comment")
    var showIgnored: Bool = false
    
    @Flag(inversion: .prefixedNo, help: "Report groups of declarations that are all similar to each other instead of every pair; pairs between groups are listed after them (default: off)")
    var group: Bool?
    
    mutating func validate() throws {
        for path in paths {
            do {
                try FileReader.validateInputPath(path)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
        applySettings(config: Self.loadConfig())
        let settings = resolvedSettings
        guard (0.0...1.0).contains(settings.threshold) else {
            throw ValidationError("Threshold must be between 0.0 and 1.0, got \(settings.threshold).")
        }
        guard let mode = CompareMode(rawValue: settings.compare.lowercased()) else {
            throw ValidationError("Invalid compare mode '\(settings.compare)'. Valid modes: \(CompareMode.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        switch mode {
        case .tree:
            guard Self.elementTypes(for: settings.elementType, mode: .tree) != nil else {
                throw ValidationError("Invalid element type '\(settings.elementType)'. Valid types: \(Self.elementTypeNames)")
            }
        case .members:
            guard Self.elementTypes(for: settings.elementType, mode: .members) != nil else {
                throw ValidationError("--compare members compares types, protocols and extensions, but the element type is '\(settings.elementType)'. Valid types: \(Self.memberElementTypeNames)")
            }
            guard !advanced else {
                throw ValidationError("--advanced reports syntax tree metrics and cannot be used with --compare members.")
            }
        case .witnesses:
            guard Self.elementTypes(for: settings.elementType, mode: .witnesses) != nil else {
                throw ValidationError("--compare witnesses compares members that implement protocol requirements, but the element type is '\(settings.elementType)'. Valid types: \(Self.witnessElementTypeNames)")
            }
        }
        guard Self.outputFormats.contains(format.lowercased()) else {
            throw ValidationError("Invalid output format '\(format)'. Valid formats: \(Self.outputFormats.joined(separator: ", "))")
        }
        guard settings.minLines >= 0 else {
            throw ValidationError("Minimum lines must be 0 (no limit) or more, got \(settings.minLines).")
        }
        guard settings.minTokens >= 0 else {
            throw ValidationError("Minimum tokens must be 0 (no limit) or more, got \(settings.minTokens).")
        }
        guard settings.renameCost >= 0, settings.renameCost.isFinite else {
            throw ValidationError("Rename cost must be a number 0 or more, got \(settings.renameCost).")
        }
        guard threads >= 0 else {
            throw ValidationError("Number of threads must be 0 (automatic) or more, got \(threads).")
        }
        guard SimilarityRanking.SortOrder(rawValue: settings.sort.lowercased()) != nil else {
            throw ValidationError("Invalid sort order '\(settings.sort)'. Valid orders: \(SimilarityRanking.SortOrder.allCases.map(\.rawValue).joined(separator: ", "))")
        }
    }
    
    mutating func run() async throws {
        // validate() filled in and checked these values.
        let settings = resolvedSettings
        let threshold = settings.threshold
        let minLines = settings.minLines
        let minTokens = settings.minTokens
        let bodyOnly = settings.bodyOnly
        // Option values are case-insensitive; normalize them for display and output.
        let elementType = settings.elementType.lowercased()
        format = format.lowercased()
        
        let compareMode = CompareMode(rawValue: settings.compare.lowercased())!
        let targetElementTypes = Self.elementTypes(for: elementType, mode: compareMode)!
        let sortOrder = SimilarityRanking.SortOrder(rawValue: settings.sort.lowercased())!
        
        printDiagnostic("Scanning: \(paths.joined(separator: ", "))")
        if !exclude.isEmpty {
            printDiagnostic("Exclude: \(exclude.joined(separator: ", "))")
        }
        let pairFilter = PairFilter(nameContains: filterName, codeContains: filterCode)
        if let name = pairFilter.nameContains {
            printDiagnostic("Filter: name contains '\(name)'")
        }
        if let code = pairFilter.codeContains {
            printDiagnostic("Filter: source contains '\(code)'")
        }
        printDiagnostic("Element type: \(elementType)")
        printDiagnostic("Threshold: \(threshold)")
        printDiagnostic("Minimum lines: \(minLines), minimum tokens: \(minTokens)")
        switch compareMode {
        case .tree:
            printDiagnostic("Compare: \(bodyOnly ? "bodies only" : "whole declarations")")
            printDiagnostic("Rename cost: \(settings.renameCost)")
        case .members:
            printDiagnostic("Compare: members (kind, name and type)")
        case .witnesses:
            printDiagnostic("Compare: bodies of implementations of the same protocol requirement")
            printDiagnostic("Rename cost: \(settings.renameCost)")
            if bodyOnly {
                printDiagnostic("Note: witnesses are always compared by their bodies; --body-only does not apply")
            }
        }
        printDiagnostic("Advanced metrics: \(advanced)")
        printDiagnostic("")
        
        var pairCount = 0
        do {
            // Extract code elements from the given paths
            // Witnesses are members collected separately; conformances are always collected.
            let extractorConfig = CodeElementExtractor.Configuration(
                elementTypes: compareMode == .witnesses ? [] : targetElementTypes,
                maxPreviewLines: 5,
                minLines: minLines,
                minTokens: minTokens,
                respectIgnoreDirectives: settings.ignoreDirectives,
                compareBodyOnly: bodyOnly,
                witnessCandidateTypes: compareMode == .witnesses ? targetElementTypes : []
            )
            let extractor = CodeElementExtractor(configuration: extractorConfig)
            let extraction = try extractor.extract(fromPaths: paths, excluding: exclude.map(ExcludePattern.init))
            let elements = extraction.elements
            
            let elementDescription = elementType == "all" ? "elements (all types)" : "\(elementType) elements"
            if compareMode != .witnesses {
                printDiagnostic("Found \(elements.count) \(elementDescription)")
            }
            
            let treeScanner = SimilarityScanner(
                maxConcurrency: threads,
                progressHandler: progress ? Self.printProgress : nil,
                costs: settings.operationCosts
            )
            let result: SimilarityScanner.Result
            switch compareMode {
            case .tree:
                result = try await treeScanner.scan(elements, threshold: threshold)
            case .members:
                result = MemberSimilarityScanner().scan(elements, threshold: threshold, conformances: extraction.conformances)
            case .witnesses:
                result = try await WitnessSimilarityScanner(scanner: treeScanner)
                    .scan(extraction.witnessCandidates, threshold: threshold, conformances: extraction.conformances)
                printDiagnostic("Found \(result.statistics.elementCount) implementations of requirements of protocols declared in the scanned files (\(extraction.witnessCandidates.count) members with a body)")
            }
            let unsortedPairs = pairFilter.apply(to: result.pairs).map { ($0.first, $0.second, $0.similarity) }
            let similarPairs = SimilarityRanking.sorted(unsortedPairs, by: sortOrder)
            
            if pairFilter.isEmpty {
                printDiagnostic("Found \(similarPairs.count) similar pairs")
            } else {
                printDiagnostic("Found \(result.pairs.count) similar pairs, \(similarPairs.count) matching the filter")
            }
            if showIgnored && !settings.ignoreDirectives {
                printDiagnostic("Note: --show-ignored lists nothing because similarity-ignore comments are not honored (--no-ignore-directives)")
            }
            
            if compareMode != .witnesses && elements.count < 2 {
                printDiagnostic("Need at least 2 \(elementDescription) to compare")
            }
            
            if stats {
                showStatistics(result.statistics, mode: compareMode)
            }
            
            // Create output formatter
            let formatter = OutputFormatter(
                elementType: elementType,
                threshold: threshold,
                advanced: advanced,
                costs: settings.operationCosts,
                compare: compareMode.rawValue,
                printCodePreviews: showCode,
                sortOrder: sortOrder,
                ignored: showIgnored ? extraction.ignored : nil,
                grouped: settings.group
            )
            
            if let style = DiagnosticFormatter.Style(rawValue: format) {
                if settings.group || showIgnored || showCode || advanced {
                    printDiagnostic("Note: --format \(format) writes one warning per declaration; --group, --show-ignored, --print and --advanced do not apply")
                }
                // GitHub resolves annotation paths against the repository root, which is the
                // working directory of a workflow step; Xcode needs absolute paths to open files.
                let currentDirectory = FileManager.default.currentDirectoryPath
                let diagnostics = DiagnosticFormatter.format(
                    similarPairs,
                    style: style,
                    relativeTo: style == .github ? currentDirectory : nil,
                    messagePathsRelativeTo: currentDirectory
                )
                try formatter.write(diagnostics, to: output)
            } else if format == "json" {
                try formatter.outputJSON(similarPairs: similarPairs, to: output)
            } else {
                try formatter.outputText(similarPairs: similarPairs, to: output)
            }
            
            pairCount = similarPairs.count
        } catch {
            printDiagnostic("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
        
        // Checked after the results are written, outside the do/catch so it is not reported as an error.
        if settings.failOnDuplicates && pairCount > 0 {
            printDiagnostic("Exiting with code 1: \(pairCount) similar pairs found (--fail-on-duplicates)")
            throw ExitCode.failure
        }
    }
    
    // MARK: - Helper Methods
    
    /// Reads the nearest config file, warning about problems with it on stderr.
    private static func loadConfig() -> SimilarityConfig? {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let url = SimilarityConfig.find(from: currentDirectory) else { return nil }
        do {
            let config = try SimilarityConfig.load(from: url)
            printDiagnostic("Using config: \(url.path)")
            for key in config.unknownKeys {
                printDiagnostic("Warning: \(url.path): unsupported key '\(key)' is ignored")
            }
            return config
        } catch {
            printDiagnostic("Warning: ignoring \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// The options given on the command line; nil for those that were not.
    private var commandLineSettings: SimilarityConfig {
        SimilarityConfig(
            threshold: threshold,
            elementType: elementType,
            exclude: exclude,
            minLines: minLines,
            minTokens: minTokens,
            bodyOnly: bodyOnly,
            ignoreDirectives: ignoreDirectives,
            sort: sort,
            failOnDuplicates: failOnDuplicates,
            renameCost: renameCost,
            compare: compare,
            group: group
        )
    }
    
    /// Every option, after applySettings filled in those not given on the command line.
    private var resolvedSettings: ScanSettings {
        ScanSettings.resolve(commandLine: commandLineSettings, file: nil)
    }
    
    /// Fills in options not given on the command line from the config file and defaults.
    private mutating func applySettings(config: SimilarityConfig?) {
        let settings = ScanSettings.resolve(commandLine: commandLineSettings, file: config)
        threshold = settings.threshold
        elementType = settings.elementType
        exclude = settings.exclude
        minLines = settings.minLines
        minTokens = settings.minTokens
        bodyOnly = settings.bodyOnly
        ignoreDirectives = settings.ignoreDirectives
        sort = settings.sort
        failOnDuplicates = settings.failOnDuplicates
        renameCost = settings.renameCost
        compare = settings.compare
        group = settings.group
    }
    
    /// Accepted `--format` values.
    static let outputFormats = ["text", "json"] + DiagnosticFormatter.Style.allCases.map(\.rawValue)
    
    /// Accepted `--element-type` values, for help and error messages.
    static let elementTypeNames = (CodeElementType.allCases.filter(treeElementTypes.contains).map(\.rawValue) + ["all"]).joined(separator: ", ")
    
    /// What `--compare` compares.
    enum CompareMode: String, CaseIterable {
        case tree
        case members
        case witnesses
    }
    
    /// Element types compared as syntax trees: declarations extracted on their own.
    static let treeElementTypes: Set<CodeElementType> = [.function, .initializer, .struct, .class, .enum, .actor, .protocol, .extension]
    
    /// Element types that have members, for `--compare members`.
    static let memberElementTypes: Set<CodeElementType> = [.struct, .class, .enum, .actor, .protocol, .extension]
    
    /// Accepted `--element-type` values with `--compare members`, for error messages.
    static let memberElementTypeNames = (CodeElementType.allCases.filter(memberElementTypes.contains).map(\.rawValue) + ["all"]).joined(separator: ", ")
    
    /// Kinds of members compared with `--compare witnesses`: methods (`function`), initializers,
    /// computed properties and subscripts.
    static let witnessElementTypes: Set<CodeElementType> = [.function, .initializer, .property, .subscript]
    
    /// Accepted `--element-type` values with `--compare witnesses`, for help and error messages.
    static let witnessElementTypeNames = (CodeElementType.allCases.filter(witnessElementTypes.contains).map(\.rawValue) + ["all"]).joined(separator: ", ")
    
    /// The element types selected by `--element-type`, or nil if the value is unknown or, with
    /// `--compare members`, names a declaration without members (with `--compare witnesses`, a
    /// declaration that cannot implement a requirement). `all` means all of them in that mode.
    private static func elementTypes(for value: String, mode: CompareMode) -> Set<CodeElementType>? {
        let value = value.lowercased()
        let available = switch mode {
        case .tree: treeElementTypes
        case .members: memberElementTypes
        case .witnesses: witnessElementTypes
        }
        if value == "all" {
            return available
        }
        return CodeElementType(rawValue: value).flatMap { available.contains($0) ? [$0] : nil }
    }
    
    /// Writes a progress line to stderr, ending it when a phase is done.
    private static func printProgress(_ progress: SimilarityScanner.Progress) {
        var text = "\r\(progress.phase == .fingerprinting ? "Fingerprinting" : "Comparing"): \(Int(progress.completionPercentage))%"
        if progress.pairsFound > 0 {
            text += " - \(progress.pairsFound) similar pairs"
        }
        if let remaining = progress.estimatedTimeRemaining, progress.completed < progress.total {
            text += " - ETA: \(String(format: "%.1f", remaining))s"
        }
        // Pad over the end of a longer previous line.
        text += "    "
        if progress.completed == progress.total {
            text += "\n"
        }
        try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
    }
    
    /// Shows pair counts and timings of the scan
    private func showStatistics(_ stats: ScanStatistics, mode: CompareMode) {
        func percent(_ count: Int) -> String {
            String(format: "%.1f%%", stats.totalPairs > 0 ? Double(count) / Double(stats.totalPairs) * 100 : 0)
        }
        printDiagnostic("\n=== Scan Statistics ===")
        printDiagnostic("Elements: \(stats.elementCount)")
        printDiagnostic("Threads: \(stats.workerCount)")
        printDiagnostic("Total pairs: \(stats.totalPairs)")
        printDiagnostic("  Nested (skipped): \(stats.nestedPairs) (\(percent(stats.nestedPairs)))")
        switch mode {
        case .tree, .witnesses:
            if mode == .witnesses {
                printDiagnostic("  (Only pairs implementing the same requirement are counted)")
            }
            printDiagnostic("  Ruled out by upper bound: \(stats.pairsRuledOutByUpperBound) (\(percent(stats.pairsRuledOutByUpperBound)))")
            printDiagnostic("  Compared with TSED: \(stats.pairsCompared) (\(percent(stats.pairsCompared)))")
        case .members:
            printDiagnostic("  Not comparable (different groups, too few members) or ruled out by member counts: \(stats.pairsRuledOutByUpperBound) (\(percent(stats.pairsRuledOutByUpperBound)))")
            printDiagnostic("  Compared by members: \(stats.pairsCompared) (\(percent(stats.pairsCompared)))")
        }
        printDiagnostic("Similar pairs: \(stats.similarPairs)")
        printDiagnostic("Fingerprint time: \(String(format: "%.3f", stats.fingerprintTime))s")
        printDiagnostic("Comparison time: \(String(format: "%.3f", stats.comparisonTime))s")
        printDiagnostic("Total time: \(String(format: "%.3f", stats.totalTime))s")
        printDiagnostic("=======================\n")
    }
}
