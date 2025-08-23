import Foundation
import AVFoundation
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didGenerate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState)
    func webRTCClient(_ client: WebRTCClient, didUpdateBitrate bitrateKbps: Double)
}

final class WebRTCClient: NSObject, ObservableObject {
    weak var delegate: WebRTCClientDelegate?
    private let factory: RTCPeerConnectionFactory
    private(set) var pc: RTCPeerConnection!
    private(set) var videoSource: RTCVideoSource!
    private(set) var localVideoTrack: RTCVideoTrack!
    private(set) var localAudioTrack: RTCAudioTrack!
    
    // Network statistics
    @Published var uploadSpeedKbps: Double = 0.0
    @Published var downloadSpeedKbps: Double = 0.0
    private var lastBytesSent: UInt64 = 0
    private var lastBytesReceived: UInt64 = 0
    private var lastStatsTime: CFTimeInterval = 0
    private var statsTimer: Timer?

    private let audioSession = RTCAudioSession.sharedInstance()

    override init() {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement":"true"])
        self.pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        self.videoSource = factory.videoSource()
        self.localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        let vsender = pc.add(localVideoTrack, streamIds: ["stream0"])!
        var params = vsender.parameters
        let enc = RTCRtpEncodingParameters()
        enc.isActive = true
        enc.maxBitrateBps = NSNumber(value: 15_000_000)  // 15 Mbps for 1080p60
        params.encodings = [enc]
        vsender.parameters = params

        let aSrc = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        self.localAudioTrack = factory.audioTrack(with: aSrc, trackId: "audio0")
        _ = pc.add(localAudioTrack, streamIds: ["stream0"])!

        audioSession.lockForConfiguration()
        try? audioSession.setCategory(.playAndRecord,
                                      with: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        try? audioSession.setMode(.videoChat)
        try? audioSession.setActive(true)
        audioSession.unlockForConfiguration()
    }

    func makePeerConnectionFactory() -> RTCPeerConnectionFactory { factory }

    func makeVideoSource() -> RTCVideoSource { videoSource }

    func createOffer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio":"false","OfferToReceiveVideo":"false"], optionalConstraints: nil)
        pc.offer(for: constraints) { [weak self] sdp, err in
            guard let self, let sdp = sdp, err == nil else { return }
            self.pc.setLocalDescription(sdp) { _ in completion(sdp.sdp) }
        }
    }
    func setRemoteAnswer(_ sdp: String) {
        let desc = RTCSessionDescription(type: .answer, sdp: sdp)
        pc.setRemoteDescription(desc, completionHandler: { _ in })
    }

    func setMicEnabled(_ on: Bool) { localAudioTrack.isEnabled = on }

    func setVideoMaxBitrate(kbps: Int) {
        guard let sender = pc.senders.first(where: { $0.track?.kind == "video" }) else { return }
        var p = sender.parameters
        if !p.encodings.isEmpty {
            var encodings = p.encodings
            encodings[0].maxBitrateBps = NSNumber(value: max(100_000, kbps * 1000))
            p.encodings = encodings
            sender.parameters = p
        }
    }

    func adaptOutputFormat(width: Int32, height: Int32, fps: Int) {
        videoSource.adaptOutputFormat(toWidth: width, height: height, fps: Int32(fps))
    }

    func getStats(_ completion: @escaping (RTCStatisticsReport) -> Void) {
        pc.statistics(completionHandler: completion)
    }
    
    func startStatsMonitoring() {
        stopStatsMonitoring()
        lastStatsTime = CACurrentMediaTime()
        
        print("📊 Stats monitoring başlatıldı - PC State: \(pc.connectionState.rawValue)")
        
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
    }
    
    func stopStatsMonitoring() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    func close() {
        print("🔌 WebRTC connection kapatılıyor")
        stopStatsMonitoring()
        pc.close()
        
        // Stats'ları sıfırla
        DispatchQueue.main.async {
            self.uploadSpeedKbps = 0
            self.downloadSpeedKbps = 0
        }
    }
    
    private func updateNetworkStats() {
        print("📊 updateNetworkStats called - PC State: \(pc.connectionState.rawValue)")
        
        pc.statistics { [weak self] report in
            guard let self = self else { return }
            
            print("📊 WebRTC Stats Report - Total stats: \(report.statistics.count), PC State: \(self.pc.connectionState.rawValue)")
            
            var bytesSent: UInt64 = 0
            var bytesReceived: UInt64 = 0
            var foundOutbound = false
            var foundInbound = false
            
            for (id, stat) in report.statistics {
                if stat.type == "outbound-rtp" {
                    foundOutbound = true
                    print("📊 Outbound RTP stat found - ID: \(id)")
                    print("📊   Values: \(stat.values)")
                    
                    // Video kontrolünü "kind" ile yapalım (MediaType yerine)
                    if let kind = stat.values["kind"] as? String {
                        print("📊   Kind: \(kind)")
                        if kind == "video",
                           let bytes = stat.values["bytesSent"] as? NSNumber {
                            bytesSent += bytes.uint64Value
                            print("📊 ✅ Video bytes sent: \(bytes.uint64Value)")
                        } else if kind == "audio" {
                            print("📊 ⚠️ Audio stat ignored")
                        }
                    } else {
                        print("📊 ❌ No 'kind' field found")
                    }
                }
                if stat.type == "inbound-rtp" {
                    foundInbound = true
                    print("📊 Inbound RTP stat found - ID: \(id)")
                    print("📊   Values: \(stat.values)")
                    
                    // Video kontrolünü "kind" ile yapalım (MediaType yerine)
                    if let kind = stat.values["kind"] as? String {
                        print("📊   Kind: \(kind)")
                        if kind == "video",
                           let bytes = stat.values["bytesReceived"] as? NSNumber {
                            bytesReceived += bytes.uint64Value
                            print("📊 ✅ Video bytes received: \(bytes.uint64Value)")
                        } else if kind == "audio" {
                            print("📊 ⚠️ Audio stat ignored")
                        }
                    } else {
                        print("📊 ❌ No 'kind' field found")
                    }
                }
                
                // List all stat types to see what we have
                if !["outbound-rtp", "inbound-rtp"].contains(stat.type) {
                    print("📊 Other stat: \(stat.type)")
                }
            }
            
            print("📊 Found - Outbound: \(foundOutbound), Inbound: \(foundInbound)")
            
            let currentTime = CACurrentMediaTime()
            let timeDiff = currentTime - self.lastStatsTime
            
            print("📊 Final - Bytes sent: \(bytesSent), received: \(bytesReceived), timeDiff: \(timeDiff)")
            
            if timeDiff > 0 && self.lastStatsTime > 0 {
                let uploadDiff = bytesSent - self.lastBytesSent
                let downloadDiff = bytesReceived - self.lastBytesReceived
                
                let uploadSpeedCalculated = Double(uploadDiff * 8) / (timeDiff * 1000)
                let downloadSpeedCalculated = Double(downloadDiff * 8) / (timeDiff * 1000)
                
                print("📊 Speed calculation - Upload: \(uploadSpeedCalculated) kbps, Download: \(downloadSpeedCalculated) kbps")
                
                DispatchQueue.main.async {
                    self.uploadSpeedKbps = uploadSpeedCalculated
                    self.downloadSpeedKbps = downloadSpeedCalculated
                    print("📊 UI updated - Upload: \(self.uploadSpeedKbps), Download: \(self.downloadSpeedKbps)")
                    
                    // Bitrate'i delegate'e gönder
                    self.delegate?.webRTCClient(self, didUpdateBitrate: uploadSpeedCalculated)
                }
            }
            
            self.lastBytesSent = bytesSent
            self.lastBytesReceived = bytesReceived
            self.lastStatsTime = currentTime
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChange: RTCSignalingState) {
        print("📊 Signaling state changed: \(stateChange)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📡 Stream added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📡 Stream removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("📡 Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateDescription: String
        switch newState {
        case .new: stateDescription = "new"
        case .checking: stateDescription = "checking"
        case .connected: stateDescription = "connected"
        case .completed: stateDescription = "completed"
        case .failed: stateDescription = "failed"
        case .disconnected: stateDescription = "disconnected"
        case .closed: stateDescription = "closed"
        case .count: stateDescription = "count"
        @unknown default: stateDescription = "unknown(\(newState.rawValue))"
        }
        
        print("📡 ICE connection state: \(stateDescription)")
        
        if newState == .failed {
            print("❌ ICE bağlantısı başarısız! Network connectivity problemi olabilir.")
        } else if newState == .disconnected {
            print("⚠️ ICE bağlantısı kesildi")
        } else if newState == .connected || newState == .completed {
            print("✅ ICE bağlantısı başarılı")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("📡 ICE gathering state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("📡 ICE candidate generated")
        delegate?.webRTCClient(self, didGenerate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let stateDescription: String
        switch newState {
        case .new: stateDescription = "new"
        case .connecting: stateDescription = "connecting" 
        case .connected: stateDescription = "connected"
        case .disconnected: stateDescription = "disconnected"
        case .failed: stateDescription = "failed"
        case .closed: stateDescription = "closed"
        @unknown default: stateDescription = "unknown(\(newState.rawValue))"
        }
        
        print("📊 WebRTC Connection state: \(stateDescription)")
        
        // Delegate'e bildir
        delegate?.webRTCClient(self, didChangeConnectionState: newState)
        
        if newState == .connected {
            print("✅ WebRTC bağlantısı kuruldu - stats monitoring başlatılıyor")
            DispatchQueue.main.async {
                self.startStatsMonitoring()
            }
        } else if newState == .disconnected {
            print("⚠️ WebRTC bağlantısı kesildi - stats monitoring durduruluyor")
            DispatchQueue.main.async {
                self.stopStatsMonitoring()
            }
        } else if newState == .failed {
            print("❌ WebRTC bağlantısı başarısız oldu - stats monitoring durduruluyor")
            DispatchQueue.main.async {
                self.stopStatsMonitoring()
            }
        } else if newState == .closed {
            print("🔒 WebRTC bağlantısı kapatıldı - stats monitoring durduruluyor")
            DispatchQueue.main.async {
                self.stopStatsMonitoring()
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("📡 ICE candidates removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 Data channel opened")
    }
}


