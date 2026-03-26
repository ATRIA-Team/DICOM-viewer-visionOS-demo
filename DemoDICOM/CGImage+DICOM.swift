//
//  CGImage+DICOM.swift
//  DemoDICOM
//
//  Created on 25/03/2026.
//

import CoreGraphics
import Foundation

extension CGImage {
    
    /// Creates a grayscale CGImage from 8-bit windowed pixel data produced by
    /// `DCMWindowingProcessor.applyWindowLevel(pixels16:center:width:)`.
    ///
    /// - Parameters:
    ///   - data: Raw 8-bit grayscale pixel bytes (length = width × height).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: A grayscale `CGImage`, or `nil` if the input is invalid.
    static func fromDICOMWindowedData(_ data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, data.count == width * height else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
