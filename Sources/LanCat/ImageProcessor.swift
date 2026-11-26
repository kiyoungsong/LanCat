import AppKit
import ImageIO

struct ProcessedFrames {
    var images: [CGImage]
    var durations: [Double]
}

/// 사용자가 넣은 이미지(PNG/JPG/GIF/APNG/WebP…)를 앱에서 쓰기 좋게 다듬어요.
/// 1. 프레임을 모두 읽고 (움직이는 이미지면 프레임별 시간도)
/// 2. 테두리에 붙은 흰 배경을 지우고 (옵션)
/// 3. 모든 프레임을 합친 내용 영역으로 여백을 잘라내고
/// 4. 아이콘은 메뉴바 높이(36px = 18pt@2x), 그림은 팝오버 크기에 맞춰 줄여요.
enum ImageProcessor {
    static let maxFrames = 120

    static func process(url: URL, kind: SlotKind, removeWhite: Bool, trim: Bool) -> Result<ProcessedFrames, Error> {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .failure(ImportError("이미지를 열 수 없어요. PNG, JPG, GIF 파일인지 확인해 주세요."))
        }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 0 else { return .failure(ImportError("이미지에 프레임이 없어요.")) }

        var bitmaps: [RGBABitmap] = []
        var durations: [Double] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil),
                  var bitmap = RGBABitmap(cg) else { continue }
            if removeWhite { bitmap.removeEdgeWhite() }
            bitmaps.append(bitmap)
            durations.append(frameDelay(source, index: i))
        }
        guard !bitmaps.isEmpty else { return .failure(ImportError("이미지를 읽지 못했어요.")) }

        // 모든 프레임의 내용 영역을 합쳐서 잘라야 움직여도 위치가 흔들리지 않아요.
        // 여백 자르기를 끄면 원본 캔버스를 그대로 써요 (같은 캔버스로 만든 아이콘 세트의 크기가 서로 맞게).
        var box: CGRect?
        for b in bitmaps where trim {
            guard let r = b.contentBounds() else { continue }
            box = box.map { $0.union(r) } ?? r
        }
        if !trim, let first = bitmaps.first {
            box = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        }
        guard let crop = box else {
            return .failure(ImportError("이미지가 전부 투명해요. '흰 배경 지우기'를 끄고 다시 넣어 보세요."))
        }

        let target: CGSize
        switch kind {
        case .icon: target = fit(crop.size, maxWidth: 88, maxHeight: 36)
        case .scene: target = fit(crop.size, maxWidth: 540, maxHeight: 560)
        }

        var output: [CGImage] = []
        for b in bitmaps {
            guard let full = b.makeImage(),
                  let cropped = full.cropping(to: crop),
                  let resized = resize(cropped, to: target) else { continue }
            output.append(resized)
        }
        guard !output.isEmpty else { return .failure(ImportError("이미지를 다듬지 못했어요.")) }
        if output.count == 1 { durations = [1] }
        return .success(ProcessedFrames(images: output, durations: Array(durations.prefix(output.count))))
    }

    private static func fit(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    private static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// GIF / APNG / WebP 프레임 시간
    private static func frameDelay(_ source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else { return 0.1 }
        let containers: [(CFString, [CFString])] = [
            (kCGImagePropertyGIFDictionary, [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime]),
            (kCGImagePropertyPNGDictionary, [kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime]),
            (kCGImagePropertyWebPDictionary, [kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime]),
        ]
        for (container, keys) in containers {
            guard let dict = props[container as String] as? [String: Any] else { continue }
            for key in keys {
                if let v = dict[key as String] as? Double, v > 0.01 { return max(v, 0.03) }
            }
        }
        return 0.1
    }
}

/// 픽셀 단위로 다루기 위한 RGBA 비트맵 (위에서부터 한 줄씩)
struct RGBABitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(_ image: CGImage, maxSide: Int = 1600) {
        let scale = min(1.0, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        pixels = buffer
    }

    /// 가장자리와 이어진 흰색(거의 흰색) 영역만 투명하게 만들어요.
    /// 고양이 얼굴처럼 안쪽에 있는 흰색은 그대로 남아요.
    mutating func removeEdgeWhite(threshold: UInt8 = 245) {
        let w = width, h = height
        var px = pixels
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []

        func isWhite(_ i: Int) -> Bool {
            let p = i * 4
            return px[p + 3] > 200 && px[p] > threshold && px[p + 1] > threshold && px[p + 2] > threshold
        }
        func push(_ i: Int) {
            if !visited[i] && isWhite(i) { visited[i] = true; stack.append(i) }
        }

        for x in 0..<w { push(x); push((h - 1) * w + x) }
        for y in 0..<h { push(y * w); push(y * w + w - 1) }

        while let i = stack.popLast() {
            let p = i * 4
            px[p] = 0; px[p + 1] = 0; px[p + 2] = 0; px[p + 3] = 0
            let x = i % w, y = i / w
            if x > 0 { push(i - 1) }
            if x < w - 1 { push(i + 1) }
            if y > 0 { push(i - w) }
            if y < h - 1 { push(i + w) }
        }
        pixels = px
    }

    /// 투명하지 않은 픽셀이 있는 영역 (위-왼쪽 기준 좌표)
    func contentBounds(alphaThreshold: UInt8 = 8) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[(row + x) * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 1
        let x0 = max(0, minX - pad), y0 = max(0, minY - pad)
        let x1 = min(width, maxX + 1 + pad), y1 = min(height, maxY + 1 + pad)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    func makeImage() -> CGImage? {
        var copy = pixels
        return copy.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
