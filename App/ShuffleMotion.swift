import CoreGraphics
import Foundation

struct ShuffleMotion {
    struct Pose {
        var center: CGPoint
        var angle: Double
    }

    static let duration = 1.20
    private static let framesPerSecond = 60.0
    private static let frameCount = Int(duration * framesPerSecond)
    private static let tileSpacing = 0.057
    private static let frames: [[Pose]] = simulate()

    static func poses(at elapsed: Double) -> [Pose] {
        let frame = max(0, min(frameCount - 1, Int(elapsed * framesPerSecond)))
        return frames[frame]
    }

    private struct Piece {
        var pose: Pose
        var velocity = CGVector.zero
        var spin = 0.0
    }

    // Positions use the table's width as a unit on both axes.
    private static func simulate() -> [[Pose]] {
        var pieces = (0..<24).map { index in
            let column = Double(index % 6)
            let row = Double(index / 6)
            let offset = Double((index * 19) % 13 - 6) / 500
            return Piece(pose: Pose(
                center: CGPoint(x: 0.29 + column * 0.081 + offset, y: 0.267 + row * 0.078 - offset),
                angle: Double((index * 13) % 23 - 11) * 0.09
            ))
        }
        var frames: [[Pose]] = []
        for frame in 0..<frameCount {
            for index in pieces.indices {
                if frame == (index * 3) % 7 || frame == 19 + (index * 5) % 9 {
                    nudge(&pieces[index], index: index, secondPass: frame >= 19)
                }
                pieces[index].pose.center.x += pieces[index].velocity.dx / framesPerSecond
                pieces[index].pose.center.y += pieces[index].velocity.dy / framesPerSecond
                pieces[index].pose.angle += pieces[index].spin / framesPerSecond
                pieces[index].velocity.dx *= 0.92
                pieces[index].velocity.dy *= 0.92
                pieces[index].spin *= 0.90
            }
            resolveContacts(&pieces)
            frames.append(pieces.map(\.pose))
        }
        return frames
    }

    private static func nudge(_ piece: inout Piece, index: Int, secondPass: Bool) {
        let upper = index / 6 < 2
        let across = (upper == secondPass ? -1.0 : 1.0)
        let force = secondPass ? 0.68 : 1.0
        piece.velocity.dx += across * (0.34 + Double((index * 7) % 11) * 0.034) * force
        piece.velocity.dy += (Double((index * 3) % 9) - 4) * 0.036 * force
        piece.spin += (Double((index * 11) % 13) - 6) * 0.45 * force
    }

    private static func resolveContacts(_ pieces: inout [Piece]) {
        for left in pieces.indices {
            for right in (left + 1)..<pieces.count {
                let delta = CGVector(dx: pieces[right].pose.center.x - pieces[left].pose.center.x,
                                     dy: pieces[right].pose.center.y - pieces[left].pose.center.y)
                let distance = hypot(delta.dx, delta.dy)
                guard distance > 0, distance < tileSpacing else { continue }
                let normal = CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
                let separation = (tileSpacing - distance) / 2
                pieces[left].pose.center.x -= normal.dx * separation
                pieces[left].pose.center.y -= normal.dy * separation
                pieces[right].pose.center.x += normal.dx * separation
                pieces[right].pose.center.y += normal.dy * separation

                let relative = CGVector(dx: pieces[right].velocity.dx - pieces[left].velocity.dx,
                                        dy: pieces[right].velocity.dy - pieces[left].velocity.dy)
                let toward = relative.dx * normal.dx + relative.dy * normal.dy
                guard toward < 0 else { continue }
                let impulse = -toward * 0.55
                pieces[left].velocity.dx -= normal.dx * impulse
                pieces[left].velocity.dy -= normal.dy * impulse
                pieces[right].velocity.dx += normal.dx * impulse
                pieces[right].velocity.dy += normal.dy * impulse
            }
        }
    }
}
