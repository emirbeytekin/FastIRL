import Foundation
import AVFoundation
import WebRTC

enum LensKind: String, CaseIterable, Identifiable {
    case ultraWide = "Ultra Wide"
    case wide      = "Normal"
    case tele      = "Tele"
    var id: String { rawValue }
}

final class CameraController: NSObject {
    private let capturer: RTCCameraVideoCapturer
    private(set) var currentDevice: AVCaptureDevice?
    private(set) var currentFormat: AVCaptureDevice.Format?
    private(set) var currentFps: Int = 30

    init(capturer: RTCCameraVideoCapturer) {
        self.capturer = capturer
        super.init()
    }

    func device(position: AVCaptureDevice.Position, lens: LensKind) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType]
        switch lens {
        case .ultraWide: types = [.builtInUltraWideCamera]
        case .wide:      types = [.builtInWideAngleCamera]
        case .tele:      types = [.builtInTelephotoCamera]
        }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        return session.devices.first
    }

    func bestFormat(for device: AVCaptureDevice, targetW: Int32, targetH: Int32, targetFps: Int) -> (AVCaptureDevice.Format, Int) {
        var best: (AVCaptureDevice.Format, Int)?
        for fmt in RTCCameraVideoCapturer.supportedFormats(for: device) {
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            guard let range = fmt.videoSupportedFrameRateRanges.first else { continue }
            let okFps = min(Int(range.maxFrameRate), targetFps)
            if best == nil {
                best = (fmt, okFps)
                continue
            }
            let (currFmt, _) = best!
            let cd = CMVideoFormatDescriptionGetDimensions(currFmt.formatDescription)
            let currScore = abs(Int(cd.width - targetW)) + abs(Int(cd.height - targetH))
            let newScore  = abs(Int(dims.width - targetW)) + abs(Int(dims.height - targetH))
            if newScore < currScore { best = (fmt, okFps) }
        }
        if let best { return best }
        let dur = device.activeVideoMaxFrameDuration
        let fps = dur.value != 0 ? Int(Double(dur.timescale) / Double(dur.value)) : 30
        return (device.activeFormat, fps)
    }

    func start(position: AVCaptureDevice.Position, lens: LensKind, width: Int32, height: Int32, fps: Int, completion: (() -> Void)? = nil) {
        let dev = device(position: position, lens: lens) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        guard let dev else { return }
        // Keep original format, add explicit video orientation after capture
        let (fmt, chosenFps) = bestFormat(for: dev, targetW: width, targetH: height, targetFps: fps)
        currentDevice = dev
        currentFormat = fmt
        currentFps = chosenFps
        capturer.stopCapture { [weak self] in
            guard let self else { return }
            self.capturer.startCapture(with: dev, format: fmt, fps: chosenFps) { [weak self] _ in 
                // Force camera orientation to match app orientation
                DispatchQueue.main.async {
                    if let connection = self?.capturer.captureSession.outputs.first?.connection(with: .video) {
                        if connection.isVideoOrientationSupported {
                            // Front camera needs different orientation to avoid upside-down
                            let orientation: AVCaptureVideoOrientation = (position == .front) ? .landscapeLeft : .landscapeRight
                            connection.videoOrientation = orientation
                        }
                    }
                }
                completion?() 
            }
        }
    }

    func switchPosition() {
        guard let dev = currentDevice else { return }
        let newPos: AVCaptureDevice.Position = dev.position == .front ? .back : .front
        start(position: newPos, lens: .wide, width: 1280, height: 720, fps: currentFps) {
            // Ensure orientation is set after position switch
            if let connection = self.capturer.captureSession.outputs.first?.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    // Front camera needs different orientation to avoid upside-down
                    let orientation: AVCaptureVideoOrientation = (newPos == .front) ? .landscapeLeft : .landscapeRight
                    connection.videoOrientation = orientation
                }
            }
        }
    }

    func switchLens(_ lens: LensKind) {
        guard let pos = currentDevice?.position else { return }
        start(position: pos, lens: lens, width: 1280, height: 720, fps: currentFps)
    }

    func setZoom(factor: CGFloat) {
        guard let dev = currentDevice else { return }
        do {
            try dev.lockForConfiguration()
            let clamped = max(dev.minAvailableVideoZoomFactor, min(factor, dev.maxAvailableVideoZoomFactor))
            dev.videoZoomFactor = clamped
            dev.unlockForConfiguration()
        } catch { }
    }

    func setTorch(on: Bool) {
        guard let dev = currentDevice, dev.position == .back, dev.hasTorch else { return }
        do {
            try dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        } catch { }
    }
}


