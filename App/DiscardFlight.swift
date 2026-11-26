import FuzhouCore
import SwiftUI

struct RackDragPreview {
    struct Face: Identifiable {
        let tile: Tile
        let isGold: Bool
        var fromRack = true
        var id: Tile.ID { tile.id }
    }

    struct Preferences {
        var preview: RackDragPreview?
        var rackFaces: [Tile.ID: Anchor<CGRect>] = [:]
        var rackBounds: Anchor<CGRect>?
    }

    let faces: [Face]
    let grabbedID: Tile.ID
    let source: Anchor<CGRect>
    let translation: CGSize
    let stationary: Bool

    struct Key: PreferenceKey {
        static var defaultValue: Preferences { Preferences() }

        static func reduce(value: inout Preferences, nextValue: () -> Preferences) {
            let next = nextValue()
            if let preview = next.preview { value.preview = preview }
            value.rackFaces.merge(next.rackFaces) { _, latest in latest }
            if let rackBounds = next.rackBounds { value.rackBounds = rackBounds }
        }
    }

    static func meldFaces(for options: [Move], table: TableState, showsGold: Bool) -> [Face]? {
        guard options.count == 1, case .meld(_, let ids) = options[0] else { return nil }
        return table.tiles(inMeld: options[0]).map { tile in
            Face(tile: tile, isGold: showsGold && table.isGold(tile), fromRack: ids.contains(tile.id))
        }
    }

    static func tableTileOutline(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.13)
            .strokeBorder(TeaTheme.brass, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
    }

    struct Layout {
        let tileSize: CGSize
        let spacing: CGFloat
        let frame: CGRect

        init(source: CGRect, translation: CGSize, count: Int, grabbedIndex: Int, bounds: CGRect,
             rackTop: CGFloat? = nil, stationary: Bool = false) {
            let gap = count > 1 ? source.width * 0.065 : 0
            let width = source.width * CGFloat(count) + gap * CGFloat(count - 1)
            let bottom = rackTop.map { min(bounds.maxY, $0 - 6) } ?? bounds.maxY
            let allowedSize = CGSize(width: bounds.width, height: max(0, bottom - bounds.minY))
            let scale = min(1, allowedSize.width / width, allowedSize.height / source.height)
            tileSize = CGSize(width: source.width * scale, height: source.height * scale)
            spacing = gap * scale
            let x = source.midX + (stationary ? 0 : translation.width)
                - tileSize.width / 2 - CGFloat(grabbedIndex) * (tileSize.width + spacing)
            let y = stationary ? bottom - tileSize.height : source.midY + translation.height - tileSize.height / 2
            let desired = CGRect(x: x - bounds.minX, y: y - bounds.minY, width: width * scale, height: tileSize.height)
            frame = DiscardFlight.inside(desired, size: allowedSize).offsetBy(dx: bounds.minX, dy: bounds.minY)
        }
    }
}

struct RackDragOverlay: View {
    let preview: RackDragPreview
    let rackFaces: [Tile.ID: Anchor<CGRect>]
    let rackBounds: Anchor<CGRect>?
    let divisions: [CGRect]
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            let source = geometry[preview.source]
            if !source.isEmpty, let grabbed = preview.faces.firstIndex(where: { $0.id == preview.grabbedID }) {
                let group = preview.faces.count > 1
                let bounds = group
                    ? FoldRegions.contentFrame(in: geometry.size, avoiding: divisions,
                                               containing: CGPoint(x: source.midX, y: source.midY))
                    : CGRect(origin: .zero, size: geometry.size)
                let index = layoutDirection == .rightToLeft ? preview.faces.count - 1 - grabbed : grabbed
                let contributorRects = preview.faces.filter(\.fromRack).compactMap { face in
                    rackFaces[face.id].map { geometry[$0] }
                }
                let rackTop = group
                    ? contributorRects.reduce(rackBounds.map { geometry[$0].minY } ?? source.minY) { min($0, $1.minY) }
                    : nil
                let layout = RackDragPreview.Layout(source: source, translation: preview.translation,
                                                    count: preview.faces.count, grabbedIndex: index, bounds: bounds,
                                                    rackTop: rackTop, stationary: preview.stationary)
                if group {
                    ForEach(preview.faces.filter(\.fromRack)) { face in
                        if let anchor = rackFaces[face.id] {
                            let rect = geometry[anchor]
                            RoundedRectangle(cornerRadius: rect.width * 0.13)
                                .strokeBorder(TeaTheme.brass, lineWidth: 2.5)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                HStack(spacing: layout.spacing) {
                    ForEach(preview.faces) { face in
                        TileFace(kind: face.tile.kind, gold: face.isGold, selected: face.fromRack)
                            .frame(width: layout.tileSize.width, height: layout.tileSize.height)
                            .overlay {
                                if !face.fromRack {
                                    RackDragPreview.tableTileOutline(width: layout.tileSize.width)
                                }
                            }
                    }
                }
                .fixedSize()
                .shadow(color: .black.opacity(0.46), radius: 6, y: 4)
                .position(x: layout.frame.midX, y: layout.frame.midY)
            }
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
