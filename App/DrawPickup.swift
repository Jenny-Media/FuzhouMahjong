import SwiftUI

struct DrawPickup: View {
    static let duration = 0.66
    static let contactDelay = 0.12
    static let flowerDuration = 0.23

    struct Flight: Equatable {
        let fromReserve: Bool
        let duration: TimeInterval
        let started = Date.now
    }

    let flight: Flight
    let source: CGRect
    let destination: CGRect
    let isLocal: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45)) { time in
            let age = max(0, time.date.timeIntervalSince(flight.started))
            let t = min(1, age / flight.duration)
            let slide = t * t * (3 - 2 * t)
            let lift = sin(t * .pi)
            let x = source.midX + (destination.midX - source.midX) * slide
            let y = source.midY + (destination.midY - source.midY) * slide - lift * 16
            let landingWidth = isLocal ? max(0, destination.width - 2) : min(11, destination.width)
            let width = source.width + (landingWidth - source.width) * slide + lift * 12
            TileBack()
                .frame(width: width, height: width * 1.4)
                .rotationEffect(.degrees(lift * 14))
                .position(x: x, y: y)
                .opacity(max(0, min(1, (flight.duration - age) * (isLocal ? 45 : 15))))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
