import SwiftUI

enum FoldRegions {
    static func divisions(in geometry: GeometryProxy) -> [CGRect] {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // Active division frames already include the system's interaction margins.
            return geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }

    static func hasInteriorDivision(in size: CGSize, divisions: [CGRect]) -> Bool {
        let bounds = CGRect(origin: .zero, size: size)
        return divisions.contains { division in
            let overlap = bounds.intersection(division)
            guard !overlap.isEmpty else { return false }
            // Multitasking can expose a hinge reservation that only clips the window edge.
            let horizontal = division.width > division.height
            let roomOnEachSide = horizontal
                ? min(overlap.minY, bounds.maxY - overlap.maxY)
                : min(overlap.minX, bounds.maxX - overlap.maxX)
            return roomOnEachSide >= TeaTheme.hitTarget
        }
    }

    static func contentFrame(in size: CGSize, avoiding divisions: [CGRect], containing point: CGPoint? = nil) -> CGRect {
        var frames = [CGRect(origin: .zero, size: size)]
        for division in divisions {
            frames = frames.flatMap { frame in
                let intersection = frame.intersection(division)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return [frame] }
                return [
                    CGRect(x: frame.minX, y: frame.minY, width: intersection.minX - frame.minX, height: frame.height),
                    CGRect(x: intersection.maxX, y: frame.minY, width: frame.maxX - intersection.maxX, height: frame.height),
                    CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: intersection.minY - frame.minY),
                    CGRect(x: frame.minX, y: intersection.maxY, width: frame.width, height: frame.maxY - intersection.maxY)
                ].filter { $0.width > 0 && $0.height > 0 }
            }
        }
        let containingFrames = point.map { point in frames.filter { $0.contains(point) } } ?? []
        return (containingFrames.isEmpty ? frames : containingFrames).max {
            ($0.width * $0.height, $0.midY, $0.midX) < ($1.width * $1.height, $1.midY, $1.midX)
        } ?? .zero
    }
}

struct HingeSafeContent: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let frame = FoldRegions.contentFrame(in: geometry.size, avoiding: FoldRegions.divisions(in: geometry))
            content
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}
