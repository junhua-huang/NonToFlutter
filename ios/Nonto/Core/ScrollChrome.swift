import Foundation

/// Ignore layout jumps and rubber banding; direction changes need real travel.
struct ScrollChrome {
    private(set) var hidden = false
    private var previous: Double?
    private var travel = 0.0
    mutating func reset() { hidden = false; previous = nil; travel = 0 }
    mutating func update(offset: Double, maximum: Double, userScrolling: Bool) {
        defer { previous = offset }
        guard userScrolling, maximum > 80 else { travel = 0; return }
        if offset <= 4 { hidden = false; travel = 0; return }
        guard offset <= maximum + 2, let previous else { return }
        let delta = offset - previous
        guard abs(delta) < 160 else { travel = 0; return }
        if delta * travel < 0 { travel = 0 }
        travel += delta
        if travel > 24 { hidden = true; travel = 0 }
        else if travel < -16 { hidden = false; travel = 0 }
    }
}
