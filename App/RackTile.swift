import FuzhouCore
import SwiftUI

struct RackTile: View {
    let tile: Tile
    let isGold: Bool
    let isSelected: Bool
    var isDrawn = false
    var isMeldCandidate = false
    let canSelect: Bool
    let canDiscard: Bool
    var rackCellWidth: CGFloat? = nil
    let select: () -> Void
    let discard: () -> Void
    var throwDiscard: ((CGRect, CGRect) -> Void)? = nil
    var reposition: ((CGPoint) -> Void)? = nil
    var moveEarlier: (() -> Void)? = nil
    var moveLater: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let showsPreview = throwDiscard != nil && canDiscard && !reduceMotion && offset != .zero

        return Button(action: select) {
            TileFace(kind: tile.kind, gold: isGold, selected: isSelected || offset != .zero)
                .frame(width: face.width, height: face.height)
                .overlay {
                    if isMeldCandidate {
                        RoundedRectangle(cornerRadius: face.width * 0.13)
                            .strokeBorder(TeaTheme.feltDark, style: StrokeStyle(lineWidth: 2.5, dash: [5, 2]))
                            .allowsHitTesting(false)
                    }
                }
                .offset(x: reduceMotion || showsPreview ? 0 : offset.width,
                        y: reduceMotion ? 0 : (showsPreview ? 0 : offset.height) - (isSelected ? 3 : 0))
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
        .highPriorityGesture(placement, including: canDiscard || reposition != nil ? .all : .none)
        .zIndex(offset != .zero ? 1 : 0)
        .accessibilityLabel(isDrawn ? "刚摸到，\(tileLabel)" : tileLabel)
        .accessibilityValue(isMeldCandidate ? "牌组候选" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tile-\(tile.id)")
        .accessibilityActions {
            if canDiscard { Button("出牌", action: discard) }
            if let moveEarlier { Button("前移", action: moveEarlier) }
            if let moveLater { Button("后移", action: moveLater) }
        }
    }

    private var placement: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($offset) { drag, offset, _ in
                if reposition != nil {
                    offset = drag.translation
                } else {
                    let up = -drag.translation.height
                    offset = up > abs(drag.translation.width) ? drag.translation : .zero
                }
            }
            .onEnded { drag in
                if let reposition {
                    reposition(drag.location)
                    return
                }
                let up = -drag.translation.height
                let projectedUp = -drag.predictedEndTranslation.height
                guard canDiscard, up >= 22, up > abs(drag.translation.width) * 1.2 else { return }
                guard up >= 48 || projectedUp >= 77 else { return }
                if !reduceMotion, let frame = faceFrame, let throwDiscard {
                    throwDiscard(frame, frame.offsetBy(dx: drag.translation.width, dy: drag.translation.height))
                } else {
                    discard()
                }
            }
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.90 : 1)
        }
    }
}
