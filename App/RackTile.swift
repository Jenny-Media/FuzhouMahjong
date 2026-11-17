import FuzhouCore
import SwiftUI

struct RackTile: View {
    let tile: Tile
    let isGold: Bool
    let isSelected: Bool
    let canSelect: Bool
    let canDiscard: Bool
    var rackCellWidth: CGFloat? = nil
    let select: () -> Void
    let discard: () -> Void
    var reposition: ((CGPoint) -> Void)? = nil
    var moveEarlier: (() -> Void)? = nil
    var moveLater: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var offset: CGSize = .zero

    var body: some View {
        let cellWidth = rackCellWidth ?? TeaTheme.hitTarget
        let faceWidth = max(0, cellWidth - (rackCellWidth == nil ? 4 : 1.5))
        let faceHeight = rackCellWidth == nil ? 52 : faceWidth / TileFace.artworkAspectRatio

        return Button(action: select) {
            TileFace(kind: tile.kind, gold: isGold, selected: isSelected || offset != .zero)
                .frame(width: faceWidth, height: faceHeight)
                .offset(x: reduceMotion ? 0 : offset.width,
                        y: reduceMotion ? 0 : offset.height - (isSelected ? 3 : 0))
                .frame(width: cellWidth, height: max(TeaTheme.hitTarget, faceHeight))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!canSelect)
        .highPriorityGesture(placement, including: canDiscard || reposition != nil ? .all : .none)
        .zIndex(offset != .zero ? 1 : 0)
        .accessibilityLabel(isGold ? "\(tile.kind.spokenName)，金牌" : tile.kind.spokenName)
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
                    offset = up > abs(drag.translation.width) ? CGSize(width: 0, height: -min(65, up)) : .zero
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
                if up >= 48 || projectedUp >= 77 { discard() }
            }
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.90 : 1)
        }
    }
}
