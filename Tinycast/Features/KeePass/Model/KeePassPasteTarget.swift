enum KeePassPasteTarget {
    static func index(processIDs: [Int32?], ownProcessID: Int32, terminated: Set<Int32>) -> Int? {
        processIDs.indices.first { index in
            guard let processID = processIDs[index] else { return false }
            return processID != ownProcessID && !terminated.contains(processID)
        }
    }
}
