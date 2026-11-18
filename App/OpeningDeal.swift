import FuzhouCore
import SwiftUI

struct OpeningDeal: View {
    static let tileInterval = 0.040
    static let flightDuration = 0.26
    private static let tileCount = FuzhouMatch.rackSize * Seat.allCases.count

    enum Stage: Equatable {
        case shuffle(Date?)
        case stacking
        case deal(Date)
        case settled

        var title: String {
            switch self {
            case .shuffle: "正在洗牌"
            case .stacking: "正在砌牌"
            case .deal, .settled: "正在发牌"
            }
        }

        var hasDealCount: Bool {
            switch self {
            case .deal, .settled: true
            default: false
            }
        }

        var isMoving: Bool {
            switch self {
            case .shuffle(.some), .deal: true
            default: false
            }
        }
    }

    let viewer: Seat
    let dealer: Seat
    let stage: Stage
    let reduceMotion: Bool
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !stage.isMoving)) { time in
                let dealt = landedTiles(at: time.date)
                VStack(spacing: 18) {
                    Canvas { context, size in
                        let back = context.resolve(Image("JadeTileBack"))
                        switch stage {
                        case .shuffle(let start):
                            let elapsed = reduceMotion ? 0 : start.map { max(0, time.date.timeIntervalSince($0)) } ?? 0
                            drawShuffle(in: context, size: size, back: back, elapsed: elapsed)
                        case .stacking, .deal, .settled:
                            drawWall(in: context, size: size, back: back, removed: dealt)
                            drawDeal(in: context, size: size, back: back, clock: time.date, landed: dealt)
                        }
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .modifier(Felt())
                    .clipShape(RoundedRectangle(cornerRadius: TeaTheme.tableCorner))
                    .accessibilityHidden(true)
                    VStack(spacing: 5) {
                        Text(stage.title)
                            .font(.title3.weight(.semibold))
                            .accessibilityIdentifier("opening-stage")
                        if stage.hasDealCount {
                            let offset = (viewer.id - dealer.id + 4) % 4
                            Text("手牌 \((dealt + 3 - offset) / 4) / \(FuzhouMatch.rackSize)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(TeaTheme.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 53)
                }
            }

            Button("跳过动画", action: skip)
                .buttonStyle(TeaButtonStyle(prominent: false))
                .accessibilityIdentifier("skip-opening")
        }
        .padding(TeaTheme.gutter)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HingeSafeContent())
    }

    private func landedTiles(at time: Date) -> Int {
        switch stage {
        case .settled: return Self.tileCount
        case .deal(let start):
            let elapsed = time.timeIntervalSince(start) - Self.flightDuration
            guard elapsed >= 0 else { return 0 }
            return min(Self.tileCount, Int(elapsed / Self.tileInterval) + 1)
        default: return 0
        }
    }

    private func drawShuffle(in context: GraphicsContext, size: CGSize,
                             back: GraphicsContext.ResolvedImage, elapsed: Double) {
        for pose in ShuffleMotion.poses(at: elapsed) {
            let position = CGPoint(x: pose.center.x * size.width, y: pose.center.y * size.width)
            drawBack(back, in: context, at: position, width: size.width * 0.055, angle: pose.angle, lift: 1)
        }
    }

    private func drawWall(in context: GraphicsContext, size: CGSize,
                          back: GraphicsContext.ResolvedImage, removed: Int) {
        let width = size.width * 0.026
        let stacks = max(0, 64 - removed / 2)
        for index in 0..<stacks {
            let side = index % 4
            let column = index / 4
            let offset = (Double(column) - 7.5) * width * 0.96
            let position: CGPoint
            switch side {
            case 0: position = CGPoint(x: size.width * 0.50 + offset, y: size.height * 0.72)
            case 1: position = CGPoint(x: size.width * 0.75, y: size.height * 0.50 + offset)
            case 2: position = CGPoint(x: size.width * 0.50 + offset, y: size.height * 0.28)
            default: position = CGPoint(x: size.width * 0.25, y: size.height * 0.50 + offset)
            }
            let angle = side.isMultiple(of: 2) ? 0.0 : .pi / 2
            drawBack(back, in: context, at: CGPoint(x: position.x, y: position.y + 2.5), width: width,
                     angle: angle, lift: 0.6)
            drawBack(back, in: context, at: position, width: width, angle: angle, lift: 0.8)
        }
    }

    private func drawDeal(in context: GraphicsContext, size: CGSize,
                          back: GraphicsContext.ResolvedImage, clock: Date, landed: Int) {
        let elapsed: Double
        if case .deal(let start) = stage { elapsed = clock.timeIntervalSince(start) }
        else { elapsed = -1 }
        let width = size.width * 0.031
        let source = CGPoint(x: size.width * 0.66, y: size.height * 0.28)

        for index in 0..<Self.tileCount {
            let age = elapsed - Double(index) * Self.tileInterval
            guard index < landed || age >= 0 else { break }
            let seat = dealer.advanced(index % 4)
            let side = (seat.id - viewer.id + 4) % 4
            let offset = (Double(index / 4) - 7.5) * width * 1.06
            let angle = side.isMultiple(of: 2) ? 0.0 : .pi / 2
            let destination: CGPoint
            switch side {
            case 0: destination = CGPoint(x: size.width * 0.50 + offset, y: size.height * 0.89)
            case 1: destination = CGPoint(x: size.width * 0.91, y: size.height * 0.50 + offset)
            case 2: destination = CGPoint(x: size.width * 0.50 - offset, y: size.height * 0.11)
            default: destination = CGPoint(x: size.width * 0.09, y: size.height * 0.50 - offset)
            }
            if index < landed {
                drawBack(back, in: context, at: destination, width: width, angle: angle, lift: 0.6)
            } else {
                let t = min(1, age / Self.flightDuration)
                let eased = t * t * (3 - 2 * t)
                let lift = sin(t * .pi)
                let point = CGPoint(x: source.x + (destination.x - source.x) * eased,
                                    y: source.y + (destination.y - source.y) * eased - lift * size.height * 0.055)
                drawBack(back, in: context, at: point, width: width * (1 + lift * 0.22),
                         angle: angle * eased, lift: 1 + lift * 3)
            }
        }
    }

    private func drawBack(_ back: GraphicsContext.ResolvedImage, in context: GraphicsContext,
                          at position: CGPoint, width: CGFloat, angle: Double, lift: CGFloat) {
        var tile = context
        tile.translateBy(x: position.x, y: position.y)
        tile.rotate(by: .radians(angle))
        tile.addFilter(.shadow(color: .black.opacity(0.37), radius: lift, y: lift))
        let height = width * 1.4
        tile.draw(back, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    }
}
