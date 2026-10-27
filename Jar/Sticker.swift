import CoreImage
import UIKit
import Vision

/// ponytail: Vision lifts one foreground. If it misses, the whole photo gets the white edge. A manual cut would replace that fallback.
func stickerPNG(_ data: Data) -> Data? {
    guard let source = UIImage(data: data)?.cgImage else { return nil }
    let fitted = fit(source, maxSide: 960)
    let mask = foregroundMask(fitted) ?? opaqueMask(width: fitted.width, height: fitted.height)
    guard let mask else { return nil }
    let stroke = max(18, CGFloat(min(fitted.width, fitted.height)) * 0.055)
    guard let cut = dieCut(image: fitted, mask: mask, stroke: stroke) else { return nil }
    return UIImage(cgImage: cut).pngData()
}

private func fit(_ image: CGImage, maxSide: Int) -> CGImage {
    let longest = max(image.width, image.height)
    guard longest > maxSide else { return image }
    let scale = CGFloat(maxSide) / CGFloat(longest)
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage() ?? image
}

private func foregroundMask(_ image: CGImage) -> CGImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image)
    guard (try? handler.perform([request])) != nil,
          let observation = request.results?.first,
          let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) else { return nil }
    let rendered = CIContext().createCGImage(CIImage(cvPixelBuffer: buffer), from: CIImage(cvPixelBuffer: buffer).extent)
    return rendered.flatMap(deviceGray)
}

private func deviceGray(_ image: CGImage) -> CGImage? {
    let space = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
        space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()
}

private func opaqueMask(width: Int, height: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
    ), let pixels = ctx.data else { return nil }
    pixels.bindMemory(to: UInt8.self, capacity: width * height).initialize(repeating: 255, count: width * height)
    return ctx.makeImage()
}
