import FuzhouCore
import SwiftUI

struct DiscardDragPreview {
    let tile: Tile
    let isGold: Bool
    let source: Anchor<CGRect>
    let translation: CGSize

    struct Key: PreferenceKey {
        static var defaultValue: DiscardDragPreview? { nil }

        static func reduce(value: inout DiscardDragPreview?, nextValue: () -> DiscardDragPreview?) {
            if let next = nextValue() { value = next }
        }
    }
}

struct DiscardFlight: View {
    static let duration: TimeInterval = 0.24

    struct Motion: Equatable {
        let tile: Tile
        let isGold: Bool
        let globalSource: CGRect
        let seat: Seat
        let impact: TableImpact
        let id = UUID()
    }

    let tile: Tile
    let isGold: Bool
    let id: UUID
    let source: CGRect
    let destination: CGRect
    let finished: () -> Void
    @State private var started: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: started == nil)) { clock in
            let elapsed = started.map { clock.date.timeIntervalSince($0) } ?? 0
            let fraction = min(1, max(0, elapsed / Self.duration))
            let travel = 1 - (1 - fraction) * (1 - fraction)
            let lift = sin(fraction * .pi)
            let width = source.width + (destination.width - source.width) * travel
            let height = source.height + (destination.height - source.height) * travel
            TileFace(kind: tile.kind, gold: isGold)
                .frame(width: width, height: height)
                .rotationEffect(.degrees(lift * 9))
                .shadow(color: .black.opacity(lift * 0.5), radius: lift * 6, y: lift * 4)
                .position(x: source.midX + (destination.midX - source.midX) * travel,
                          y: source.midY + (destination.midY - source.midY) * travel - lift * 12)
        }
        .task(id: id) {
            started = .now
            do { try await Task.sleep(for: .seconds(Self.duration)) }
            catch { return }
            finished()
        }
    }

    static func inside(_ frame: CGRect, size: CGSize) -> CGRect {
        frame.offsetBy(dx: min(max(frame.minX, 0), max(0, size.width - frame.width)) - frame.minX,
                       dy: min(max(frame.minY, 0), max(0, size.height - frame.height)) - frame.minY)
    }
}
