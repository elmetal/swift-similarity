import Foundation

// MARK: - File Reading Utilities

/// Provides file reading utilities for Swift source files.
public class FileReader {
    
    /// Finds all Swift files in a directory.
    /// - Parameter directory: The directory path to search
    /// - Returns: Array of Swift file paths
    /// - Throws: File system errors
    public static func findSwiftFiles(in directory: String) throws -> [String] {
        let url = URL(fileURLWithPath: directory)
        let fileManager = FileManager.default
        
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "FileReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create file enumerator"])
        }
        
        var swiftFiles: [String] = []
        
        while let element = enumerator.nextObject() {
            guard let fileURL = element as? URL else { continue }
            
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile == true && fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL.path)
            }
        }
        
        return swiftFiles
    }
} 