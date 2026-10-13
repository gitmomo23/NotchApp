import CoreGraphics

struct SpringValue {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0
    var stiffness: CGFloat = 320
    var damping: CGFloat = 28

    mutating func step(dt: CGFloat) -> Bool {
        let displacement = value - target
        let acceleration = (-stiffness * displacement) - (damping * velocity)
        velocity += acceleration * dt
        value += velocity * dt
        if abs(value - target) < 0.0008 && abs(velocity) < 0.02 {
            value = target
            velocity = 0
            return true
        }
        return false
    }

    mutating func snap() {
        value = target
        velocity = 0
    }
}
