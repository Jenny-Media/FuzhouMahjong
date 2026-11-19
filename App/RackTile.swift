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
    var reposition: ((CGPoint) -> Void)? = nil
    var moveEarlier: (() -> Void)? = nil
    var moveLater: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var offset: CGSize = .zero
    @State private var faceFrame: CGRect?

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
        let showsPreview = (isMeldCandidate || (throwDiscard != nil && canDiscard)) && !reduceMotion && offset != .zero

        return Button(action: select) {
            TileFace(kind: tile.kind, gold: isGold, selected: isSelected || offset != .zero)
                .frame(width: face.width, height: face.height)
                .overlay {
                    if isMeldCandidate {
                        let shape = RoundedRectangle(cornerRadius: face.width * 0.13)
                        shape.fill(TeaTheme.gain.opacity(0.46)).blendMode(.multiply)
                            .overlay { shape.strokeBorder(TeaTheme.feltDark.opacity(0.68), lineWidth: 1.5) }
                            .allowsHitTesting(false)
                    }
                }
                .offset(x: reduceMotion || showsPreview ? 0 : offset.width,
                        y: reduceMotion ? 0 : (showsPreview ? 0 : offset.height) - (isSelected || isMeldCandidate ? 3 : 0))
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
        .zIndex(offset != .zero ? 1 : 0)
        .accessibilityLabel(isDrawn ? "\(drawLabel)，\(tileLabel)" : tileLabel)
        .accessibilityValue(isMeldCandidate ? "牌组候选" : "")
        .accessibilityHint(isMeldCandidate ? "轻点查看牌组" : "")
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
            .updating($offset) { drag, offset, _ in
                offset = reposition != nil || isUpwardSwipe(drag.translation) ? drag.translation : .zero
            }
            .onEnded { drag in
                if let reposition {
                    reposition(drag.location)
                    return
                }
                let up = -drag.translation.height
                let projectedUp = -drag.predictedEndTranslation.height
                guard canDiscard || meldAction != nil, up >= 22, isUpwardSwipe(drag.translation) else { return }
                guard up >= 48 || projectedUp >= 77 else { return }
                if let meldAction {
                    meldAction.perform()
                } else if !reduceMotion, let frame = faceFrame, let throwDiscard {
                    throwDiscard(frame, frame.offsetBy(dx: drag.translation.width, dy: drag.translation.height))
                } else {
                    discard()
                }
            }
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
