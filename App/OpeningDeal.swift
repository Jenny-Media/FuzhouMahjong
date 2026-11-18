import FuzhouCore
import SwiftUI

struct TableAnchors: PreferenceKey {
    enum Marker: Hashable {
        case center, wall, reserve, wallStack(Int), player(Seat), rack(Int), drawn
    }

    static let defaultValue: [Marker: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Marker: Anchor<CGRect>], nextValue: () -> [Marker: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct OpeningDeal: View {
    nonisolated static let tileInterval = 0.040
    nonisolated static let flightDuration = 0.26
    static let stackingDuration = 0.33
    static let tileCount = FuzhouMatch.rackSize * Seat.allCases.count

    enum Stage: Equatable {
        case shuffle(Date?)
        case stacking(Date)
        case deal(Date)
        case settled

        var title: String {
            switch self {
            case .shuffle: "正在洗牌"
            case .stacking: "正在摆牌"
            case .deal, .settled: "正在发牌"
            }
        }

        var isDealing: Bool {
            if case .deal = self { return true }
            return false
        }

        var showsWall: Bool {
            switch self {
            case .deal, .settled: true
            default: false
            }
        }

        func landed(for seat: Seat, dealer: Seat, at time: Date) -> Int {
            switch self {
            case .settled: return FuzhouMatch.rackSize
            case .deal(let start):
                let age = time.timeIntervalSince(start) - Self.arrivalOffset(for: seat, dealer: dealer)
                guard age >= 0 else { return 0 }
                let circuit = OpeningDeal.tileInterval * Double(Seat.allCases.count)
                return min(FuzhouMatch.rackSize, Int(age / circuit) + 1)
            default: return 0
            }
        }

        private static func arrivalOffset(for seat: Seat, dealer: Seat) -> TimeInterval {
            let position = (seat.id - dealer.id + Seat.allCases.count) % Seat.allCases.count
            return OpeningDeal.flightDuration + Double(position) * OpeningDeal.tileInterval
        }
    }

    let viewer: Seat
    let dealer: Seat
    let stage: Stage
    let anchors: [TableAnchors.Marker: CGRect]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: stage == .shuffle(nil) || stage == .settled)) { time in
            Canvas { context, _ in
                let back = context.resolve(Image("JadeTileBack"))
                switch stage {
                case .shuffle(let start):
                    drawPile(in: context, back: back,
                             elapsed: start.map { max(0, time.date.timeIntervalSince($0)) } ?? 0)
                case .stacking(let start):
                    drawPile(in: context, back: back, elapsed: ShuffleMotion.duration,
                             stacking: progress(time.date.timeIntervalSince(start) / Self.stackingDuration))
                case .deal(let start):
                    drawFlights(in: context, back: back, elapsed: time.date.timeIntervalSince(start))
                case .settled: break
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawPile(in context: GraphicsContext, back: GraphicsContext.ResolvedImage,
                          elapsed: TimeInterval, stacking: Double = 0) {
        guard let center = anchors[.center] else { return }
        let spread = min(center.width * 0.95, center.height * 1.75, 300)
        let width = max(0, spread * 0.071)
        let wall = (0..<7).compactMap { anchors[.wallStack($0)] }
        for (index, pose) in ShuffleMotion.poses(at: elapsed).enumerated() {
            let from = CGPoint(x: center.midX + (pose.center.x - 0.5) * spread,
                               y: center.midY + (pose.center.y - 0.39) * spread)
            if stacking > 0, !wall.isEmpty {
                let stack = wall[index % wall.count]
                let to = CGPoint(x: stack.midX, y: stack.midY + Double(index / wall.count % 2) * 2)
                Self.drawBack(back, in: context, at: interpolate(from, to, stacking),
                              width: width + (stack.width - width) * stacking,
                              angle: pose.angle * (1 - stacking))
            } else {
                Self.drawBack(back, in: context, at: from, width: width, angle: pose.angle)
            }
        }
    }

    private func drawFlights(in context: GraphicsContext, back: GraphicsContext.ResolvedImage,
                             elapsed: TimeInterval) {
        guard let source = anchors[.wall] else { return }
        for index in 0..<Self.tileCount {
            let age = elapsed - Double(index) * Self.tileInterval
            if age < 0 { break }
            guard age < Self.flightDuration else { continue }
            let seat = dealer.advanced(index % Seat.allCases.count)
            let slot = index / Seat.allCases.count
            let destination: CGRect
            if seat == viewer {
                guard let cell = anchors[.rack(slot)] else { continue }
                destination = cell
            } else {
                guard let rack = anchors[.player(seat)] else { continue }
                destination = Self.opponentSlot(slot, in: rack)
            }
            let fraction = progress(age / Self.flightDuration)
            let lift = sin(fraction * .pi)
            var point = interpolate(source.center, destination.center, fraction)
            point.y -= lift * 13
            let width = source.width + (max(0, destination.width - 1) - source.width) * fraction + lift * 7
            Self.drawBack(back, in: context, at: point, width: width, angle: lift * 0.16)
        }
    }

    static func opponentSlot(_ index: Int, in rack: CGRect) -> CGRect {
        let columns = FuzhouMatch.rackSize / 2
        let width = max(0, min(9, (rack.width - 3) / CGFloat(columns), (rack.height - 2) / 2.8))
        let height = width * 1.4
        let column = index % columns
        let row = index / columns
        return CGRect(x: rack.midX + (CGFloat(column) - CGFloat(columns) / 2) * (width + 0.35),
                      y: rack.midY + (CGFloat(row) - 1) * (height + 0.6),
                      width: width, height: height)
    }

    static func drawBack(_ back: GraphicsContext.ResolvedImage, in context: GraphicsContext,
                         at point: CGPoint, width: CGFloat, angle: Double = 0) {
        var tile = context
        tile.translateBy(x: point.x, y: point.y)
        tile.rotate(by: .radians(angle))
        let height = width * 1.4
        tile.draw(back, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    }

    private func progress(_ time: Double) -> Double {
        let t = min(1, max(0, time))
        return t * t * (3 - 2 * t)
    }

    private func interpolate(_ start: CGPoint, _ end: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
