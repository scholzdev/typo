import Foundation
import QuartzCore

/// Geometry of the fold animation, as Xcode does it: a placeholder of animated height sits in the layout under the fold
/// line, and a snapshot of the folding lines fills it as paper folded in two. The top half hangs from the fold line and
/// the bottom half stands on the placeholder's bottom edge; both tilt about the horizontal axis so their seam comes
/// towards the viewer. Unfolding runs the same backwards.
public enum FoldPaper {
    public static let duration: Double = 0.3

    /// Cubic ease-in-out of linear progress `t` (clamped to 0...1).
    public static func eased(_ t: Double) -> CGFloat {
        let t = min(max(t, 0), 1)
        return CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
    }

    /// The placeholder's height at eased progress `e`: `full` shrinking to nothing when folding, growing back when not.
    public static func height(full: CGFloat, eased e: CGFloat, folding: Bool) -> CGFloat { full * (folding ? 1 - e : e) }

    /// The panels' tilt: two halves of `full` tilted by the angle span `current` (current = full × cos angle).
    public static func angle(current: CGFloat, full: CGFloat) -> CGFloat {
        guard full > 0 else { return .pi / 2 }
        return acos(min(max(current / full, 0), 1))
    }

    /// Viewer distance for the perspective: far enough that the near seam never passes the eye.
    public static func eyeDistance(full: CGFloat) -> CGFloat { 2 * max(full, 300) }

    /// A panel's transform about its anchor, the edge it hangs on (top panel: its top edge; bottom: its bottom edge).
    /// Layer coordinates are y-up, so the top panel's free edge lies below its anchor and the bottom panel's above.
    public static func panel(top: Bool, angle: CGFloat, full: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m34 = -1 / eyeDistance(full: full)
        return CATransform3DRotate(t, top ? -angle : angle, 1, 0, 0)
    }

    /// The black shade over a panel at `angle`: darker as it tilts away from the light, the lower half more.
    public static func shade(top: Bool, angle: CGFloat) -> Float { Float((top ? 0.12 : 0.3) * angle / (.pi / 2)) }

    /// Where `transform` puts the point (x, y, 0) of a layer plane, projected back to the plane (x, y).
    public static func project(_ x: CGFloat, _ y: CGFloat, _ t: CATransform3D) -> CGPoint {
        let w = x * t.m14 + y * t.m24 + t.m44
        return CGPoint(x: (x * t.m11 + y * t.m21 + t.m41) / w, y: (x * t.m12 + y * t.m22 + t.m42) / w)
    }
}
