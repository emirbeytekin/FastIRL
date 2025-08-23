import Foundation
import AVFoundation
import WebRTC

enum LensKind: String, CaseIterable, Identifiable {
    case ultraWide = "Ultra Wide"
    case wide      = "Normal"
    case tele      = "Tele"
    var id: String { rawValue }
}

enum StabilizationMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case standard = "Standard"
    case cinematic = "Cinematic"
    case cinematicExtended = "Cinematic Extended"
    case auto = "Auto"
    
    var id: String { rawValue }
    
    var avMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off: return .off
        case .standard: return .standard
        case .cinematic: return .cinematic
        case .cinematicExtended: return .cinematicExtended
        case .auto: return .auto
        }
    }
}

// CameraMode enum kaldırıldı - sadece single-cam modu destekleniyor

final class CameraController: NSObject {
    let capturer: RTCCameraVideoCapturer
    private(set) var currentDevice: AVCaptureDevice?
    private(set) var currentFormat: AVCaptureDevice.Format?
    private(set) var currentFps: Int = 30
    
    // Multi-camera support kaldırıldı - sadece single-cam modu

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
        let supportedFormats = RTCCameraVideoCapturer.supportedFormats(for: device)
        print("📷 Device: \(device.localizedName), Total formats: \(supportedFormats.count)")
        
        for (i, fmt) in supportedFormats.enumerated() {
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            guard let range = fmt.videoSupportedFrameRateRanges.first else { continue }
            let okFps = min(Int(range.maxFrameRate), targetFps)
            print("📷 Format \(i): \(dims.width)x\(dims.height), FPS: \(Int(range.minFrameRate))-\(Int(range.maxFrameRate))")
            if best == nil {
                best = (fmt, okFps)
                continue
            }
            let (currFmt, currFps) = best!
            let cd = CMVideoFormatDescriptionGetDimensions(currFmt.formatDescription)
            
            // Prioritize higher resolution if both support target FPS
            let currentSupportsTargetFps = currFps >= targetFps
            let newSupportsTargetFps = okFps >= targetFps
            
            if newSupportsTargetFps && !currentSupportsTargetFps {
                // New format supports target FPS, current doesn't - choose new
                best = (fmt, okFps)
            } else if currentSupportsTargetFps && !newSupportsTargetFps {
                // Current supports target FPS, new doesn't - keep current
                continue
            } else {
                // Both support or both don't support target FPS - choose by resolution
                let currPixels = Int(cd.width) * Int(cd.height)
                let newPixels = Int(dims.width) * Int(dims.height)
                let targetPixels = Int(targetW) * Int(targetH)
                
                // Prefer format closest to target pixels, but prefer higher if equal distance
                let currDistance = abs(currPixels - targetPixels)
                let newDistance = abs(newPixels - targetPixels)
                
                if newDistance < currDistance || 
                   (newDistance == currDistance && newPixels > currPixels) {
                    best = (fmt, okFps)
                }
            }
        }
        if let best { 
            let dims = CMVideoFormatDescriptionGetDimensions(best.0.formatDescription)
            print("📷 ✅ Best format selected: \(dims.width)x\(dims.height)@\(best.1)fps")
            return best 
        }
        let dur = device.activeVideoMaxFrameDuration
        let fps = dur.value != 0 ? Int(Double(dur.timescale) / Double(dur.value)) : 30
        print("📷 ⚠️ Fallback to device.activeFormat")
        return (device.activeFormat, fps)
    }

    func start(position: AVCaptureDevice.Position, lens: LensKind, width: Int32, height: Int32, fps: Int, completion: (() -> Void)? = nil) {
        // Sadece single-cam modu destekleniyor
        startSingleCam(position: position, lens: lens, width: width, height: height, fps: fps, completion: completion)
    }
    
    private func startSingleCam(position: AVCaptureDevice.Position, lens: LensKind, width: Int32, height: Int32, fps: Int, completion: (() -> Void)? = nil) {
        let dev = device(position: position, lens: lens) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        guard let dev else { return }
        // Keep original format, add explicit video orientation after capture
        let (fmt, chosenFps) = bestFormat(for: dev, targetW: width, targetH: height, targetFps: fps)
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        print("📷 Camera: \(position == .front ? "Front" : "Back"), Target: \(width)x\(height)@\(fps)fps")
        print("📷 Selected: \(dims.width)x\(dims.height)@\(chosenFps)fps")
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
    
    // Multi-cam fonksiyonu kaldırıldı

    func switchPosition() {
        guard let dev = currentDevice else { return }
        let newPos: AVCaptureDevice.Position = dev.position == .front ? .back : .front
        
        // Mevcut lens ayarını sakla (varsayılan olarak .wide kullan)
        let currentLens: LensKind = .wide
        
        start(position: newPos, lens: currentLens, width: 1280, height: 720, fps: currentFps) {
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
    
    // MARK: - Video Stabilization
    
    func getSupportedStabilizationModes() -> [StabilizationMode] {
        guard let connection = capturer.captureSession.outputs.first?.connection(with: .video) else {
            return [.off]
        }
        
        var supportedModes: [StabilizationMode] = [.off] // Off her zaman desteklenir
        
        if connection.isVideoStabilizationSupported {
            // iOS'da tüm stabilization modları genellikle desteklenir
            supportedModes.append(contentsOf: [.standard, .cinematic, .auto])
            
            // iOS 13+ için cinematicExtended kontrol et
            if #available(iOS 13.0, *) {
                supportedModes.append(.cinematicExtended)
            }
        }
        
        return supportedModes
    }
    
    func getCurrentStabilizationMode() -> StabilizationMode {
        guard let connection = capturer.captureSession.outputs.first?.connection(with: .video) else {
            return .off
        }
        
        let currentMode = connection.preferredVideoStabilizationMode
        return StabilizationMode.allCases.first { $0.avMode == currentMode } ?? .off
    }
    
    func setStabilizationMode(_ mode: StabilizationMode) {
        guard let connection = capturer.captureSession.outputs.first?.connection(with: .video) else {
            print("❌ Video connection bulunamadı")
            return
        }
        
        if !connection.isVideoStabilizationSupported && mode != .off {
            print("❌ Video stabilization desteklenmiyor")
            return
        }
        
        // iOS 13+ için cinematicExtended kontrolü
        if mode == .cinematicExtended {
            if #available(iOS 13.0, *) {
                connection.preferredVideoStabilizationMode = mode.avMode
            } else {
                print("❌ Cinematic Extended iOS 13+ gerektirir")
                return
            }
        } else {
            connection.preferredVideoStabilizationMode = mode.avMode
        }
        
        print("✅ Stabilization modu ayarlandı: \(mode.rawValue)")
    }
    
    // MARK: - Manual Focus
    
    func setManualFocus(at point: CGPoint) {
        guard let deviceInput = capturer.captureSession.inputs.first as? AVCaptureDeviceInput else {
            print("❌ Camera device bulunamadı")
            return
        }
        
        let device = deviceInput.device
        
        // Focus point'i normalize et (0.0 - 1.0 arası)
        let normalizedPoint = CGPoint(
            x: point.x / (capturer.captureSession.sessionPreset == .hd1920x1080 ? 1920 : 1280),
            y: point.y / (capturer.captureSession.sessionPreset == .hd1920x1080 ? 1080 : 720)
        )
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalizedPoint
                device.focusMode = .autoFocus
                print("🎯 Manuel focus ayarlandı: \(normalizedPoint)")
            } else {
                print("❌ Manuel focus desteklenmiyor")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Manuel focus ayarlanamadı: \(error)")
        }
    }
    
    func enableAutoFocus() {
        guard let deviceInput = capturer.captureSession.inputs.first as? AVCaptureDeviceInput else {
            print("❌ Camera device bulunamadı")
            return
        }
        
        let device = deviceInput.device
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                print("🎯 Otomatik focus'a geçildi (Continuous Auto Focus)")
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                print("🎯 Otomatik focus'a geçildi (Auto Focus)")
            } else {
                print("❌ Otomatik focus desteklenmiyor")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Otomatik focus ayarlanamadı: \(error)")
        }
    }


}


