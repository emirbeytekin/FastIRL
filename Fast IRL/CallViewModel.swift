import Foundation
import SwiftUI
import AVFoundation
import WebRTC
import Combine

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
    @Published var lens: LensKind = .wide
    @Published var zoomFactor: CGFloat = 1.0

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
    
    // Signaling
    let signalingClient = SignalingClient()
    @Published var webSocketURL = UserDefaults.standard.string(forKey: "webSocketURL") ?? "http://192.168.0.219:8080" {
        didSet {
            UserDefaults.standard.set(webSocketURL, forKey: "webSocketURL")
        }
    }
    @Published var isWebSocketConnected = false
    @Published var isWebRTCConnected = false
    @Published var hasAttemptedConnection = false
    @Published var showWebRTCAlert = false

    
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
        
        // Load saved room ID
//        if let savedRoomId = UserDefaults.standard.string(forKey: "roomId") {
//            self.roomId = savedRoomId
//        }
        
        // Update currentFps to match selectedPreset
        self.currentFps = self.selectedPreset.fps
        abr.targetMaxKbps = Int(maxBitrateKbps)
        
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
    }

    func start() {
        guard !isPublishing else { return }
        isPublishing = true
        setupPipeline()
        currentFps = selectedPreset.fps
        client.setVideoMaxBitrate(kbps: Int(maxBitrateKbps))
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
        client.setMicEnabled(micOn)
        // ABR temporarily disabled for better quality
        // abr.enabled = true
        // abr.start()
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
                cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
            }
        }
        
        // Use normal landscape format with proper orientation lock
        client.adaptOutputFormat(width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
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
            cam.start(position: position, lens: lens, width: selectedPreset.w, height: selectedPreset.h, fps: selectedPreset.fps)
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
        selectedPreset = preset
        // Save to UserDefaults
        UserDefaults.standard.set("\(preset.w)x\(preset.h)@\(preset.fps)", forKey: "selectedPreset")
        
        camera?.start(position: position, lens: lens, width: preset.w, height: preset.h, fps: preset.fps)
        compositor?.updateOutputSize(width: preset.w, height: preset.h)
        applyFPS(preset.fps)
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
        camera?.switchPosition(); 
        position = (position == .back) ? .front : .back 
    }

    func setLens(_ l: LensKind) { lens = l; camera?.switchLens(l) }

    func onPinch(scale: CGFloat) { zoomFactor *= scale; camera?.setZoom(factor: zoomFactor) }

    func setMaxBitrate(_ kbps: Double) { 
        maxBitrateKbps = kbps; 
        client.setVideoMaxBitrate(kbps: Int(kbps)); 
        abr.targetMaxKbps = Int(kbps)
        UserDefaults.standard.set(kbps, forKey: "maxBitrateKbps")
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
        guard let url = URL(string: webSocketURL) else {
            print("❌ Invalid WebSocket URL: \(webSocketURL)")
            return
        }
        hasAttemptedConnection = true
        

        
        signalingClient.connect(to: url)
    }
    

    
    func disconnectWebSocket() {
        print("🔌 WebSocket bağlantısı kesiliyor...")
        
        // Her şeyi tamamen resetle
        isPublishing = false
        isWebRTCConnected = false
        
        // WebRTC connection'ını tamamen kapat
        client.close()
        
        // Compositor'u durdur
        compositor?.stop()
        compositor = nil
        
        // WebRTC client'ı sıfırla
        client = WebRTCClient()
        client.delegate = self
        
        // WebSocket bağlantısını kapat
        signalingClient.disconnect()
        
        // UI'ı güncelle
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("🔄 Tüm bağlantılar ve yayın durumu sıfırlandı, yeni WebRTC client oluşturuldu")
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
}




