import Foundation

/// Writes a diagnostic line (progress, configuration, statistics) to standard error.
///
/// Standard output is reserved for the scan results, so `scan -f json` produces parseable JSON
/// and results can be piped regardless of the output format.
func printDiagnostic(_ message: String = "") {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
