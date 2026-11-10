import ArgumentParser

// MARK: - Main CLI Tool

/// Swift code similarity detection tool entry point
@main
struct SwiftSimilarityCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-similarity-cli",
        abstract: "Finds similar Swift declarations (functions, initializers, types, protocols, extensions) by comparing their syntax trees",
        version: "0.0.2",
        subcommands: [ScanCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}