import FuzhouCore
import SwiftUI

struct TableAnchors: PreferenceKey {
    enum Marker: Hashable {
        case center, felt, wall, reserve, wallStack(Int)
        case player(Seat), seatCard(Seat), rack(Int), drawn, openingDrawDock, latestDiscard, meldTile(Tile.ID)
    }

    static let defaultValue: [Marker: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Marker: Anchor<CGRect>], nextValue: () -> [Marker: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct OpeningDeal: View {
    nonisolated static let tileInterval = 0.040
    nonisolated static let flightDuration = 0.26
    static let stackingDuration = 0.46
    nonisolated static let tileCount = FuzhouMatch.rackSize * Seat.allCases.count
    nonisolated static let dealerArrival = Double(tileCount) * tileInterval + flightDuration

    enum Stage: Equatable {
        case shuffle(Date?)
        case stacking(Date)
        case deal(Date)
        case settled
        case flowers
        case revealGold

        var title: String {
            switch self {
            case .shuffle: "正在洗牌"
            case .stacking: "正在摆牌"
            case .deal, .settled: "正在发牌"
            case .flowers: "正在补花"
            case .revealGold: "开金"
            }
        }

        var isDealing: Bool {
            if case .deal = self { return true }
            return false
        }

        var showsWall: Bool {
            switch self {
            case .deal, .settled, .flowers, .revealGold: true
            default: false
            }
        }

        var showsFlowers: Bool { self == .flowers || self == .revealGold }

        func landed(for seat: Seat, dealer: Seat, at time: Date) -> Int {
            switch self {
            case .settled, .flowers, .revealGold: return FuzhouMatch.rackSize
            case .deal(let start):
                let age = time.timeIntervalSince(start) - Self.arrivalOffset(for: seat, dealer: dealer)
                guard age >= 0 else { return 0 }
                let circuit = OpeningDeal.tileInterval * Double(Seat.allCases.count)
                return min(FuzhouMatch.rackSize, Int(age / circuit) + 1)
            default: return 0
            }
        }

        func dealerTileLanded(at time: Date) -> Bool {
            if case .deal(let start) = self { return time.timeIntervalSince(start) >= OpeningDeal.dealerArrival }
            return showsWall
        }

        private static func arrivalOffset(for seat: Seat, dealer: Seat) -> TimeInterval {
            let position = (seat.id - dealer.id + Seat.allCases.count) % Seat.allCases.count
            return OpeningDeal.flightDuration + Double(position) * OpeningDeal.tileInterval
        }
    }

    let viewer: Seat
    let dealer: Seat
    let dealsDealerTile: Bool
    let stage: Stage
    let anchors: [TableAnchors.Marker: CGRect]
    @Environment(\.tileStyle) private var tileStyle

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30,
                                paused: stage == .shuffle(nil) || (stage.showsWall && !stage.isDealing))) { time in
            Canvas { context, _ in
                let back = context.resolve(Image(decorative: tileStyle.backArtwork))
                switch stage {
                case .shuffle(let start):
                    drawPile(in: context, back: back,
                             elapsed: start.map { max(0, time.date.timeIntervalSince($0)) } ?? 0)
                case .stacking(let start):
                    drawPile(in: context, back: back, elapsed: ShuffleMotion.duration,
                             stacking: progress(time.date.timeIntervalSince(start) / Self.stackingDuration))
                case .deal(let start):
                    drawFlights(in: context, back: back, elapsed: time.date.timeIntervalSince(start))
                case .settled, .flowers, .revealGold: break
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawPile(in context: GraphicsContext, back: GraphicsContext.ResolvedImage,
                          elapsed: TimeInterval, stacking: Double = 0) {
        guard let center = anchors[.center] else { return }
        // Leave room for the rotated tile backs and their depth inside the shuffle area.
        let spread = min(center.width * 0.95, center.height * 1.28, 300)
        let width = max(0, spread * 0.077)
        let wall = (0..<7).compactMap { anchors[.wallStack($0)] }
        for (index, pose) in ShuffleMotion.poses(at: elapsed).enumerated() {
            let from = CGPoint(x: center.midX + (pose.center.x - 0.5) * spread,
                               y: center.midY + (pose.center.y - 0.39) * spread)
            if stacking > 0, !wall.isEmpty {
                let stack = wall[index % wall.count]
                let to = CGPoint(x: stack.midX, y: stack.midY + Double(index / wall.count % 2) * 2)
                Self.drawBack(back, in: context, at: interpolate(from, to, stacking),
                              width: width + (stack.width - width) * stacking,
                              angle: pose.angle * (1 - stacking), depth: width * 0.15 * (1 - stacking))
            } else {
                Self.drawBack(back, in: context, at: from, width: width,
                              angle: pose.angle, depth: width * 0.15)
            }
        }
    }

    private func drawFlights(in context: GraphicsContext, back: GraphicsContext.ResolvedImage,
                             elapsed: TimeInterval) {
        guard let source = anchors[.wall] else { return }
        for index in 0..<(Self.tileCount + (dealsDealerTile ? 1 : 0)) {
            let age = elapsed - Double(index) * Self.tileInterval
            if age < 0 { break }
            guard age < Self.flightDuration else { continue }
            let seat = dealer.advanced(index % Seat.allCases.count)
            let slot = index / Seat.allCases.count
            let destination: CGRect
            if index == Self.tileCount {
                guard let target = anchors[dealer == viewer ? .drawn : .player(dealer)] else { continue }
                if dealer == viewer {
                    destination = target
                } else {
                    destination = Self.opponentDealerSlot(in: target)
                }
            } else if seat == viewer {
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

    static func opponentDealerSlot(in rack: CGRect) -> CGRect {
        let last = opponentSlot(FuzhouMatch.rackSize - 1, in: rack)
        return last.offsetBy(dx: last.width * 0.65, dy: -last.height * 0.60)
    }

    static func drawBack(_ back: GraphicsContext.ResolvedImage, in context: GraphicsContext,
                         at point: CGPoint, width: CGFloat, angle: Double = 0, depth: CGFloat = 0) {
        var tile = context
        tile.translateBy(x: point.x, y: point.y)
        tile.rotate(by: .radians(angle))
        let height = width * 1.4
        let face = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        if depth > 0 {
            var base = tile
            base.addFilter(.shadow(color: .black.opacity(0.48), radius: depth, y: depth))
            base.fill(Path(roundedRect: face.offsetBy(dx: 0, dy: depth), cornerRadius: width * 0.13),
                      with: .color(TeaTheme.porcelain.opacity(0.8)))
        }
        tile.draw(back, in: face)
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
