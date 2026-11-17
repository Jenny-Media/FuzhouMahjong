import SwiftUI

struct DrawPickup: View {
    static let duration = 0.71
    static let contactDelay = 0.15

    let started: Date
    let wall: CGPoint
    let player: CGPoint

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45)) { time in
            let age = max(0, time.date.timeIntervalSince(started))
            let t = min(1, max(0, age - 0.08) / (Self.duration - 0.17))
            let slide = t * t * (3 - 2 * t)
            let lift = sin(t * .pi)
            let x = wall.x + (player.x - wall.x) * slide
            let y = wall.y + (player.y + 10 - wall.y) * slide - lift * 7
            let width = 12 + lift * 18
            TileBack()
                .frame(width: width, height: width * 1.4)
                .rotationEffect(.degrees(lift * 14))
                .shadow(color: .black.opacity(0.30), radius: 1 + lift * 4, y: 1 + lift * 5)
                .position(x: x, y: y)
                .opacity(max(0, min(1, (Self.duration - age) * 12)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
