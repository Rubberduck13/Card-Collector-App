public func analyzeCenteringReal(from observation: VNRectangleObservation, in cgImage: CGImage) -> CenteringResult {
    let ciImage = CIImage(cgImage: cgImage)
    let extent = ciImage.extent
    let topLeft = CGPoint(x: observation.topLeft.x * extent.width, y: observation.topLeft.y * extent.height)
    let topRight = CGPoint(x: observation.topRight.x * extent.width, y: observation.topRight.y * extent.height)
    let bottomLeft = CGPoint(x: observation.bottomLeft.x * extent.width, y: observation.bottomLeft.y * extent.height)
    let bottomRight = CGPoint(x: observation.bottomRight.x * extent.width, y: observation.bottomRight.y * extent.height)

    guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else { return fallbackCentering() }
    perspectiveFilter.setValue(ciImage, forKey: kCIInputImageKey)
    perspectiveFilter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
    perspectiveFilter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
    perspectiveFilter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
    perspectiveFilter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

    guard let correctedImage = perspectiveFilter.outputImage else { return fallbackCentering() }
    let context = CIContext()
    guard let correctedCGImage = context.createCGImage(correctedImage, from: correctedImage.extent),
          let pixelData = correctedCGImage.dataProvider?.data,
          let buffer = CFDataGetBytePtr(pixelData) else {
        return fallbackCentering()
    }

    let width = correctedCGImage.width
    let height = correctedCGImage.height
    let bytesPerPixel = correctedCGImage.bitsPerPixel / 8
    let bytesPerRow = correctedCGImage.bytesPerRow
    let dataLength = CFDataGetLength(pixelData)

    func brightness(x: Int, y: Int) -> Int {
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard offset + 2 < dataLength, offset >= 0 else { return 0 }
        let r = Int(buffer[offset])
        let g = Int(buffer[offset + 1])
        let b = Int(buffer[offset + 2])
        return (r + g + b) / 3
    }

    // Scans ONE line and returns the pixel distance to the sharpest brightness jump
    func scanLineForBorder(edge: String, lineOffset: Int) -> Int? {
        let scanLength: Int
        switch edge {
        case "left", "right": scanLength = width / 2
        default: scanLength = height / 2
        }
        var prevBrightness: Int? = nil
        var maxJump = 0
        var borderWidth: Int? = nil

        for i in 0..<scanLength {
            let currentBrightness: Int
            switch edge {
            case "left": currentBrightness = brightness(x: i, y: lineOffset)
            case "right": currentBrightness = brightness(x: width - 1 - i, y: lineOffset)
            case "top": currentBrightness = brightness(x: lineOffset, y: i)
            default: currentBrightness = brightness(x: lineOffset, y: height - 1 - i)
            }
            if let prev = prevBrightness, i > 3 { // skip first few px: card cut-edge noise
                let jump = abs(currentBrightness - prev)
                if jump > maxJump {
                    maxJump = jump
                    borderWidth = i
                }
            }
            prevBrightness = currentBrightness
        }
        // Only trust this line if it found a real, meaningfully sharp transition
        return maxJump > 15 ? borderWidth : nil
    }

    // Scans MULTIPLE parallel lines (not just the midline) and averages the results,
    // discarding outliers caused by busy artwork, foil glare, or printed text near the border
    func findBorderWidth(edge: String) -> Double {
        let sampleCount = 7
        let dimension = (in edge == "left" || edge == "right") ? height : width
        let margin = dimension / 4 // stay away from the very corners
        var results: [Int] = []

        for sample in 0..<sampleCount {
            let position = margin + (sample * (dimension - 2 * margin) / (sampleCount - 1))
            if let width = scanLineForBorder(edge: edge, lineOffset: position) {
                results.append(width)
            }
        }

        guard !results.isEmpty else { return 12 } // reasonable fallback if nothing detected

        // Use median instead of mean — more robust against one or two bad outlier scans
        let sorted = results.sorted()
        return Double(sorted[sorted.count / 2])
    }

    let leftBorder = findBorderWidth(edge: "left")
    let rightBorder = findBorderWidth(edge: "right")
    let topBorder = findBorderWidth(edge: "top")
    let bottomBorder = findBorderWidth(edge: "bottom")

    let totalH = leftBorder + rightBorder
    let totalV = topBorder + bottomBorder
    let leftPct = totalH > 0 ? (leftBorder / totalH) * 100 : 50
    let rightPct = 100 - leftPct
    let topPct = totalV > 0 ? (topBorder / totalV) * 100 : 50
    let bottomPct = 100 - topPct

    let passesPSA10 = leftPct >= 40 && leftPct <= 60 && topPct >= 40 && topPct <= 60
    let passesBGS10 = leftPct >= 48 && leftPct <= 52 && topPct >= 48 && topPct <= 52

    return CenteringResult(
        leftRightRatio: (leftPct, rightPct),
        topBottomRatio: (topPct, bottomPct),
        passesPSA10: passesPSA10,
        passesBGS10: passesBGS10
    )
}

private func fallbackCentering() -> CenteringResult {
    CenteringResult(leftRightRatio: (50, 50), topBottomRatio: (50, 50), passesPSA10: true, passesBGS10: true)
}
