import Foundation

extension Array where Element: Sendable {
    /// `map` that runs `transform` in parallel; the result keeps the order of the elements.
    /// - Parameter maxConcurrency: At most this many elements are transformed at the same time;
    ///   0 (the default) uses all cores.
    func concurrentMap<T: Sendable>(maxConcurrency: Int = 0, _ transform: @Sendable (Element) -> T) -> [T] {
        [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            // Each iteration initializes only its own slots.
            nonisolated(unsafe) let buffer = buffer
            self.withUnsafeBufferPointer { elements in
                nonisolated(unsafe) let elements = elements
                if maxConcurrency <= 0 {
                    DispatchQueue.concurrentPerform(iterations: elements.count) { index in
                        (buffer.baseAddress! + index).initialize(to: transform(elements[index]))
                    }
                } else {
                    // One iteration per worker, each taking every `workers`-th element so that
                    // workers get a similar share of elements that cost more toward one end.
                    let workers = Swift.min(maxConcurrency, elements.count)
                    DispatchQueue.concurrentPerform(iterations: workers) { worker in
                        for index in stride(from: worker, to: elements.count, by: workers) {
                            (buffer.baseAddress! + index).initialize(to: transform(elements[index]))
                        }
                    }
                }
            }
            initializedCount = count
        }
    }
}
