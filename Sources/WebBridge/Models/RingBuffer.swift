import Foundation

/// Fixed-capacity FIFO buffer. Oldest entries drop off once capacity is exceeded.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private(set) var capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    var elements: [Element] { storage }
    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var last: Element? { storage.last }

    mutating func append(_ element: Element) {
        storage.append(element)
        trim()
    }

    mutating func append(contentsOf newElements: [Element]) {
        storage.append(contentsOf: newElements)
        trim()
    }

    mutating func replaceLast(_ element: Element) {
        guard !storage.isEmpty else { return append(element) }
        storage[storage.count - 1] = element
    }

    mutating func clear() { storage.removeAll(keepingCapacity: true) }

    mutating func setCapacity(_ newValue: Int) {
        capacity = max(1, newValue)
        trim()
    }

    private mutating func trim() {
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }
}
