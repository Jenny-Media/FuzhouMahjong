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

    var font: String {
        switch self {
        case .photoMatched, .traditional: "STSongti-TC-Bold"
        case .minimal: "PingFangTC-Semibold"
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
func extractInk(_ source: CGImage, rect: CGRect, redOnly: Bool = false) -> CGImage {
    let crop = source.cropping(to: rect)!
    let context = bitmap(crop.width, crop.height)
    context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let paper = [229.0, 225.0, 213.0]

    for offset in stride(from: 0, to: crop.width * crop.height * 4, by: 4) {
        let pixel = data.advanced(by: offset)
        let darkest = Double(min(pixel[0], pixel[1], pixel[2]))
        let lightest = Double(max(pixel[0], pixel[1], pixel[2]))
        let matchesInk = !redOnly || (Int(pixel[0]) - Int(max(pixel[1], pixel[2])) > 18)
        let alpha = matchesInk && darkest < 204 && (lightest - darkest > 24 || lightest < 170)
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
    let marginX = CGFloat(insetX * cellWidth) / 235
    let marginY = CGFloat(insetY * cellHeight) / CGFloat(height)
    context.draw(ink, in: CGRect(x: marginX, y: marginY, width: CGFloat(cellWidth) - 2 * marginX,
                                 height: CGFloat(cellHeight) - 2 * marginY))
    return context.makeImage()!
}

func ink(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, alpha: 1)
}

let blue = ink(0x102471)
let green = ink(0x14552C)
let red = ink(0xA11E18)

func glyph(_ text: String, style: Style, color: CGColor, in box: CGRect, on context: CGContext) {
    let font = CTFontCreateWithName(style.font as CFString, 128, nil)
    let char = Array(text.utf16)
    var index = CGGlyph()
    precondition(CTFontGetGlyphsForCharacters(font, char, &index, 1), "Missing glyph: \(text)")
    let outline = CTFontCreatePathForGlyph(font, index, nil)!
    let bounds = outline.boundingBoxOfPath
    let scale = min(box.width / bounds.width, box.height / bounds.height)
    context.saveGState()
    context.translateBy(x: box.midX - bounds.midX * scale, y: box.midY - bounds.midY * scale)
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(color)
    context.addPath(outline)
    context.fillPath()
    context.restoreGState()
}

func denseRosettes(rank: Int, on context: CGContext) {
    let rowCount = rank == 8 ? 4 : 3
    let columnCount = rank == 8 ? 2 : 3
    let stepX: CGFloat = rank == 8 ? 58 : 52
    let stepY: CGFloat = rank == 8 ? 49 : 63
    let radius: CGFloat = rank == 8 ? 18 : 20
    let colors = rank == 8 ? Array(repeating: blue, count: 4) : [green, red, blue]
    for row in 0..<rowCount {
        for column in 0..<columnCount {
            let x = 96 + (CGFloat(column) - CGFloat(columnCount - 1) / 2) * stepX
            let y = 134 + (CGFloat(rowCount - 1) / 2 - CGFloat(row)) * stepY
            context.setFillColor(colors[row])
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            context.saveGState()
            context.setBlendMode(.clear)
            let petals = CGMutablePath()
            for petal in 0..<5 {
                let angle = Double(petal) * 2 * .pi / 5 + .pi / 2
                let center = CGPoint(x: x + radius * 0.29 * cos(angle), y: y + radius * 0.29 * sin(angle))
                let petalRadius = radius * 0.23
                petals.addEllipse(in: CGRect(x: center.x - petalRadius, y: center.y - petalRadius,
                                             width: petalRadius * 2, height: petalRadius * 2))
            }
            context.addPath(petals)
            context.fillPath()
            context.restoreGState()
        }
    }
}

struct Stalk {
    var x: CGFloat
    var y: CGFloat
    var color: CGColor = green
}

func bamboo(_ rank: Int, style: Style, on context: CGContext) {
    let stalks: [Stalk]
    switch rank {
    case 2: stalks = [Stalk(x: 96, y: 183), Stalk(x: 96, y: 85)]
    case 4: stalks = [Stalk(x: 65, y: 183), Stalk(x: 127, y: 183), Stalk(x: 65, y: 85), Stalk(x: 127, y: 85)]
    case 5: stalks = [Stalk(x: 58, y: 192), Stalk(x: 134, y: 192), Stalk(x: 96, y: 134, color: red),
                      Stalk(x: 58, y: 76), Stalk(x: 134, y: 76)]
    case 6: stalks = [56, 96, 136].flatMap { x in [Stalk(x: x, y: 183), Stalk(x: x, y: 85)] }
    case 7: stalks = [Stalk(x: 96, y: 202, color: red), Stalk(x: 96, y: 134, color: blue),
                      Stalk(x: 96, y: 66, color: blue)] +
        [50, 142].flatMap { x in [Stalk(x: x, y: 134), Stalk(x: x, y: 66)] }
    case 8:
        // The physical set carries four slanted stalks in each of the W/M groups.
        for (y, mirrored) in [(180.0, false), (89.0, true)] {
            for (index, angle) in [0.29, -0.47, 0.47, -0.29].enumerated() {
                context.saveGState()
                context.translateBy(x: CGFloat(44 + index * 34), y: y)
                context.rotate(by: mirrored ? -angle : angle)
                drawStalk(width: 17, height: 59, color: green, style: style, on: context)
                context.restoreGState()
            }
        }
        return
    case 9: stalks = [50, 96, 142].flatMap { x in
        [202, 134, 66].map { y in Stalk(x: x, y: y, color: x == 96 ? red : green) }
    }
    default: preconditionFailure("Unexpected bamboo rank")
    }
    let height: CGFloat = rank == 2 || rank == 4 || rank == 6 ? 76 : 54
    for stalk in stalks {
        context.saveGState()
        context.translateBy(x: stalk.x, y: stalk.y)
        drawStalk(width: 22, height: height, color: stalk.color, style: style, on: context)
        context.restoreGState()
    }
}

func drawStalk(width: CGFloat, height: CGFloat, color: CGColor, style: Style, on context: CGContext) {
    context.setFillColor(color)
    let shoulders = CGMutablePath()
    let end = width / 2
    let middle = end * 0.69
    let half = height / 2
    shoulders.move(to: CGPoint(x: -middle, y: -half))
    shoulders.addQuadCurve(to: CGPoint(x: -middle, y: -half + width / 2),
                           control: CGPoint(x: -end * 1.45, y: -half + width / 4))
    shoulders.addQuadCurve(to: CGPoint(x: -middle, y: half - width / 2),
                           control: CGPoint(x: -middle * 0.75, y: 0))
    shoulders.addQuadCurve(to: CGPoint(x: -middle, y: half),
                           control: CGPoint(x: -end * 1.45, y: half - width / 4))
    shoulders.addLine(to: CGPoint(x: middle, y: half))
    shoulders.addQuadCurve(to: CGPoint(x: middle, y: half - width / 2),
                           control: CGPoint(x: end * 1.45, y: half - width / 4))
    shoulders.addQuadCurve(to: CGPoint(x: middle, y: -half + width / 2),
                           control: CGPoint(x: middle * 0.75, y: 0))
    shoulders.addQuadCurve(to: CGPoint(x: middle, y: -half),
                           control: CGPoint(x: end * 1.45, y: -half + width / 4))
    shoulders.closeSubpath()
    context.addPath(shoulders)
    context.fillPath()
    context.fillEllipse(in: CGRect(x: -end, y: -width * 0.22, width: width, height: width * 0.44))
    if style != .minimal {
        context.setStrokeColor(color.copy(alpha: 0.58)!)
        context.setLineWidth(style == .traditional ? 3 : 4)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 0, y: -half + 9))
        context.addLine(to: CGPoint(x: 0, y: half - 9))
        context.setBlendMode(.destinationOut)
        context.strokePath()
    }
}

func render(_ style: Style) throws {
    let board = load(references.appending(path: "\(style.sheet).png"))
    let atlas = bitmap(cellWidth * columns, cellHeight * rows)
    let samples = [
        (9, 0, 0), (10, 1, 0), (11, 2, 0), (12, 3, 0), (13, 4, 0),
        (14, 0, 1), (15, 1, 1), (16, 2, 1), (17, 3, 1), (33, 4, 1),
        (18, 0, 2), (20, 1, 2), (4, 2, 2), (5, 3, 2), (27, 4, 2),
    ]
    let approved = Dictionary(uniqueKeysWithValues: samples.map { index, column, row in
        (index, tileSample(board, column: column, row: row))
    })
    let wan = extractInk(board, rect: CGRect(x: 679, y: 811, width: 176, height: 149), redOnly: true)
    for index in 0..<(columns * rows) {
        let rect = CGRect(x: index % columns * cellWidth, y: (rows - 1 - index / columns) * cellHeight,
                          width: cellWidth, height: cellHeight)
        if style == .traditional && (16...17).contains(index) {
            let tile = bitmap(cellWidth, cellHeight)
            denseRosettes(rank: index - 8, on: tile)
            atlas.draw(tile.makeImage()!, in: rect)
        } else if let sample = approved[index] {
            atlas.draw(sample, in: rect)
        } else {
            let tile = bitmap(cellWidth, cellHeight)
            switch index {
            case 0...8:
                let numerals = ["一", "二", "三", "四", "伍", "六", "七", "八", "九"]
                glyph(numerals[index], style: style, color: blue,
                      in: CGRect(x: 34, y: 145, width: 124, height: 88), on: tile)
                tile.draw(wan, in: CGRect(x: 24, y: 16, width: 144, height: 125))
            case 18...26:
                bamboo(index - 17, style: style, on: tile)
            case 28...32, 34...41:
                let symbols = ["東", "南", "西", "北", "中", "發", "白", "梅", "蘭", "菊", "竹", "春", "夏", "秋", "冬"]
                let color = index == 31 || index >= 38 ? red : index >= 32 ? green : blue
                glyph(symbols[index - 27], style: style, color: color,
                      in: CGRect(x: 24, y: 49, width: 144, height: 170), on: tile)
            default:
                preconditionFailure("Missing tile \(index)")
            }
            atlas.draw(tile.makeImage()!, in: rect)
        }
    }

    let imageset = catalog.appending(path: "\(style.asset).imageset")
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
