// Dessine l'icône de mSTICK : une note adhésive jaune au coin replié sur fond sombre, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let yellow = NSColor(red: 1.0, green: 0.80, blue: 0.22, alpha: 1)
let darkYellow = NSColor(red: 0.86, green: 0.62, blue: 0.10, alpha: 1)
let background = NSColor(white: 0.118, alpha: 1)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
cg.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
cg.setFillColor(background.cgColor)
cg.fillPath()

// Note : carré de 460 px, coin bas-droit replié, légèrement penchée.
cg.translateBy(x: size / 2, y: size / 2)
cg.rotate(by: -0.06)
let s: CGFloat = 470, fold: CGFloat = 130
let note = CGMutablePath()
note.move(to: CGPoint(x: -s / 2, y: s / 2))
note.addLine(to: CGPoint(x: s / 2, y: s / 2))
note.addLine(to: CGPoint(x: s / 2, y: -s / 2 + fold))
note.addLine(to: CGPoint(x: s / 2 - fold, y: -s / 2))
note.addLine(to: CGPoint(x: -s / 2, y: -s / 2))
note.closeSubpath()
cg.setFillColor(yellow.cgColor)
cg.addPath(note); cg.fillPath()
let corner = CGMutablePath()
corner.move(to: CGPoint(x: s / 2, y: -s / 2 + fold))
corner.addLine(to: CGPoint(x: s / 2 - fold, y: -s / 2 + fold))
corner.addLine(to: CGPoint(x: s / 2 - fold, y: -s / 2))
corner.closeSubpath()
cg.setFillColor(darkYellow.cgColor)
cg.addPath(corner); cg.fillPath()
// Lignes de texte
cg.setStrokeColor(NSColor(red: 0.45, green: 0.32, blue: 0.02, alpha: 0.85).cgColor)
cg.setLineWidth(30); cg.setLineCap(.round)
for (i, w) in [330.0, 330.0, 200.0].enumerated() {
    let y = s / 2 - 100 - CGFloat(i) * 80
    cg.move(to: CGPoint(x: -s / 2 + 70, y: y)); cg.addLine(to: CGPoint(x: -s / 2 + 70 + w, y: y)); cg.strokePath()
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
