import Foundation
import AVFoundation
import WebRTC

final class SecondaryCameraOverlayCapture {
    private let controller: CameraController
    private weak var model: SecondaryCameraOverlayModel?
    private let overlaySource: RTCVideoSource
    private let overlayTrack: RTCVideoTrack
    private let tap: PixelBufferTap

    init(model: SecondaryCameraOverlayModel, factory: RTCPeerConnectionFactory) {
        self.model = model
        self.overlaySource = factory.videoSource()
        self.overlayTrack = factory.videoTrack(with: overlaySource, trackId: "video-sec-\(UUID().uuidString.prefix(6))")
        self.controller = CameraController(capturer: RTCCameraVideoCapturer(delegate: overlaySource))
        self.tap = PixelBufferTap { [weak model] pb in model?.lastPixelBuffer = pb }
        overlayTrack.add(tap)
        model.track = overlayTrack
    }

    func start(position: AVCaptureDevice.Position = .front, lens: LensKind = .wide, width: Int32 = 640, height: Int32 = 360, fps: Int = 24) {
        controller.start(position: position, lens: lens, width: width, height: height, fps: fps)
    }

    func stop() { }
}

final class PixelBufferTap: NSObject, RTCVideoRenderer {
    private let onPixel: (CVPixelBuffer) -> Void
    init(onPixel: @escaping (CVPixelBuffer) -> Void) { self.onPixel = onPixel }
    func setSize(_ size: CGSize) { }
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pb = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else { return }
        DispatchQueue.main.async { [onPixel] in onPixel(pb) }
    }
}


