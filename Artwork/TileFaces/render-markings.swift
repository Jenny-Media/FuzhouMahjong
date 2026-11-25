import CoreGraphics
import CoreText
import Foundation
import ImageIO

// Run from the project root with swift Artwork/TileFaces/render-markings.swift.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let references = root.appending(path: "Artwork/TileFaces")
let catalog = root.appending(path: "App/Assets.xcassets/TileMarkings")
let cellWidth = 192
let cellHeight = 268
let columns = 7
let rows = 6
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let alphaFormat = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

enum Style: String, CaseIterable {
    case photoMatched, minimal, traditional

    var sheet: String {
        switch self {
        case .photoMatched: "approved-default"
        case .minimal: "approved-minimal"
        case .traditional: "approved-traditional"
        }
    }

    var asset: String {
        switch self {
        case .photoMatched: "PhotoMatchedMarkings"
        case .minimal: "MinimalMarkings"
        case .traditional: "TraditionalMarkings"
        }
    }

    var numeralBox: CGRect {
        switch self {
        case .photoMatched: CGRect(x: 36, y: 143, width: 120, height: 86)
        case .minimal: CGRect(x: 42, y: 143, width: 108, height: 84)
        case .traditional: CGRect(x: 33, y: 140, width: 126, height: 90)
        }
    }

    var honorBox: CGRect {
        switch self {
        case .photoMatched: CGRect(x: 25, y: 51, width: 142, height: 166)
        case .minimal: CGRect(x: 31, y: 59, width: 130, height: 150)
        case .traditional: CGRect(x: 21, y: 48, width: 150, height: 172)
        }
    }

    var addedStroke: CGFloat {
        switch self {
        case .photoMatched: 3.5
        case .minimal: 0
        case .traditional: 5
        }
    }
}

func bitmap(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: colorSpace, bitmapInfo: alphaFormat)!
    context.interpolationQuality = .high
    return context
}

func load(_ url: URL) -> CGImage {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

// The approved review boards share a registered grid. Recover pigment coverage
// from the tile interior, then remove the sampled neutral substrate.
func extractInk(_ source: CGImage, rect: CGRect) -> CGImage {
    let crop = source.cropping(to: rect)!
    let context = bitmap(crop.width, crop.height)
    context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let paper = [229.0, 225.0, 213.0]

    for offset in stride(from: 0, to: crop.width * crop.height * 4, by: 4) {
        let pixel = data.advanced(by: offset)
        let darkest = Double(min(pixel[0], pixel[1], pixel[2]))
        let lightest = Double(max(pixel[0], pixel[1], pixel[2]))
        let alpha = darkest < 204 && (lightest - darkest > 24 || lightest < 170)
            ? min(1, (213 - darkest) / 183)
            : 0
        for channel in 0..<3 {
            let pigment = Double(pixel[channel]) - paper[channel] * (1 - alpha)
            pixel[channel] = UInt8(max(0, min(255 * alpha, pigment)).rounded())
        }
        pixel[3] = UInt8((255 * alpha).rounded())
    }
    return context.makeImage()!
}

func tileSample(_ source: CGImage, column: Int, row: Int) -> CGImage {
    let left = [83, 368, 650, 933, 1217][column]
    let top = [33, 351, 676][row]
    let height = [291, 297, 303][row]
    let insetX = 13
    let insetY = 12
    let ink = extractInk(source, rect: CGRect(x: left + insetX, y: top + insetY,
                                             width: 235 - 2 * insetX, height: height - 2 * insetY))
    let context = bitmap(cellWidth, cellHeight)
    let scale = min(CGFloat(cellWidth) / 235, CGFloat(cellHeight) / CGFloat(height))
    let width = CGFloat(ink.width) * scale
    let fittedHeight = CGFloat(ink.height) * scale
    context.draw(ink, in: CGRect(x: (CGFloat(cellWidth) - width) / 2,
                                 y: (CGFloat(cellHeight) - fittedHeight) / 2,
                                 width: width, height: fittedHeight))
    return context.makeImage()!
}

func ink(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, alpha: 1)
}

let blue = ink(0x102371)
let green = ink(0x145321)
let red = ink(0x9D2018)

func markingFont(for style: Style) -> CTFont {
    if style == .minimal {
        return CTFontCreateWithName("PingFangTC-Semibold" as CFString, 128, nil)
    }
    // The artwork-only subset keeps regeneration independent of installed fonts.
    let url = references.appending(path: "TileCalligraphy.ttf")
    let provider = CGDataProvider(url: url as CFURL)!
    let font = CGFont(provider)!
    return CTFontCreateWithGraphicsFont(font, 128, nil, nil)
}

func glyphPath(_ text: String, font: CTFont) -> CGPath {
    var character = text.utf16.first!
    var index = CGGlyph()
    precondition(CTFontGetGlyphsForCharacters(font, &character, &index, 1), "Missing glyph: \(text)")
    return CTFontCreatePathForGlyph(font, index, nil)!
}

func drawGlyph(_ outline: CGPath, color: CGColor, in box: CGRect, scale: CGFloat,
               addedStroke: CGFloat, on context: CGContext) {
    let bounds = outline.boundingBoxOfPath
    context.saveGState()
    context.translateBy(x: box.midX - bounds.midX * scale, y: box.midY - bounds.midY * scale)
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(color)
    if addedStroke < 0 {
        // Resolve overlapping font contours before thinning to preserve the joins.
        let shape = outline.normalized()
        let edge = shape.copy(strokingWithWidth: -addedStroke / scale, lineCap: .round,
                              lineJoin: .round, miterLimit: 2)
        context.addPath(shape.subtracting(edge))
        context.fillPath()
    } else {
        context.setStrokeColor(color)
        context.setLineWidth(addedStroke / scale)
        context.setLineJoin(.round)
        context.addPath(outline)
        context.drawPath(using: addedStroke > 0 ? .fillStroke : .fill)
    }
    context.restoreGState()
}

func sharedScale(for outlines: [CGPath], in box: CGRect, addedStroke: CGFloat) -> CGFloat {
    let bounds = outlines.map(\.boundingBoxOfPath)
    return min((box.width - addedStroke) / bounds.map(\.width).max()!,
               (box.height - addedStroke) / bounds.map(\.height).max()!)
}

func inkBounds(_ image: CGImage) -> CGRect {
    let context = bitmap(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var bounds = CGRect.null
    for y in 0..<image.height {
        for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 32 {
            bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return bounds
}

func recolor(_ image: CGImage, to color: CGColor) -> CGImage {
    let context = bitmap(image.width, image.height)
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.draw(image, in: rect)
    context.setBlendMode(.sourceIn)
    context.setFillColor(color)
    context.fill(rect)
    return context.makeImage()!
}

struct BambooArtwork {
    let greenStalk: CGImage
    let redStalk: CGImage
    let blueStalk: CGImage

    init(from board: CGImage, style: Style) {
        if style == .minimal {
            let context = bitmap(26, 100)
            context.setFillColor(green)
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 26, height: 100),
                                   cornerWidth: 13, cornerHeight: 13, transform: nil))
            context.fillPath()
            greenStalk = context.makeImage()!
        } else {
            // Isolate the upper stalk from the approved 三條.
            let artwork = extractInk(board, rect: CGRect(x: 449, y: 701, width: 70, height: 128))
            greenStalk = artwork.cropping(to: inkBounds(artwork).insetBy(dx: -1, dy: -1))!
        }
        redStalk = recolor(greenStalk, to: red)
        blueStalk = recolor(greenStalk, to: blue)
    }

    func draw(_ rank: Int, on context: CGContext) {
        let regularHeight: CGFloat = 81
        let compactHeight: CGFloat = 57
        switch rank {
        case 2, 4, 6:
            let columns: [CGFloat] = switch rank {
            case 2: [96]
            case 4: [64, 128]
            default: [53, 96, 139]
            }
            for x in columns {
                for y in [85.0, 183.0] {
                    stalk(greenStalk, x: x, y: y, height: regularHeight, on: context)
                }
            }
        case 3:
            stalk(greenStalk, x: 96, y: 185, height: regularHeight, on: context)
            for x in [61.0, 131.0] {
                stalk(greenStalk, x: x, y: 83, height: regularHeight, on: context)
            }
        case 5:
            for x in [58.0, 134.0] {
                for y in [76.0, 192.0] {
                    stalk(greenStalk, x: x, y: y, height: compactHeight, on: context)
                }
            }
            stalk(redStalk, x: 96, y: 134, height: compactHeight, on: context)
        case 7:
            stalk(redStalk, x: 96, y: 202, height: compactHeight, on: context)
            for y in [66.0, 134.0] {
                stalk(blueStalk, x: 96, y: y, height: compactHeight, on: context)
                for x in [50.0, 142.0] {
                    stalk(greenStalk, x: x, y: y, height: compactHeight, on: context)
                }
            }
        case 8:
            eightBamboo(on: context)
        case 9:
            for x in [50.0, 96.0, 142.0] {
                for y in [66.0, 134.0, 202.0] {
                    stalk(x == 96 ? redStalk : greenStalk, x: x, y: y, height: compactHeight, on: context)
                }
            }
        default:
            preconditionFailure("Unexpected bamboo rank")
        }
    }

    private func stalk(_ image: CGImage, x: CGFloat, y: CGFloat, height: CGFloat, angle: CGFloat = 0,
                       on context: CGContext) {
        let width = CGFloat(image.width) * 0.76
        context.saveGState()
        context.translateBy(x: x, y: y)
        context.rotate(by: angle)
        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        context.restoreGState()
    }

    private func eightBamboo(on context: CGContext) {
        // Four joined stalks in each of the mirrored groups on the physical set.
        let points = [(51.0, 24.0), (51, -23), (96, 21), (141, -23), (141, 24)]
        for (center, direction) in [(181.0, 1.0), (87.0, -1.0)] {
            let group = points.map { x, y in CGPoint(x: x, y: center + direction * y) }
            for (start, end) in zip(group, group.dropFirst()) {
                let dx = end.x - start.x
                let dy = end.y - start.y
                stalk(greenStalk, x: (start.x + end.x) / 2, y: (start.y + end.y) / 2,
                      height: hypot(dx, dy) + 14, angle: atan2(dy, dx) - .pi / 2, on: context)
            }
        }
    }
}

func drawCircles(_ rank: Int, compactTraditional: Bool = false, on context: CGContext) {
    if compactTraditional && rank == 1 {
        let frame = CGRect(x: 24, y: 62, width: 144, height: 144)
        context.setStrokeColor(blue)
        context.setLineWidth(8)
        context.strokeEllipse(in: frame.insetBy(dx: 4, dy: 4))
        context.setFillColor(green)
        for (x, y) in [(65, 101), (65, 167), (127, 101), (127, 167)] {
            context.fillEllipse(in: CGRect(x: x - 11, y: y - 11, width: 22, height: 22))
        }
        drawRosette(x: 96, y: 134, diameter: 76, color: red, on: context)
        return
    }
    let corners: [(CGFloat, CGFloat)] = [(54, 181), (138, 181), (54, 87), (138, 87)]
    let dots: [(CGFloat, CGFloat)]
    let diameter: CGFloat
    switch rank {
    case 1: (dots, diameter) = ([(96, 134)], 96)
    case 2: (dots, diameter) = ([(96, 182), (96, 86)], 58)
    case 3: (dots, diameter) = ([(52, 192), (96, 134), (140, 76)], 48)
    case 4: (dots, diameter) = (corners, 46)
    case 5: (dots, diameter) = (corners + [(96, 134)], 42)
    case 6: (dots, diameter) = ([(62, 196), (130, 196), (62, 123), (130, 123), (62, 72), (130, 72)], 40)
    case 7: (dots, diameter) = ([(52, 211), (96, 191), (140, 171),
                                 (65, 124), (127, 124), (65, 76), (127, 76)], 36)
    case 8: (dots, diameter) = ([56, 108, 160, 212].flatMap { y in [(62, y), (130, y)] }, 36)
    case 9: (dots, diameter) = ([196, 134, 72].flatMap { y in [(44, y), (96, y), (148, y)] }, 36)
    default: preconditionFailure("Unexpected circle rank")
    }
    // Use the familiar color groupings on the flat dots.
    let colors = switch rank {
    case 2: [green, blue]
    case 3: [green, red, blue]
    case 4: [blue, green, green, blue]
    case 5: [blue, green, green, blue, red]
    case 6: [green, green, red, red, red, red]
    case 7: [green, green, green, red, red, red, red]
    case 9: [green, green, green, red, red, red, blue, blue, blue]
    default: Array(repeating: blue, count: dots.count)
    }
    for ((x, y), color) in zip(dots, colors) {
        if compactTraditional {
            drawRosette(x: x, y: y, diameter: diameter + 4, color: color, on: context)
        } else {
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                           width: diameter, height: diameter))
        }
    }
}

func drawRosette(x: CGFloat, y: CGFloat, diameter: CGFloat, color: CGColor, on context: CGContext) {
    let ring = diameter * 0.12
    context.setStrokeColor(color)
    context.setLineWidth(ring)
    context.strokeEllipse(in: CGRect(x: x - diameter / 2 + ring / 2, y: y - diameter / 2 + ring / 2,
                                     width: diameter - ring, height: diameter - ring))
    context.setFillColor(color)
    let petal = diameter * 0.18
    let offset = diameter * 0.15
    for (dx, dy) in [(0, offset), (offset, 0), (0, -offset), (-offset, 0)] {
        context.fillEllipse(in: CGRect(x: x + dx - petal / 2, y: y + dy - petal / 2,
                                       width: petal, height: petal))
    }
}

func drawCompactWhiteDragon(on context: CGContext) {
    let border = CGPath(roundedRect: CGRect(x: 39, y: 48, width: 114, height: 172),
                        cornerWidth: 13, cornerHeight: 13, transform: nil)
    context.setStrokeColor(blue)
    context.setLineWidth(8)
    context.addPath(border)
    context.strokePath()
}

func separateLowerCircleRows(_ sample: CGImage, top: Int, split: Int) -> CGImage {
    // Keep the upper pips in place and open a gap between the two lower pairs.
    let tile = bitmap(cellWidth, cellHeight)
    let width = CGFloat(cellWidth)
    let upper = sample.cropping(to: CGRect(x: 0, y: 0, width: cellWidth, height: top))!
    tile.draw(upper, in: CGRect(x: 0, y: cellHeight - top, width: cellWidth, height: top))
    let scale: CGFloat = 0.92
    for (band, shift) in [(top..<split, 1.0), (split..<cellHeight, -1.0)] {
        let pair = sample.cropping(to: CGRect(x: 0, y: band.lowerBound, width: cellWidth, height: band.count))!
        let inkMidY = inkBounds(pair).midY
        let centerY = CGFloat(cellHeight - band.lowerBound) - inkMidY
        let height = CGFloat(band.count) * scale
        tile.draw(pair, in: CGRect(x: (width - width * scale) / 2,
                                   y: centerY - (CGFloat(band.count) - inkMidY) * scale + shift,
                                   width: width * scale, height: height))
    }
    return tile.makeImage()!
}

func separateTraditionalEightCircles(_ sample: CGImage) -> CGImage {
    let tile = bitmap(cellWidth, cellHeight)
    // Split the approved ink between rows, then space the four pairs evenly.
    let rowBoundaries = [35, 86, 135, 184, 238]
    let scale: CGFloat = 0.92
    let width = CGFloat(cellWidth) * scale
    for (row, (start, end)) in zip(rowBoundaries, rowBoundaries.dropFirst()).enumerated() {
        let pair = sample.cropping(to: CGRect(x: 0, y: start, width: cellWidth, height: end - start))!
        let height = CGFloat(pair.height) * scale
        let centerY = 212 - CGFloat(row) * 52
        tile.draw(pair, in: CGRect(x: (CGFloat(cellWidth) - width) / 2, y: centerY - height / 2,
                                   width: width, height: height))
    }
    return tile.makeImage()!
}

func render(_ style: Style) throws {
    let board = load(references.appending(path: "\(style.sheet).png"))
    let atlas = bitmap(cellWidth * columns, cellHeight * rows)
    // These approved cells supply the complete circle tiles, white dragon, and bamboo samples.
    let sampleIndices = [9, 10, 11, 12, 13, 14, 15, 16, 17, 33, 18]
    let approved: [Int: CGImage] = Dictionary(uniqueKeysWithValues: sampleIndices.enumerated().compactMap { position, index in
        guard style != .minimal || index == 18 || index == 33 else { return nil }
        let sample = tileSample(board, column: position % 5, row: position / 5)
        let artwork = switch (style, index) {
        case (.photoMatched, 15): separateLowerCircleRows(sample, top: 139, split: 187)
        case (.traditional, 14): separateLowerCircleRows(sample, top: 121, split: 176)
        case (.traditional, 16): separateTraditionalEightCircles(sample)
        default: sample
        }
        return (index, artwork)
    })
    let font = markingFont(for: style)
    let wanTile = bitmap(cellWidth, cellHeight)
    let wanGlyph = glyphPath(style == .minimal ? "万" : "萬", font: font)
    let wanBox: CGRect = switch style {
    case .photoMatched: CGRect(x: 44, y: 37, width: 104, height: 105)
    case .minimal: CGRect(x: 41, y: 42, width: 110, height: 91)
    case .traditional: CGRect(x: 42, y: 32, width: 108, height: 113)
    }
    // The dense strokes of 萬 need more space at discard size.
    let wanStroke = style.addedStroke * 0.4
    let wanScale = sharedScale(for: [wanGlyph], in: wanBox, addedStroke: wanStroke) * (style == .minimal ? 0.85 : 0.96)
    drawGlyph(wanGlyph, color: red, in: wanBox, scale: wanScale, addedStroke: wanStroke, on: wanTile)
    let wan = wanTile.makeImage()!
    // Convert image rows to the drawing context's bottom-left origin.
    let minimumNumeralBottom = CGFloat(cellHeight) - inkBounds(wan).minY + 13
    let bamboo = BambooArtwork(from: board, style: style)
    let numerals = ["一", "二", "三", "四", style == .minimal ? "五" : "伍", "六", "七", "八", "九"]
        .map { glyphPath($0, font: font) }
    let honors = ["東", "南", "西", "北", "中", "發", "白", "梅", "蘭", "菊", "竹", "春", "夏", "秋", "冬"]
        .map { glyphPath($0, font: font) }
    let numeralScale = sharedScale(for: numerals, in: style.numeralBox, addedStroke: style.addedStroke)
    let honorScale = sharedScale(for: honors, in: style.honorBox, addedStroke: style.addedStroke)
    // Center the single stroke within each style's upper numeral area.
    let oneStrokeOffset: CGFloat = switch style {
    case .photoMatched: 2
    case .minimal: 1
    case .traditional: -16
    }

    for index in 0..<(columns * rows) {
        let rect = CGRect(x: index % columns * cellWidth, y: (rows - 1 - index / columns) * cellHeight,
                          width: cellWidth, height: cellHeight)
        if let sample = approved[index] {
            atlas.draw(sample, in: rect)
            continue
        }
        let tile = bitmap(cellWidth, cellHeight)
        switch index {
        case 0...8:
            let numeral = numerals[index]
            // Give 四 more height and keep the enclosed counters open.
            let (scaleAdjustment, strokeReduction): (CGFloat, CGFloat) = switch (style, index) {
            case (.photoMatched, 3): (1.22, 4.4)
            case (.traditional, 3): (1.22, 5.25)
            case (.traditional, 4): (1, 2.6)
            case (.minimal, 3): (1.055, 3.4)
            case (_, 4): (1, 1.8)
            default: (1, 0)
            }
            let scale = numeralScale * scaleAdjustment
            let stroke = style.addedStroke - strokeReduction
            let height = numeral.boundingBoxOfPath.height * scale + stroke
            let numeralBox = style.numeralBox.offsetBy(dx: 0, dy: index == 0 ? oneStrokeOffset : 0)
            let bottom = numeralBox.midY - height / 2
            let box = numeralBox.offsetBy(dx: 0, dy: max(0, minimumNumeralBottom - bottom))
            drawGlyph(numeral, color: blue, in: box, scale: scale, addedStroke: stroke, on: tile)
            tile.draw(wan, in: CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
        case 9...17:
            drawCircles(index - 8, on: tile)
        case 18...26:
            bamboo.draw(index - 17, on: tile)
        case 27...32, 34...41:
            let color = index == 31 || index >= 38 ? red : index >= 32 ? green : blue
            // 西 is naturally shorter than the other winds.
            let scale = index == 29 && style != .minimal ? honorScale * 1.09 : honorScale
            // Keep the narrow gaps in 蘭 and 夏 open at bonus-strip size.
            let stroke: CGFloat = switch (style, index) {
            case (.photoMatched, 29): 2.2
            case (.traditional, 29): 3.2
            case (.minimal, 35): -2.1
            case (.minimal, 39): -2.0
            case (_, 35): style.addedStroke * 0.2
            case (_, 39): style.addedStroke * 0.4
            default: style.addedStroke
            }
            drawGlyph(honors[index - 27], color: color, in: style.honorBox, scale: scale,
                      addedStroke: stroke, on: tile)
        default:
            preconditionFailure("Missing tile \(index)")
        }
        atlas.draw(tile.makeImage()!, in: rect)
    }

    try writeAtlas(atlas, named: style.asset)
}

func writeAtlas(_ atlas: CGContext, named name: String) throws {
    let imageset = catalog.appending(path: "\(name).imageset")
    try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
    let info = #"{"images":[{"filename":"markings.png","idiom":"universal","scale":"1x"}],"info":{"author":"xcode","version":1}}"#
    try (info + "\n").write(to: imageset.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    let output = imageset.appending(path: "markings.png")
    let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, atlas.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

for style in Style.allCases {
    try render(style)
}

let compactColumns = 5
let compact = bitmap(cellWidth * compactColumns, cellHeight * 2)
for index in 0..<10 {
    let tile = bitmap(cellWidth, cellHeight)
    if index == 9 {
        drawCompactWhiteDragon(on: tile)
    } else {
        drawCircles(index + 1, compactTraditional: true, on: tile)
    }
    compact.draw(tile.makeImage()!, in: CGRect(x: index % compactColumns * cellWidth,
                                             y: (1 - index / compactColumns) * cellHeight,
                                             width: cellWidth, height: cellHeight))
}
try writeAtlas(compact, named: "TraditionalCompactMarkings")
