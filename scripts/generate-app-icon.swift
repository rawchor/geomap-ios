// Regenerates the 1024x1024 app icon from the in-app logo drawing.
// Run from the repo root:
//   swiftc scripts/generate-app-icon.swift Geomap/Components/OrbitLogo.swift -o /tmp/gen-icon && /tmp/gen-icon
import AppKit

@main
struct GenerateAppIcon {
    static func main() {
        let size = 1024
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        // Flip to a top-left origin, matching SwiftUI's Canvas.
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        OrbitLogoDrawing.draw(in: ctx, size: CGFloat(size), includeBackground: true)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        let data = rep.representation(using: .png, properties: [:])!
        let path = "Geomap/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
