import ArgumentParser

// MARK: - Main CLI Tool

/// Swift code similarity detection tool entry point
@main
struct SwiftSimilarityCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-similarity",
        abstract: "A Swift code similarity detection tool for finding similar functions, structs, and classes",
        version: "1.0.0",
        subcommands: [ScanCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}