import Foundation
import SwiftUI
import AVFoundation
import WebRTC
import Combine
import HaishinKit

struct VideoPreset: Identifiable, Hashable {
    let id = UUID()
    let w: Int32
    let h: Int32
    let fps: Int
    let label: String
}

struct BitratePreset: Identifiable, Hashable {
    let id = UUID()
    let value: Double
    let label: String
}

enum StreamingMode: String, CaseIterable, Identifiable {
    case webRTC = "WebRTC"
    case srt = "SRT"
    case dual = "Dual Mode"
    
    var id: String { rawValue }
}

@MainActor
final class CallViewModel: ObservableObject {
    // Public UI state
    @Published var isPublishing = false
    @Published var selectedPreset: VideoPreset
    @Published var currentFps: Int = 60
    @Published var maxBitrateKbps: Double = 15000  // 15 Mbps for 1080p60
    @Published var micOn = true
    @Published var torchOn = false
    @Published var position: AVCaptureDevice.Position = .back
    
    // Dual Streaming Support
    @Published var selectedStreamingMode: StreamingMode = .webRTC
    @Published var srtServerURL = "srt://localhost:9001"
    @Published var srtLatency = 120 // milliseconds
    @Published var srtBufferSizeMB = 1 // MB
    
    // Her kamera pozisyonu için ayrı lens ayarları
    @Published var backCameraLens: LensKind = .wide
    @Published var frontCameraLens: LensKind = .wide
    
    // Focus indicator için
    @Published var focusIndicatorLocation: CGPoint? = nil
    
    // Yayın süre takibi
    @Published var streamStartTime: Date? = nil
    @Published var streamDuration: TimeInterval = 0
    private var streamTimer: Timer?
    
    // Yayın boyutu takibi
    @Published var totalStreamBytes: Int64 = 0
    @Published var streamBitrateKbps: Double = 0
    private var lastBitrateUpdate: Date = Date()
    private var bitrateUpdateTimer: Timer?
    
    // Computed property for current lens based on position
    var lens: LensKind {
        get {
            return position == .back ? backCameraLens : frontCameraLens
        }
        set {
            if position == .back {
                backCameraLens = newValue
            } else {
                frontCameraLens = newValue
            }
        }
    }
    @Published var zoomFactor: CGFloat = 1.0
    @Published var stabilizationMode: StabilizationMode = .auto
    @Published var supportedStabilizationModes: [StabilizationMode] = [.off]
    

    
    // Computed property for UI
    var currentLens: LensKind { lens }
    
    // MARK: - Stream Duration Tracking
    
    func startStreamTimer() {
        streamStartTime = Date()
        streamDuration = 0
        
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.streamStartTime else { return }
            
            // Main thread'de @Published property güncelle
            DispatchQueue.main.async {
                self.streamDuration = Date().timeIntervalSince(startTime)
            }
        }
        
        print("⏱️ Yayın süre takibi başlatıldı")
    }
    
    func stopStreamTimer() {
        streamTimer?.invalidate()
        streamTimer = nil
        streamStartTime = nil
        streamDuration = 0
        print("⏱️ Yayın süre takibi durduruldu")
    }
    
    func resetStreamStats() {
        totalStreamBytes = 0
        streamBitrateKbps = 0
        lastBitrateUpdate = Date()
        print("📊 Yayın istatistikleri sıfırlandı")
    }
    
    func updateStreamBitrate(_ currentBitrateKbps: Double) {
        // Main thread'de @Published property güncelle
        DispatchQueue.main.async {
            self.streamBitrateKbps = currentBitrateKbps
            
            // Her saniye bitrate'i toplam boyuta ekle
            let now = Date()
            let timeDiff = now.timeIntervalSince(self.lastBitrateUpdate)
            if timeDiff >= 1.0 {
                let bytesThisSecond = Int64((currentBitrateKbps * 1000 * timeDiff) / 8) // kbps -> bytes
                self.totalStreamBytes += bytesThisSecond
                self.lastBitrateUpdate = now
            }
        }
    }
    
    // MARK: - Computed Properties for UI
    
    var streamDurationFormatted: String {
        let minutes = Int(streamDuration) / 60
        let seconds = Int(streamDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var totalStreamMB: Double {
        return Double(totalStreamBytes) / (1024 * 1024)
    }
    
    var totalStreamMBFormatted: String {
        if totalStreamMB >= 1024 {
            return String(format: "%.1f GB", totalStreamMB / 1024)
        } else {
            return String(format: "%.1f MB", totalStreamMB)
        }
    }

    // Overlay widgets
    @Published var newWidgetURL: String = "https://example.org"
    @Published var newWidgetTitle: String = ""
    @Published var overlaysShown = false { 
        didSet { 
            print("📱 overlaysShown changed to: \(overlaysShown)")
            // Sadece overlay kapatıldığında VE gerçekten widget varsa restart et
            if isPublishing && !overlaysShown && oldValue == true && !overlayManager.widgets.isEmpty {
                print("🔄 Overlay kapatıldı (widget vardı), pipeline restart")
                setupPipeline() 
            } else if isPublishing && !overlaysShown && oldValue == true && overlayManager.widgets.isEmpty {
                print("✅ Overlay kapatıldı ama widget yoktu, pipeline restart yok")
            }
        } 
    }
    @Published var sidePanelCollapsed = false

    // Core
    var client = WebRTCClient()
    @Published var overlayManager = OverlayManager()
    private(set) var compositor: CompositorVideoCapturer?
    private(set) var cameraCapturer: RTCCameraVideoCapturer?
    private(set) var camera: CameraController?
    lazy var abr = ABRManager(client: client)
    
    // Dual Streaming Manager
    lazy var dualStreamingManager = DualStreamingManager()
    
    // OBS WebSocket Manager
    let obsManager = OBSWebSocketManager()
    
    // Signaling Client
    private let signalingClient = SignalingClient()
    @Published var webSocketURL = UserDefaults.standard.string(forKey: "webSocketURL") ?? "ws://173.249.21.219:8080" {
        didSet {
            UserDefaults.standard.set(webSocketURL, forKey: "webSocketURL")
        }
    }
    @Published var roomId: String = "" {
        didSet {
            UserDefaults.standard.set(roomId, forKey: "roomId")
        }
    }
    @Published var isWebSocketConnected = false
    @Published var isWebRTCConnected = false {
        didSet {
            if isWebRTCConnected && !oldValue {
                // WebRTC bağlantısı yeni başladı
                stopWebRTCReconnectTimer()
                
                // Yayın timer'ını başlat
                startStreamTimer()
                resetStreamStats()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showOBSStartStreamAlert = true
                }
            } else if !isWebRTCConnected && oldValue {
                // WebRTC bağlantısı koptu
                print("🔄 WebRTC bağlantısı koptu, yayın durduruluyor...")
                
                // Yayın timer'ını durdur
                stopStreamTimer()
                
                // Yayını durdur
                isPublishing = false
                // ABR'yi devre dışı bırak
                abr.enabled = false
                
                print("✋ Otomatik reconnect devre dışı - manuel bağlantı gerekli")
                // Otomatik reconnect sistemi tamamen kaldırıldı
                isManualDisconnect = false // Flag'i sıfırla
            }
        }
    }

    
    @Published var hasAttemptedConnection = false
    @Published var showWebRTCAlert = false
    @Published var showOBSStartStreamAlert = false
    
    // WebRTC Auto-reconnect properties
    @Published var isWebRTCReconnecting = false
    @Published var webRTCReconnectCountdown = 0
    private var webRTCReconnectTimer: Timer?
    private var webRTCCountdownTimer: Timer?
    private let webRTCReconnectInterval: TimeInterval = 3.0
    private let maxWebRTCReconnectAttempts = 10
    private var webRTCReconnectAttempts = 0
    
    // Manuel disconnect flag'i
    private var isManualDisconnect = false

    
    private var cancellables = Set<AnyCancellable>()
    
    // Settings persistence - UserDefaults will be handled in init and when values change
    

    
    // Multi-camera support
    // Multi-camera kaldırıldı - sadece web widgets
    


    init() {
        // Load saved settings
        if let savedPreset = UserDefaults.standard.string(forKey: "selectedPreset") {
            // Parse saved preset string (e.g., "1920x1080@60")
            let components = savedPreset.components(separatedBy: ["x", "@"])
            if components.count == 3,
               let w = Int(components[0]),
               let h = Int(components[1]),
               let fps = Int(components[2]) {
                self.selectedPreset = VideoPreset(w: Int32(w), h: Int32(h), fps: fps, label: "\(w)x\(h)@\(fps)")
            } else {
                self.selectedPreset = VideoPreset(w: 1920, h: 1080, fps: 60, label: "1080p60")
            }
        } else {
            self.selectedPreset = VideoPreset(w: 1920, h: 1080, fps: 60, label: "1080p60")
        }
        
        // Load other saved settings
        if UserDefaults.standard.double(forKey: "maxBitrateKbps") > 0 {
            self.maxBitrateKbps = UserDefaults.standard.double(forKey: "maxBitrateKbps")
        } else {
            self.maxBitrateKbps = 15000 // Default 15 Mbps
        }
        
        // Load saved widget URL
        if let savedWidgetURL = UserDefaults.standard.string(forKey: "newWidgetURL") {
            self.newWidgetURL = savedWidgetURL
        }
        
        // Load saved stabilization mode
        if let savedStabilization = UserDefaults.standard.string(forKey: "stabilizationMode"),
           let mode = StabilizationMode(rawValue: savedStabilization) {
            self.stabilizationMode = mode
        }
        
        // Stabilization modlarını başlangıçta güncelle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateSupportedStabilizationModes()
        }
        
        // Load saved room ID
        if let savedRoomId = UserDefaults.standard.string(forKey: "roomId") {
            self.roomId = savedRoomId
        }
        
        // Update currentFps to match selectedPreset
        self.currentFps = self.selectedPreset.fps
        abr.targetMaxKbps = Int(maxBitrateKbps)
        // ABR geri beslemeleri ile UI senkronu
        abr.onAdaptQuality = { [weak self] w, h, fps in
            DispatchQueue.main.async {
                self?.selectedPreset = VideoPreset(w: w, h: h, fps: fps, label: "\(w)x\(h)@\(fps)")
                self?.currentFps = fps
            }
        }
        abr.onBitrateChanged = { [weak self] kbps in
            DispatchQueue.main.async {
                self?.maxBitrateKbps = Double(kbps)
            }
        }
        
        print("ℹ️ Sadece web widget'ları destekleniyor (OVERLAY'LER SADECE LOCAL'DE!)")
        print("📱 Loaded settings: \(selectedPreset.label), \(maxBitrateKbps) kbps")
        
        // Signaling client setup
        signalingClient.delegate = self
        client.delegate = self
        
        // Otomatik start - app açılınca yayın başlasın
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🚀 App açıldı, otomatik yayın başlatılıyor...")
            self.start()
        }
        
        // SignalingClient'ın isConnected property'sini observe et
        signalingClient.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isWebSocketConnected = isConnected
            }
            .store(in: &cancellables)
        
        // Sahne değişikliği notification'ını dinle
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🎬 Sahne değişikliği algılandı, WebRTC reconnect countdown sıfırlanıyor...")
            self?.resetWebRTCReconnectCountdown()
        }
    }

    func start() {
        guard !isPublishing else { return }
        isPublishing = true
        setupPipeline()
        currentFps = selectedPreset.fps
        client.setVideoMaxBitrate(kbps: Int(maxBitrateKbps))
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
        client.setMicEnabled(micOn)
        // ABR sadece WebRTC bağlıyken etkili olsun
        abr.enabled = isWebRTCConnected
        abr.start()
        // Stats monitoring will start when WebRTC connection is established
        isSetupInProgress = false
        objectWillChange.send()
    }

    private func hasActiveOverlays() -> Bool {
        // Overlay'ler sadece local'de gösteriliyor, yayına gitmiyor
        let result = false // Her zaman false döndür - overlay'ler yayına gitmesin
        print("🔍 hasActiveOverlays: overlaysShown=\(overlaysShown), widgets.count=\(overlayManager.widgets.count), result=\(result) - OVERLAY'LER SADECE LOCAL'DE!")
        return result
    }

    private var isSetupInProgress = false
    
    private func setupPipeline() {
        // Thread safety: Prevent concurrent setup calls
        guard !isSetupInProgress else {
            print("⚠️ Setup already in progress, skipping...")
            return
        }
        isSetupInProgress = true
        
        let hasOverlays = hasActiveOverlays()
        
        print("🔄 setupPipeline: hasOverlays=\(hasOverlays), compositor=\(compositor != nil), camera=\(camera != nil)")
        
        // Eğer mevcut pipeline aynı türdeyse VE kamera zaten varsa, restart etmeyin
        let currentHasCompositor = compositor != nil
        if currentHasCompositor == hasOverlays && camera != nil {
            print("✅ Pipeline aynı türde, restart etmiyoruz")
            // Sadece compositor'un overlay manager'ını güncelle
            if hasOverlays, let comp = compositor {
                comp.updateOutputSize(width: selectedPreset.w, height: selectedPreset.h)
            }
            isSetupInProgress = false
            return
        }
        
        print("⚠️ Pipeline türü değişiyor, restart gerekiyor...")
        
        // Farklı pipeline türü gerekiyor, yumuşak geçiş yap
        let oldCamera = camera
        
        // Stop existing compositor but keep camera if possible
        // Sadece gerçekten farklı pipeline türü gerekiyorsa durdur
        if let existingCompositor = compositor {
            print("🔄 Compositor durduruluyor (pipeline türü değişiyor)")
            existingCompositor.stop()
        }
        compositor = nil

        if hasOverlays {
            let comp = CompositorVideoCapturer(source: client.makeVideoSource(), overlayManager: overlayManager, width: selectedPreset.w, height: selectedPreset.h)
            compositor = comp
            
            // Sadece single-cam with overlays
            setupSingleCameraWithOverlays(comp: comp, oldCamera: oldCamera)
            
            comp.start()
        } else {
            // Direct pipeline (no overlays)
            if let existingCam = oldCamera, let existingCapturer = cameraCapturer {
                // Mevcut camera'yı direkt WebRTC'ye bağla
                existingCapturer.delegate = client.makeVideoSource()
                camera = existingCam
                cameraCapturer = existingCapturer
            } else {
                // Yeni kamera oluştur - single-cam modu
                let capturer = RTCCameraVideoCapturer(delegate: client.makeVideoSource())
                cameraCapturer = capturer
                let cam = CameraController(capturer: capturer)
                camera = cam
                cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps) {
                    // Update stabilization after camera starts
                    self.updateSupportedStabilizationModes()
                    cam.setStabilizationMode(self.stabilizationMode)
                }
            }
        }
        
        // Use normal landscape format with proper orientation lock
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
        
        // Stabilization modlarını hemen güncelle (kamera başlamadan önce)
        updateStabilizationModesEarly()
        
        isSetupInProgress = false
    }
    
    private func setupSingleCameraWithOverlays(comp: CompositorVideoCapturer, oldCamera: CameraController?) {
        // Eğer mevcut kamera varsa onu kullan, yoksa yeni oluştur
        if let existingCam = oldCamera, let existingCapturer = cameraCapturer {
            // Mevcut camera'yı yeni compositor'a bağla
            existingCapturer.delegate = comp
            camera = existingCam
            cameraCapturer = existingCapturer
        } else {
            // Yeni kamera oluştur
            let capturer = RTCCameraVideoCapturer(delegate: comp)
            cameraCapturer = capturer
            let cam = CameraController(capturer: capturer)
            camera = cam
            cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps) {
                // Update stabilization after camera starts
                self.updateSupportedStabilizationModes()
                cam.setStabilizationMode(self.stabilizationMode)
            }
        }
    }
    


    func stop() {
        guard isPublishing else { return }
        print("🛑 Yayın sonlandırılıyor...")
        isPublishing = false
        // abr.stop()
        
        // WebRTC connection'ını tamamen kapat
        client.close()
        
        // WebRTC bağlantı durumunu false yap
        isWebRTCConnected = false
        
        // Compositor'u durdur
        compositor?.stop()
        compositor = nil
        
        // WebSocket bağlantısını da kapat
        signalingClient.disconnect()
        
        // UI'ı güncelle
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func applyFPS(_ fps: Int) {
        currentFps = fps
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: fps)
    }

    func restartForPreset(_ preset: VideoPreset) {
        print("🔄 Restarting for preset: \(preset.label)")
        
        // Update dual streaming manager video settings
        dualStreamingManager.updateVideoSettings(
            width: Int32(preset.w),
            height: Int32(preset.h),
            fps: Int32(preset.fps),
            bitrate: Int32(maxBitrateKbps)
        )
        
        // Update current settings
        selectedPreset = preset
        currentFps = preset.fps
        
        // Restart camera with new settings
        camera?.start(position: position, lens: lens, width: preset.w, height: preset.h, fps: preset.fps)
        
        // Update WebRTC client
        client.setVideoMaxBitrate(kbps: Int(maxBitrateKbps))
        
        print("✅ Preset applied: \(preset.label)")
    }

    func toggleMic() { 
        micOn.toggle()
        print("🎤 Mic toggled: micOn=\(micOn), isSelected=\(!micOn)")
        client.setMicEnabled(micOn)
    }

    func toggleTorch() { torchOn.toggle(); camera?.setTorch(on: torchOn) }
    


    func switchCameraPosition() { 
        // Prevent camera switch during setup to avoid race conditions
        guard !isSetupInProgress else {
            print("⚠️ Cannot switch camera during setup")
            return
        }
        
        // Hedef pozisyonu belirle
        let newPosition: AVCaptureDevice.Position = (position == .back) ? .front : .back
        
        // Hedef pozisyon için lens ayarını al
        let targetLens: LensKind = newPosition == .back ? backCameraLens : frontCameraLens
        
        print("📷 Kamera değiştiriliyor: \(position == .back ? "Back" : "Front") → \(newPosition == .back ? "Back" : "Front"), Lens: \(targetLens.rawValue)")
        
        // Pozisyonu güncelle
        position = newPosition
        
        // Kamerayı hedef lens ile başlat
        camera?.start(position: newPosition, lens: targetLens, width: 1280, height: 720, fps: camera?.currentFps ?? 60)
    }

    func setLens(_ l: LensKind) { 
        // Lens ayarını mevcut kamera pozisyonuna kaydet
        if position == .back {
            backCameraLens = l
        } else {
            frontCameraLens = l
        }
        
        // Kamerada lens'i değiştir
        camera?.switchLens(l)
        
        print("📷 Lens değiştirildi: \(l.rawValue) (Pozisyon: \(position == .back ? "Back" : "Front"))")
    }
    
    // Manuel focus fonksiyonu
    func setManualFocus(at location: CGPoint) {
        print("🎯 Manuel focus ayarlanıyor: \(location)")
        
        // Focus indicator'ı güncelle
        focusIndicatorLocation = location
        
        // Camera controller'a focus komutu gönder
        camera?.setManualFocus(at: location)
        
        // 3 saniye sonra focus indicator'ı gizle
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
//            self.focusIndicatorLocation = nil
//        }
    }
    
    func enableAutoFocus() {
        print("🎯 Otomatik focus'a geçiliyor...")
        
        // Focus indicator'ı gizle
        focusIndicatorLocation = nil
        
        // Camera controller'a otomatik focus komutu gönder
        camera?.enableAutoFocus()
    }
    
    func cycleLens() {
        let lenses: [LensKind] = [.wide, .ultraWide, .tele]
        if let currentIndex = lenses.firstIndex(of: lens) {
            let nextIndex = (currentIndex + 1) % lenses.count
            let nextLens = lenses[nextIndex]
            setLens(nextLens)
        }
    }

    func onPinch(scale: CGFloat) { zoomFactor *= scale; camera?.setZoom(factor: zoomFactor) }
    

    
    func setStabilizationMode(_ mode: StabilizationMode) {
        stabilizationMode = mode
        camera?.setStabilizationMode(mode)
        // Save to UserDefaults
        UserDefaults.standard.set(mode.rawValue, forKey: "stabilizationMode")
    }
    
    func updateSupportedStabilizationModes() {
        if let camera = camera {
            supportedStabilizationModes = camera.getSupportedStabilizationModes()
            
            // Update current mode if not supported
            if !supportedStabilizationModes.contains(stabilizationMode) {
                stabilizationMode = supportedStabilizationModes.first ?? .off
            }
        }
    }
    
    // Stabilization modlarını erken güncelle (kamera başlamadan önce)
    private func updateStabilizationModesEarly() {
        // Eğer kamera zaten varsa, stabilization modlarını hemen güncelle
        if let camera = camera {
            DispatchQueue.main.async {
                self.updateSupportedStabilizationModes()
            }
        } else {
            // Kamera henüz yoksa, kısa bir süre sonra tekrar dene
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateStabilizationModesEarly()
            }
        }
    }

    func setMaxBitrate(_ kbps: Double) { 
        maxBitrateKbps = kbps; 
        client.setVideoMaxBitrate(kbps: Int(kbps)); 
        abr.targetMaxKbps = Int(kbps)
        UserDefaults.standard.set(kbps, forKey: "maxBitrateKbps")
    }
    
    // MARK: - Dual Streaming Methods
    
    func switchStreamingMode(_ mode: StreamingMode) {
        // Stop current streaming if active
        if isPublishing {
            stop()
        }
        
        selectedStreamingMode = mode
        
        // Update dual streaming manager
        dualStreamingManager.selectedMode = mode
        
        // Update video settings for new mode
        updateVideoSettingsForMode(mode)
        
        print("🔄 Streaming mode switched to: \(mode.rawValue)")
    }
    
    func startSRTStream() {
        print("🚀 Starting SRT stream to: \(srtServerURL)")
        
        // Sync URL with DualStreamingManager
        dualStreamingManager.srtServerURL = srtServerURL
        dualStreamingManager.srtLatency = srtLatency
        dualStreamingManager.srtBufferSize = srtBufferSizeMB * 1024 * 1024
        
        dualStreamingManager.startStreaming()
    }
    
    func stopSRTStream() {
        print("🛑 Stopping SRT stream...")
        dualStreamingManager.stopStreaming()
    }
    
    // MARK: - Dual Mode Coordination
    func startDualMode() {
        print("🚀 Starting Dual Mode (WebRTC + SRT)...")
        
        // Start WebRTC first
        if !isPublishing {
            start()
        }
        
        // Start SRT stream
        startSRTStream()
        
        print("✅ Dual Mode started")
    }
    
    func stopDualMode() {
        print("🛑 Stopping Dual Mode...")
        
        // Stop SRT stream
        stopSRTStream()
        
        // Stop WebRTC if it was started by dual mode
        if isPublishing {
            stop()
        }
        
        print("✅ Dual Mode stopped")
    }
    
    private func updateVideoSettingsForMode(_ mode: StreamingMode) {
        switch mode {
        case .webRTC:
            // WebRTC settings remain the same
            break
        case .srt:
            // SRT settings - lower bitrate for better stability
            setMaxBitrate(5000) // 5 Mbps for SRT
            print("📡 SRT mode: Bitrate set to 5 Mbps")
        case .dual:
            // Dual mode - balanced settings
            setMaxBitrate(8000) // 8 Mbps for dual streaming
            print("📡 Dual mode: Bitrate set to 8 Mbps")
        }
    }

    // overlays
    func addOverlayWidget() {
        // Prevent widget operations during setup to avoid race conditions
        guard !isSetupInProgress else {
            print("⚠️ Cannot add widget during setup")
            return
        }
        
        let wasActive = hasActiveOverlays()
        let title = newWidgetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        overlayManager.addWidget(urlString: newWidgetURL, frame: CGRect(x: 200, y: 120, width: 320, height: 180), title: title)
        // Save widget URL to UserDefaults
        UserDefaults.standard.set(newWidgetURL, forKey: "newWidgetURL")
        let nowActive = hasActiveOverlays()
        
        print("➕ addOverlayWidget: wasActive=\(wasActive), nowActive=\(nowActive)")
        
        if wasActive != nowActive { 
            print("🔄 Widget durumu değişti, pipeline restart")
            setupPipeline() 
        } else { 
            print("✅ Widget eklendi, pipeline restart yok")
            // Sadece overlay manager'ını güncelle, pipeline'ı restart etme
            compositor?.updateOverlayManager(overlayManager)
            objectWillChange.send() 
        }
    }

    func removeOverlayWidget(id: UUID) {
        // Prevent widget operations during setup to avoid race conditions
        guard !isSetupInProgress else {
            print("⚠️ Cannot remove widget during setup")
            return
        }
        
        let wasActive = hasActiveOverlays()
        overlayManager.removeWidget(id: id)
        let nowActive = hasActiveOverlays()
        
        print("➖ removeOverlayWidget: wasActive=\(wasActive), nowActive=\(nowActive)")
        
        if wasActive != nowActive { 
            print("🔄 Widget durumu değişti, pipeline restart")
            setupPipeline() 
        } else {
            print("✅ Widget silindi, pipeline restart yok")
        }
        
        // UI her zaman güncellensin - widget silindiyse görünümden de gitsin
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    // Secondary camera kaldırıldı - sadece web widgets destekleniyor
    
    // MARK: - Signaling Functions
    
    func connectWebSocket() {
        // Oda ID kontrolü
        guard !roomId.isEmpty else {
            print("❌ Oda ID boş olamaz!")
            return
        }
        
        guard roomId.count == 6 else {
            print("❌ Oda ID 6 karakter olmalı! Mevcut: \(roomId.count)")
            return
        }
        
        // Oda ID'yi WebSocket URL'ine ekle
        var wsURL = webSocketURL
        if wsURL.hasSuffix("/") {
            wsURL += roomId
        } else {
            wsURL += "/" + roomId
        }
        
        guard let url = URL(string: wsURL) else {
            print("❌ Invalid WebSocket URL: \(wsURL)")
            return
        }
        hasAttemptedConnection = true
        
        print("🔌 WebSocket bağlantısı başlatılıyor: \(wsURL)")
        
        // Kamera pipeline'ını yeniden başlat
        print("📹 Kamera pipeline yeniden başlatılıyor...")
        setupPipeline()
        
        signalingClient.connect(to: url)
    }
    

    
    func disconnectWebSocket() {
        print("🔌 WebSocket bağlantısı kesiliyor...")
        
        // Manuel disconnect flag'ini set et
        isManualDisconnect = true
        
        // WebRTC reconnect timer'ını durdur (manuel disconnect)
        stopWebRTCReconnectTimer()
        
        // Yayın timer'ını durdur
        stopStreamTimer()
        
        // Her şeyi tamamen resetle
        isPublishing = false
        isWebRTCConnected = false
        
        // Kamera pipeline'ını tamamen temizle
        print("📹 Kamera pipeline temizleniyor...")
        cameraCapturer?.stopCapture()
        camera = nil
        cameraCapturer = nil
        
        // Compositor'u durdur
        compositor?.stop()
        compositor = nil
        
        // WebRTC connection'ını tamamen kapat
        client.close()
        
        // WebRTC client'ı sıfırla
        client = WebRTCClient()
        client.delegate = self
        
        // WebSocket bağlantısını kapat
        signalingClient.disconnect()
        
        // UI'ı güncelle
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("🔄 Tüm bağlantılar, yayın durumu ve kamera pipeline sıfırlandı, yeni WebRTC client oluşturuldu")
    }
    
    func sendOffer() {
        print("📡 Offer oluşturuluyor...")
        client.createOffer { [weak self] sdp in
            print("📡 Offer callback çalıştı")
            print("📡 SDP uzunluğu: \(sdp.count)")
            print("📡 SDP ilk 100 karakter: \(String(sdp.prefix(100)))")
            print("📡 SDP son 100 karakter: \(String(sdp.suffix(100)))")
            
            // SDP'nin geçerli olup olmadığını kontrol et
            if !sdp.hasPrefix("v=") {
                print("❌ SDP geçersiz! 'v=' ile başlamıyor")
                print("❌ SDP başlangıcı: \(sdp.prefix(10))")
                return
            }
            
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            print("📡 RTCSessionDescription oluşturuldu")
            print("📡 Offer type: \(offer.type.rawValue)")
            print("📡 Offer SDP uzunluğu: \(offer.sdp.count)")
            
            self?.signalingClient.sendOffer(offer)
            print("📡 Offer SignalingClient'a gönderildi")
        }
    }
}

// MARK: - SignalingClientDelegate
extension CallViewModel: SignalingClientDelegate {
    func signalingClientDidConnect(_ client: SignalingClient) {
        print("✅ WebSocket bağlandı")
        isWebSocketConnected = true
        
        // Otomatik olarak offer gönder ve yayını başlat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📡 WebSocket bağlandı, offer gönderiliyor...")
            self.sendOffer()
            
            // Offer gönderildikten sonra yayını başlat
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !self.isPublishing {
                    print("🚀 WebSocket bağlandı, yayın başlatılıyor...")
                    self.start()
                }
            }
        }
    }
    
    func signalingClientDidDisconnect(_ client: SignalingClient) {
        print("❌ WebSocket bağlantısı kesildi")
        isWebSocketConnected = false
        // Not: Otomatik yayın sonlandırma kaldırıldı - kullanıcı manuel disconnect butonu ile durduracak
    }
    

    

    
    func signalingClient(_ client: SignalingClient, didReceiveOffer offer: RTCSessionDescription) {
        print("📨 Offer alındı")
        self.client.pc.setRemoteDescription(offer) { [weak self] error in
            if let error = error {
                print("❌ Remote description error: \(error)")
                return
            }
            
            // Create answer
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
                optionalConstraints: nil
            )
            
            self?.client.pc.answer(for: constraints) { sdp, error in
                guard let sdp = sdp, error == nil else {
                    print("❌ Answer creation error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                self?.client.pc.setLocalDescription(sdp) { error in
                    if let error = error {
                        print("❌ Local description error: \(error)")
                        return
                    }
                    
                    self?.signalingClient.sendAnswer(sdp)
                    print("✅ Answer gönderildi")
                }
            }
        }
    }
    
    func signalingClient(_ client: SignalingClient, didReceiveAnswer answer: RTCSessionDescription) {
        print("📨 Answer alındı")
        self.client.setRemoteAnswer(answer.sdp)
    }
    
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate) {
        print("📨 ICE Candidate alındı")
        self.client.pc.add(candidate)
    }
}

// MARK: - WebRTCClientDelegate
extension CallViewModel: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didGenerate candidate: RTCIceCandidate) {
        print("📡 ICE Candidate oluşturuldu")
        signalingClient.sendIceCandidate(candidate)
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            self.isWebRTCConnected = (state == .connected)
            
            let stateDescription: String
            switch state {
            case .new: stateDescription = "new"
            case .connecting: stateDescription = "connecting"
            case .connected: stateDescription = "connected"
            case .disconnected: 
                stateDescription = "disconnected"
                // WebRTC bağlantısı kesildiğinde alert göster
                if self.isPublishing {
                    self.showWebRTCAlert = true
                }
            case .failed: 
                stateDescription = "failed"
                // Connection failed durumunda da alert göster
                if self.isPublishing {
                    self.showWebRTCAlert = true
                }
            case .closed: stateDescription = "closed"
            @unknown default: stateDescription = "unknown"
            }
            
            print("🔗 WebRTC Connection UI updated: \(stateDescription)")
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didUpdateBitrate bitrateKbps: Double) {
        DispatchQueue.main.async {
            self.updateStreamBitrate(bitrateKbps)
        }
    }
    
    // MARK: - WebRTC Auto-Reconnect Methods
    
    private func startWebRTCReconnectTimer() {
        guard webRTCReconnectAttempts < maxWebRTCReconnectAttempts else { 
            print("❌ WebRTC max reconnect attempts reached")
            stopWebRTCReconnectTimer()
            return 
        }
        
        // Önceki timer'ları temizle
        webRTCReconnectTimer?.invalidate()
        webRTCCountdownTimer?.invalidate()
        
        isWebRTCReconnecting = true
        webRTCReconnectCountdown = Int(webRTCReconnectInterval)
        
        print("🔄 WebRTC reconnect timer başlatıldı, \(webRTCReconnectCountdown) saniye... (deneme: \(webRTCReconnectAttempts + 1)/\(maxWebRTCReconnectAttempts))")
        
        // Countdown timer
        webRTCCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.webRTCReconnectCountdown -= 1
                print("⏰ WebRTC reconnect countdown: \(self.webRTCReconnectCountdown)")
                if self.webRTCReconnectCountdown <= 0 {
                    self.webRTCCountdownTimer?.invalidate()
                    self.webRTCCountdownTimer = nil
                }
            }
        }
        
        // Reconnect timer
        webRTCReconnectTimer = Timer.scheduledTimer(withTimeInterval: webRTCReconnectInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.attemptWebRTCReconnect()
            }
        }
    }
    
    private func stopWebRTCReconnectTimer() {
        webRTCReconnectTimer?.invalidate()
        webRTCReconnectTimer = nil
        webRTCCountdownTimer?.invalidate()
        webRTCCountdownTimer = nil
        isWebRTCReconnecting = false
        webRTCReconnectAttempts = 0
        webRTCReconnectCountdown = 0
        print("✅ WebRTC reconnect timer durduruldu")
    }
    
    private func resetWebRTCReconnectCountdown() {
        // Timer'ları durdur
        webRTCReconnectTimer?.invalidate()
        webRTCReconnectTimer = nil
        webRTCCountdownTimer?.invalidate()
        webRTCCountdownTimer = nil
        
        // State'i sıfırla
        isWebRTCReconnecting = false
        webRTCReconnectAttempts = 0
        webRTCReconnectCountdown = 0
        
        print("🔄 WebRTC reconnect countdown sahne değişikliği nedeniyle sıfırlandı")
    }
    
    private func attemptWebRTCReconnect() {
        guard isWebRTCReconnecting && webRTCReconnectAttempts < maxWebRTCReconnectAttempts else {
            print("❌ WebRTC reconnect max attempt sayısına ulaşıldı")
            stopWebRTCReconnectTimer()
            return
        }
        
        webRTCReconnectAttempts += 1
        print("🔄 WebRTC reconnect denemesi \(webRTCReconnectAttempts)/\(maxWebRTCReconnectAttempts)")
        
        // COMPLETE RESET: Tüm WebRTC state'i temizle
        print("🧹 WebRTC complete reset başlatılıyor...")
        
        // 1. Mevcut connection'ları kapat
        client.close()
        signalingClient.disconnect()
        
        // 2. State'i sıfırla
        isWebRTCConnected = false
        isPublishing = false
        
        // 3. Pipeline'ı yeniden kur
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔧 Pipeline yeniden kuruluyor...")
            self.setupPipeline()
            
            // 4. WebSocket bağlantısını yeniden başlat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📡 WebSocket yeniden bağlanıyor...")
                self.connectWebSocket()
                
                // 5. WebRTC bağlantısını başlat
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🎥 WebRTC bağlantısı başlatılıyor...")
                    self.connectWebRTC()
                    
                    // 6. Bağlantı kontrolü
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if !self.isWebRTCConnected && self.isWebRTCReconnecting {
                            print("🔄 WebRTC bağlantısı başarısız, bir sonraki deneme için timer başlatılıyor...")
                            self.startWebRTCReconnectTimer()
                        } else if self.isWebRTCConnected {
                            print("✅ WebRTC bağlantısı başarılı!")
                            self.stopWebRTCReconnectTimer()
                            
                            // WebRTC bağlandıktan sonra yayını yeniden başlat
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if !self.isPublishing {
                                    print("🚀 WebRTC bağlandı, yayın yeniden başlatılıyor...")
                                    self.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func connectWebRTC() {
        // WebRTC bağlantısını başlat
        guard let url = URL(string: webSocketURL) else {
            print("❌ Geçersiz WebSocket URL: \(webSocketURL)")
            return
        }
        
        print("📡 WebRTC bağlantısı için signaling başlatılıyor: \(webSocketURL)")
        signalingClient.connect(to: url)
    }
    
    func forceWebRTCReconnect() {
        print("🚀 Zorla WebRTC yeniden bağlanma başlatıldı...")
        
        // Mevcut timer'ları durdur
        stopWebRTCReconnectTimer()
        
        // Attempt sayısını sıfırla
        webRTCReconnectAttempts = 0
        
        // COMPLETE RESET: Tüm WebRTC state'i temizle
        print("🧹 Force reconnect: WebRTC complete reset başlatılıyor...")
        
        // 1. Mevcut connection'ları kapat
        client.close()
        signalingClient.disconnect()
        
        // 2. State'i sıfırla
        isWebRTCConnected = false
        isPublishing = false
        
        // 3. Pipeline'ı yeniden kur
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔧 Force reconnect: Pipeline yeniden kuruluyor...")
            self.setupPipeline()
            
            // 4. WebSocket bağlantısını yeniden başlat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📡 Force reconnect: WebSocket yeniden bağlanıyor...")
                self.connectWebSocket()
                
                // 5. WebRTC bağlantısını başlat
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🎥 Force reconnect: WebRTC bağlantısı başlatılıyor...")
                    self.connectWebRTC()
                    
                    // 6. Bağlantı kontrolü
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if !self.isWebRTCConnected {
                            print("🔄 Force reconnect sonrası bağlantı kurulamadı, timer başlatılıyor...")
                            self.startWebRTCReconnectTimer()
                        } else {
                            print("✅ Force reconnect başarılı!")
                            
                            // WebRTC bağlandıktan sonra yayını yeniden başlat
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if !self.isPublishing {
                                    print("🚀 Force reconnect sonrası yayın yeniden başlatılıyor...")
                                    self.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}




