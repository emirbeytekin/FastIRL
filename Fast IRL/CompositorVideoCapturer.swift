import Foundation
import CoreImage
import CoreGraphics
import UIKit
import WebRTC
import WebKit

// Composes camera frames with overlay widget webviews into a single RTCVideoSource.
final class CompositorVideoCapturer: RTCVideoCapturer, RTCVideoCapturerDelegate {
    private let source: RTCVideoSource
    private let overlayManager: OverlayManager
    private let context = CIContext(options: [.priorityRequestLow: true])
    private var lastCameraPixelBuffer: CVPixelBuffer?
    private var lastRotation: RTCVideoRotation = ._0
    private let compositionQueue = DispatchQueue(label: "com.fastirl.compositor")

    // target output
    private var outputWidth: Int32
    private var outputHeight: Int32

    // No forced rotation offset, let WebRTC handle it naturally

    // HTML overlay snapshot cache (~1 fps to reduce freezing)
    private var lastHtmlOverlayImage: CIImage?
    private var lastHtmlUpdateTime: CFTimeInterval = 0
    private let htmlUpdateInterval: CFTimeInterval = 1.0

    // API compatibility flags
    private var started: Bool = false

    init(source: RTCVideoSource, overlayManager: OverlayManager, width: Int32, height: Int32) {
        self.source = source
        self.overlayManager = overlayManager
        self.outputWidth = width
        self.outputHeight = height
        super.init(delegate: source)
    }

    func start() { started = true }
    func stop() { started = false }

    // Receive camera frames; emit continuously for smooth preview
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard started else { return }
        if let buf = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer {
            lastCameraPixelBuffer = buf
            lastRotation = frame.rotation
            composeAndEmit(camera: buf)
        }
    }

    func updateOutputSize(width: Int32, height: Int32) {
        outputWidth = width
        outputHeight = height
    }

    private func composeAndEmit(camera: CVPixelBuffer) {
        // Simple approach: just emit camera without overlays to test stability
        let camImage = CIImage(cvPixelBuffer: camera)
        let targetSize = CGSize(width: Int(outputWidth), height: Int(outputHeight))
        let scaledImage = scaleAspectFill(camImage, target: targetSize)
        
        compositionQueue.async {
            var outPixelBuffer: CVPixelBuffer?
            let attrs: [NSString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, Int(targetSize.width), Int(targetSize.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outPixelBuffer)
            guard let out = outPixelBuffer else { return }
            self.context.render(scaledImage, to: out)

            let rtcBuf = RTCCVPixelBuffer(pixelBuffer: out)
            let ts = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
            let outFrame = RTCVideoFrame(buffer: rtcBuf, rotation: self.lastRotation, timeStampNs: ts)
            self.delegate?.capturer(self, didCapture: outFrame)
        }
    }
    
    private func processOverlays(camImage: CIImage, widgetsSnapshot: [OverlayWidgetModel], videosSnapshot: [SecondaryCameraOverlayModel]) {
        compositionQueue.async {

            let targetSize = CGSize(width: Int(self.outputWidth), height: Int(self.outputHeight))
            
            // Update HTML overlays at low rate
            let now = CACurrentMediaTime()
            if now - self.lastHtmlUpdateTime >= self.htmlUpdateInterval {
                self.lastHtmlOverlayImage = self.buildHtmlOverlaysImage(size: targetSize, widgets: widgetsSnapshot)
                self.lastHtmlUpdateTime = now
            }

            var composed = camImage
            if let html = self.lastHtmlOverlayImage {
                composed = html.composited(over: composed)
            }

            // Live video overlays (second camera) each frame
            for v in videosSnapshot {
                if let pb = v.lastPixelBuffer {
                    let ci = CIImage(cvPixelBuffer: pb)
                    let sx = v.frame.size.width / ci.extent.width
                    let sy = v.frame.size.height / ci.extent.height
                    let scaled = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    let translated = scaled.transformed(by: CGAffineTransform(translationX: v.frame.origin.x, y: targetSize.height - v.frame.origin.y - v.frame.size.height))
                    composed = translated.composited(over: composed)
                }
            }

            var outPixelBuffer: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(targetSize.width),
                kCVPixelBufferHeightKey: Int(targetSize.height)
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, Int(targetSize.width), Int(targetSize.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outPixelBuffer)
            guard let out = outPixelBuffer else { return }
            self.context.render(composed, to: out)

            let rtcBuf = RTCCVPixelBuffer(pixelBuffer: out)
            let ts = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
            let outFrame = RTCVideoFrame(buffer: rtcBuf, rotation: self.lastRotation, timeStampNs: ts)
            self.delegate?.capturer(self, didCapture: outFrame)
        }
    }



    private func applyRotation(_ image: CIImage, rotation: RTCVideoRotation) -> CIImage {
        let extent = image.extent
        switch rotation {
        case ._0:
            return image
        case ._90:
            return image.transformed(by: CGAffineTransform(rotationAngle: .pi/2))
                .transformed(by: CGAffineTransform(translationX: extent.height, y: 0))
        case ._180:
            return image.transformed(by: CGAffineTransform(rotationAngle: .pi))
                .transformed(by: CGAffineTransform(translationX: extent.width, y: extent.height))
        case ._270:
            return image.transformed(by: CGAffineTransform(rotationAngle: -.pi/2))
                .transformed(by: CGAffineTransform(translationX: 0, y: extent.width))
        @unknown default:
            return image
        }
    }

    private func scaleAspectFill(_ image: CIImage, target: CGSize) -> CIImage {
        let w = image.extent.width
        let h = image.extent.height
        let scale = max(target.width / w, target.height / h)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (target.width - scaled.extent.width) / 2
        let dy = (target.height - scaled.extent.height) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    private func buildHtmlOverlaysImage(size: CGSize, widgets: [OverlayWidgetModel]) -> CIImage? {
        if widgets.isEmpty { return nil }
        var img = CIImage(color: CIColor(color: .clear)).cropped(to: CGRect(origin: .zero, size: size))
        for widget in widgets {
            guard let snapshot = snapshotWebView(widget.webView, targetSize: widget.frame.size) else { continue }
            if let ci = CIImage(image: snapshot) {
                let pos = widget.frame.origin
                let translated = ci.transformed(by: CGAffineTransform(translationX: pos.x, y: size.height - pos.y - ci.extent.height))
                img = translated.composited(over: img)
            }
        }
        return img
    }

    private func snapshotWebView(_ webView: WKWebView, targetSize: CGSize) -> UIImage? {
        var imageOut: UIImage?
        DispatchQueue.main.sync {
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            imageOut = renderer.image { _ in
                webView.drawHierarchy(in: CGRect(origin: .zero, size: targetSize), afterScreenUpdates: false)
            }
        }
        return imageOut
    }
}


