import Foundation

extension Array where Element: Sendable {
    /// `map` that runs `transform` on all cores; the result keeps the order of the elements.
    func concurrentMap<T: Sendable>(_ transform: @Sendable (Element) -> T) -> [T] {
        [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            // Each iteration initializes only its own slot.
            nonisolated(unsafe) let buffer = buffer
            self.withUnsafeBufferPointer { elements in
                nonisolated(unsafe) let elements = elements
                DispatchQueue.concurrentPerform(iterations: elements.count) { index in
                    (buffer.baseAddress! + index).initialize(to: transform(elements[index]))
                }
            }
            initializedCount = count
        }
    }
}
