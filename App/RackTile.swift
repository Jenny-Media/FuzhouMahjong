import FuzhouCore
import SwiftUI

struct RackTile: View {
    let tile: Tile
    let isGold: Bool
    let isSelected: Bool
    var isDrawn = false
    var drawLabel = "刚摸到"
    let canSelect: Bool
    let canDiscard: Bool
    var rackCellWidth: CGFloat? = nil
    let select: () -> Void
    let discard: () -> Void
    var throwDiscard: ((CGRect, CGRect) -> Void)? = nil
    var meldAction: (label: String, perform: () -> Void)? = nil
    var isRobGoldCandidate = false
    var swipeReady: (() -> Void)? = nil
    var reposition: ((CGPoint) -> Void)? = nil
    var moveEarlier: (() -> Void)? = nil
    var moveLater: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var drag = TileDrag()
    @State private var faceFrame: CGRect?

    private struct TileDrag {
        var offset: CGSize = .zero
        var reachedRelease = false
    }

    static func faceSize(for rackCellWidth: CGFloat?) -> CGSize {
        let faceWidth = max(0, (rackCellWidth ?? TeaTheme.hitTarget) - (rackCellWidth == nil ? 4 : 1.5))
        let faceHeight = rackCellWidth == nil ? 52 : faceWidth / TileFace.artworkAspectRatio
        return CGSize(width: faceWidth, height: faceHeight)
    }

    var body: some View {
        let cellWidth = rackCellWidth ?? TeaTheme.hitTarget
        let face = Self.faceSize(for: rackCellWidth)
        let tileLabel = isGold ? "\(tile.kind.spokenName)，金牌" : tile.kind.spokenName
        let isMeldCandidate = meldAction != nil
        let isCandidate = isMeldCandidate || isRobGoldCandidate
        let offset = drag.offset
        let showsPreview = (isMeldCandidate || (throwDiscard != nil && canDiscard)) && !reduceMotion && offset != .zero

        return Button(action: select) {
            TileFace(kind: tile.kind, gold: isGold, selected: isSelected || offset != .zero)
                .frame(width: face.width, height: face.height)
                .overlay {
                    if isCandidate {
                        let shape = RoundedRectangle(cornerRadius: face.width * 0.13)
                        shape.fill(TeaTheme.gain.opacity(isSelected ? 0 : 0.18)).blendMode(.multiply)
                            .overlay { shape.strokeBorder(isSelected ? TeaTheme.brass : TeaTheme.gain, lineWidth: 2) }
                            .allowsHitTesting(false)
                    }
                }
                .offset(x: reduceMotion || showsPreview ? 0 : offset.width,
                        y: reduceMotion ? 0 : (showsPreview ? 0 : offset.height) - (isSelected || isCandidate ? 3 : 0))
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                    if throwDiscard != nil { faceFrame = frame }
                }
                .anchorPreference(key: DiscardDragPreview.Key.self, value: .bounds) { anchor in
                    showsPreview ? DiscardDragPreview(tile: tile, isGold: isGold, source: anchor, translation: offset) : nil
                }
                .opacity(showsPreview ? 0 : 1)
                .frame(width: cellWidth, height: max(TeaTheme.hitTarget, face.height))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!canSelect)
        .highPriorityGesture(placement, including: canDiscard || meldAction != nil || reposition != nil ? .all : .none)
        .onChange(of: drag.reachedRelease) { _, reachedRelease in
            if reachedRelease { swipeReady?() }
        }
        .zIndex(offset != .zero ? 1 : 0)
        .accessibilityLabel(isDrawn ? "\(drawLabel)，\(tileLabel)" : tileLabel)
        .accessibilityValue(isRobGoldCandidate ? "可用于抢金" : isMeldCandidate ? "牌组候选" : "")
        .accessibilityHint(isRobGoldCandidate ? "轻点选择要换出的牌" : isMeldCandidate ? "轻点查看牌组" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tile-\(tile.id)")
        .accessibilityActions {
            if canDiscard { Button("出牌", action: discard) }
            if let meldAction { Button(meldAction.label, action: meldAction.perform) }
            if let moveEarlier { Button("前移", action: moveEarlier) }
            if let moveLater { Button("后移", action: moveLater) }
        }
    }

    private var placement: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($drag) { gesture, drag, _ in
                drag.offset = reposition != nil || isUpwardSwipe(gesture.translation) ? gesture.translation : .zero
                if swipeReady != nil, !drag.reachedRelease, canRelease(gesture) {
                    drag.reachedRelease = true
                }
            }
            .onEnded { drag in
                if let reposition {
                    reposition(drag.location)
                    return
                }
                guard canRelease(drag) else { return }
                if let meldAction {
                    meldAction.perform()
                } else if !reduceMotion, let frame = faceFrame, let throwDiscard {
                    throwDiscard(frame, frame.offsetBy(dx: drag.translation.width, dy: drag.translation.height))
                } else {
                    discard()
                }
            }
    }

    private func canRelease(_ drag: DragGesture.Value) -> Bool {
        let up = -drag.translation.height
        return (canDiscard || meldAction != nil) && up >= 22 && isUpwardSwipe(drag.translation) &&
            (up >= 48 || -drag.predictedEndTranslation.height >= 77)
    }

    private func isUpwardSwipe(_ translation: CGSize) -> Bool {
        let inward = layoutDirection == .leftToRight ? translation.width < 0 : translation.width > 0
        // The draw slot sits beside the rack, so a flick toward the felt can be more diagonal.
        let minimumRise: CGFloat = isDrawn && inward ? 0.55 : 1.2
        return -translation.height > abs(translation.width) * minimumRise
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.90 : 1)
        }
    }
}
