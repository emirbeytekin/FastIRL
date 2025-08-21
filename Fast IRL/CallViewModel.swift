import Foundation
import SwiftUI
import AVFoundation
import WebRTC

struct VideoPreset: Identifiable, Hashable {
    let id = UUID()
    let w: Int32
    let h: Int32
    let fps: Int
    let label: String
}

@MainActor
final class CallViewModel: ObservableObject {
    // Public UI state
    @Published var isPublishing = false
    @Published var selectedPreset: VideoPreset
    @Published var currentFps: Int
    @Published var maxBitrateKbps: Double = 4000
    @Published var micOn = true
    @Published var torchOn = false
    @Published var position: AVCaptureDevice.Position = .back
    @Published var lens: LensKind = .wide
    @Published var zoomFactor: CGFloat = 1.0

    // Overlay widgets
    @Published var newWidgetURL: String = "https://example.org"
    @Published var overlaysShown = false { didSet { setupPipeline() } }
    @Published var sidePanelCollapsed = false

    // Core
    let client = WebRTCClient()
    @Published var overlayManager = OverlayManager()
    private(set) var compositor: CompositorVideoCapturer?
    private(set) var cameraCapturer: RTCCameraVideoCapturer?
    private(set) var camera: CameraController?
    lazy var abr = ABRManager(client: client)

    init() {
        self.selectedPreset = VideoPreset(w: 1920, h: 1080, fps: 60, label: "1080p60")
        self.currentFps = 60
        abr.targetMaxKbps = Int(maxBitrateKbps)
        // No auto-start. Wait for user to tap Start.
    }

    func start() {
        guard !isPublishing else { return }
        isPublishing = true
        setupPipeline()
        currentFps = selectedPreset.fps
        client.setVideoMaxBitrate(kbps: Int(maxBitrateKbps))
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
        client.setMicEnabled(micOn)
        abr.enabled = true
        abr.start()
    }

    private func hasActiveOverlays() -> Bool {
        overlaysShown && (!overlayManager.widgets.isEmpty || !overlayManager.videoOverlays.isEmpty)
    }

    private func setupPipeline() {
        let hasOverlays = hasActiveOverlays()
        // Stop existing
        compositor?.stop(); compositor = nil
        camera = nil
        cameraCapturer = nil

        if hasOverlays {
            let comp = CompositorVideoCapturer(source: client.makeVideoSource(), overlayManager: overlayManager, width: selectedPreset.w, height: selectedPreset.h)
            compositor = comp
            let capturer = RTCCameraVideoCapturer(delegate: comp)
            cameraCapturer = capturer
            let cam = CameraController(capturer: capturer)
            camera = cam
            cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
            comp.start()
        } else {
            // Direct pipeline (no overlays)
            let capturer = RTCCameraVideoCapturer(delegate: client.makeVideoSource())
            cameraCapturer = capturer
            let cam = CameraController(capturer: capturer)
            camera = cam
            cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
        }
        
        // Use normal landscape format with proper orientation lock
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
    }

    func stop() {
        guard isPublishing else { return }
        isPublishing = false
        abr.stop()
        compositor?.stop(); compositor = nil
    }

    func applyFPS(_ fps: Int) {
        currentFps = fps
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: fps)
    }

    func restartForPreset(_ preset: VideoPreset) {
        selectedPreset = preset
        camera?.start(position: position, lens: lens, width: preset.w, height: preset.h, fps: preset.fps)
        compositor?.updateOutputSize(width: preset.w, height: preset.h)
        applyFPS(preset.fps)
    }

    func toggleMic() { micOn.toggle(); client.setMicEnabled(micOn) }

    func toggleTorch() { torchOn.toggle(); camera?.setTorch(on: torchOn) }

    func switchCameraPosition() { camera?.switchPosition(); position = (position == .back) ? .front : .back }

    func setLens(_ l: LensKind) { lens = l; camera?.switchLens(l) }

    func onPinch(scale: CGFloat) { zoomFactor *= scale; camera?.setZoom(factor: zoomFactor) }

    func setMaxBitrate(_ kbps: Double) { maxBitrateKbps = kbps; client.setVideoMaxBitrate(kbps: Int(kbps)); abr.targetMaxKbps = Int(kbps) }

    // overlays
    func addOverlayWidget() {
        let wasActive = hasActiveOverlays()
        overlayManager.addWidget(urlString: newWidgetURL, frame: CGRect(x: 200, y: 120, width: 320, height: 180))
        let nowActive = hasActiveOverlays()
        if wasActive != nowActive { setupPipeline() } else { objectWillChange.send() }
    }

    func removeOverlayWidget(id: UUID) {
        let wasActive = hasActiveOverlays()
        overlayManager.removeWidget(id: id)
        let nowActive = hasActiveOverlays()
        if wasActive != nowActive { setupPipeline() } else { objectWillChange.send() }
    }

    // secondary camera
    func addSecondaryCamera(position: AVCaptureDevice.Position) {
        let wasActive = hasActiveOverlays()
        let track = client.makePeerConnectionFactory().videoTrack(with: client.makePeerConnectionFactory().videoSource(), trackId: "sec-\(UUID().uuidString.prefix(6))")
        let model = SecondaryCameraOverlayModel(frame: CGRect(x: 40, y: 40, width: 240, height: 135), track: track)
        overlayManager.addVideoOverlay(model)
        let capture = SecondaryCameraOverlayCapture(model: model, factory: client.makePeerConnectionFactory())
        capture.start(position: position, lens: .wide, width: 640, height: 360, fps: 24)
        let nowActive = hasActiveOverlays()
        if wasActive != nowActive { setupPipeline() } else { objectWillChange.send() }
    }
}


