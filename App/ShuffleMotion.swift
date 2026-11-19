import CoreGraphics
import Foundation

struct ShuffleMotion {
    struct Pose {
        var center: CGPoint
        var angle: Double
    }

    struct Sweep {
        let time: Double
        let angle: Double
        let force: Double
    }

    static let duration = 2.45
    static let sweeps = [
        Sweep(time: 0, angle: -0.34, force: 1),
        Sweep(time: 0.45, angle: 2.78, force: 0.88),
        Sweep(time: 0.91, angle: 1.19, force: 0.98),
        Sweep(time: 1.39, angle: -1.82, force: 0.83),
        Sweep(time: 1.86, angle: 0.22, force: 0.57),
    ]
    private static let framesPerSecond = 60.0
    private static let frameCount = Int(duration * framesPerSecond)
    private static let tileSpacing = 0.072
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
        var pieces = (0..<30).map { index in
            let column = Double(index % 6)
            let row = Double(index / 6)
            let offset = Double((index * 19) % 13 - 6) / 500
            return Piece(pose: Pose(
                center: CGPoint(x: 0.24 + column * 0.100 + offset, y: 0.207 + row * 0.092 - offset),
                angle: Double((index * 13) % 23 - 11) * 0.09
            ))
        }
        var frames: [[Pose]] = []
        for frame in 0..<frameCount {
            for index in pieces.indices {
                for (pass, sweep) in sweeps.enumerated() {
                    // A push travels through the pile, with neighboring tiles reacting a few frames apart.
                    let stagger = (index * 3 + pass * 7) % 10
                    if frame == Int(sweep.time * framesPerSecond) + stagger {
                        nudge(&pieces[index], index: index, pass: pass, sweep: sweep)
                    }
                }
                pieces[index].pose.center.x += pieces[index].velocity.dx / framesPerSecond
                pieces[index].pose.center.y += pieces[index].velocity.dy / framesPerSecond
                pieces[index].pose.angle += pieces[index].spin / framesPerSecond
                pieces[index].velocity.dx *= 0.947
                pieces[index].velocity.dy *= 0.947
                pieces[index].spin *= 0.93
            }
            resolveContacts(&pieces)
            for index in pieces.indices { keepOnFelt(&pieces[index]) }
            frames.append(pieces.map(\.pose))
        }
        return frames
    }

    private static func nudge(_ piece: inout Piece, index: Int, pass: Int, sweep: Sweep) {
        let fan = Double((index * 7 + pass * 5) % 17 - 8) * 0.085
        let force = (0.68 + Double((index * 13 + pass) % 11) * 0.054) * sweep.force
        piece.velocity.dx += cos(sweep.angle + fan) * force
        piece.velocity.dy += sin(sweep.angle + fan) * force
        piece.spin += Double((index * 11 + pass * 3) % 13 - 6) * 0.72 * sweep.force
    }

    private static func keepOnFelt(_ piece: inout Piece) {
        let x = min(0.92, max(0.08, piece.pose.center.x))
        let y = min(0.70, max(0.08, piece.pose.center.y))
        if x != piece.pose.center.x { piece.velocity.dx *= -0.45 }
        if y != piece.pose.center.y { piece.velocity.dy *= -0.45 }
        piece.pose.center = CGPoint(x: x, y: y)
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
                let impulse = -toward * 0.63
                pieces[left].velocity.dx -= normal.dx * impulse
                pieces[left].velocity.dy -= normal.dy * impulse
                pieces[right].velocity.dx += normal.dx * impulse
                pieces[right].velocity.dy += normal.dy * impulse
                let twist = (relative.dx * normal.dy - relative.dy * normal.dx) * 1.4
                pieces[left].spin += twist
                pieces[right].spin -= twist
            }
        }
    }
}
