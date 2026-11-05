import Foundation

// MARK: - File Reading Utilities

/// Provides file reading utilities for Swift source files.
public class FileReader {
    
    /// Finds all Swift files in a directory.
    /// - Parameter directory: The directory path to search
    /// - Returns: Swift file paths, sorted so that results are reproducible
    /// - Throws: An error if `directory` is not an existing directory, or file system errors
    public static func findSwiftFiles(in directory: String) throws -> [String] {
        let url = URL(fileURLWithPath: directory)
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "FileReaderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not a directory: \(directory)"])
        }
        
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
        
        return swiftFiles.sorted()
    }
} 