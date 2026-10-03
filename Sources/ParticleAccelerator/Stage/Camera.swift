import Foundation
import simd

/// Where the stage is looked at from. Every visual is drawn through one, so every
/// visual has depth.
struct Camera: Equatable {
    var position: SIMD3<Float>
    var lookingAt: SIMD3<Float> = .zero
    /// A tilt of the picture, in radians.
    var roll: Float = 0
    /// How wide the view is, top to bottom, in radians.
    var fieldOfView: Float = 45 * .pi / 180
    /// The picture's width ÷ its height.
    var aspect: Float = 16.0 / 9.0
    /// Nothing nearer or further than these is drawn.
    var near: Float = 0.05
    var far: Float = 60

    /// Turns a place on the stage into a place in the picture, with perspective.
    var viewProjection: simd_float4x4 {
        projection * view
    }

    /// How far a point is in front of the camera, along the line of sight.
    func depth(of point: SIMD3<Float>) -> Float {
        simd_dot(point - position, simd_normalize(lookingAt - position))
    }

    private var view: simd_float4x4 {
        let backwards = simd_normalize(position - lookingAt)
        // "Up" leans over by the roll.
        let up = SIMD3<Float>(sin(roll), cos(roll), 0)
        let right = simd_normalize(simd_cross(up, backwards))
        let trueUp = simd_cross(backwards, right)
        return simd_float4x4(columns: (
            SIMD4(right.x, trueUp.x, backwards.x, 0),
            SIMD4(right.y, trueUp.y, backwards.y, 0),
            SIMD4(right.z, trueUp.z, backwards.z, 0),
            SIMD4(-simd_dot(right, position), -simd_dot(trueUp, position), -simd_dot(backwards, position), 1)))
    }

    private var projection: simd_float4x4 {
        let vertical = 1 / tan(fieldOfView / 2)
        let depthScale = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(vertical / aspect, 0, 0, 0),
            SIMD4(0, vertical, 0, 0),
            SIMD4(0, 0, depthScale, -1),
            SIMD4(0, 0, depthScale * near, 0)))
    }
}

/// Keeps the camera from ever standing still: a slow drift from side to side and up
/// and down, a gentle roll, a slow breath in and out, and a small punch towards the
/// stage on a beat.
///
/// Each movement is a few slow waves of different lengths added together. The lengths
/// share no common multiple worth the name, so the path never visibly repeats.
struct CameraDrift: Equatable {
    /// How far the camera sits from the middle of the stage.
    var distance: Float = 2.4
    /// How far it swings side to side and up and down, in radians.
    var sideways: Float = 0.10
    var upAndDown: Float = 0.035
    var roll: Float = 0.018
    /// How far it breathes in and out, as a share of the distance.
    var breath: Float = 0.03
    /// How far a full-strength beat punches it in, as a share of the distance.
    var punch: Float = 0.035

    /// The camera at a moment.
    /// - Parameters:
    ///   - time: seconds since the stage started.
    ///   - punchNow: from 0 (no beat) to 1 (a beat just landed).
    func camera(at time: Double, aspect: Float, punchNow: Float) -> Camera {
        let t = Float(time)
        let yaw = sideways * (0.65 * sin(t * 0.113) + 0.35 * sin(t * 0.047 + 1.3))
        let pitch = upAndDown * (0.6 * sin(t * 0.083 + 0.7) + 0.4 * sin(t * 0.031 + 2.9))
        let away = distance * (1 + breath * sin(t * 0.053 + 0.4) - punch * punchNow)
        let position = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * away
        return Camera(
            position: position, roll: roll * sin(t * 0.061 + 2.1), aspect: aspect)
    }
}
