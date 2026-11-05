import Foundation
import PackagePlugin

/// `swift package similarity [--target <name>]... [scan options]`
///
/// Runs `swift-similarity-cli scan` on the source directories of the given targets, or of every
/// Swift source target of the package except test targets when none is given. Every other
/// argument is passed to `scan`, so all of its options work, for example:
///
/// ```bash
/// swift package similarity --threshold 0.85 --group
/// swift package similarity --target App --format github --fail-on-duplicates
/// ```
///
/// The plugin only reads the package, so it needs no permissions unless `--output` writes a file
/// inside it (then run it with `--allow-writing-to-package-directory`).
@main
struct SimilarityPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let targetNames = extractor.extractOption(named: "target")
        let options = extractor.remainingArguments

        let modules: [SwiftSourceModuleTarget]
        if targetNames.isEmpty {
            modules = context.package.sourceModules
                .compactMap { $0 as? SwiftSourceModuleTarget }
                .filter { $0.kind != .test }
        } else {
            modules = try context.package.targets(named: targetNames).map { target in
                guard let module = target as? SwiftSourceModuleTarget else {
                    throw PluginError("'\(target.name)' is not a Swift source target")
                }
                return module
            }
        }
        guard !modules.isEmpty else {
            throw PluginError("The package has no Swift source targets to scan")
        }

        let tool = try context.tool(named: "swift-similarity-cli")
        let process = Process()
        process.executableURL = tool.url
        process.arguments = ["scan"] + modules.map(\.directoryURL.path) + options
        // Run in the package directory, so that `similarity.toml` there is found and GitHub
        // annotation paths are relative to it.
        process.currentDirectoryURL = context.package.directoryURL
        try process.run()
        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            // The tool has already explained the problem (or the duplicates, with
            // --fail-on-duplicates) on stderr and stdout.
            throw PluginError("swift-similarity-cli exited with status \(process.terminationStatus)")
        }
    }
}

struct PluginError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
