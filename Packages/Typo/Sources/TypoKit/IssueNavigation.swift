/// Which issue the jump bar's previous/next buttons go to.
public enum IssueNavigation {
    /// The offset of the issue after (or before) `caret`, wrapping around at the ends; nil without issues.
    public static func target(offsets: [Int], caret: Int, forward: Bool) -> Int? {
        let sorted = offsets.sorted()
        if forward { return sorted.first { $0 > caret } ?? sorted.first }
        return sorted.last { $0 < caret } ?? sorted.last
    }
}
