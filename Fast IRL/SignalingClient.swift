import Foundation
import WebRTC

protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didReceiveOffer offer: RTCSessionDescription)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer answer: RTCSessionDescription)
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate)
    func signalingClientDidConnect(_ client: SignalingClient)
    func signalingClientDidDisconnect(_ client: SignalingClient)
}

final class SignalingClient: NSObject {
    weak var delegate: SignalingClientDelegate?
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    @Published var isConnected = false
    
    override init() {
        super.init()
        self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    func connect(to url: URL) {
        print("🔗 WebSocket bağlantısı başlatılıyor: \(url)")
        
        // WebSocket URL'ini doğru formatta oluştur
        var components = URLComponents()
        components.scheme = "ws"
        components.host = url.host ?? "localhost"
        components.port = url.port ?? 8080
        components.path = "/"
        
        guard let wsURL = components.url else {
            print("❌ WebSocket URL oluşturulamadı")
            return
        }
        
        print("🔗 WebSocket URL: \(wsURL)")
        
        webSocket?.cancel()
        webSocket = urlSession?.webSocketTask(with: wsURL)
        webSocket?.resume()
        
        startReceiving()
    }
    
    func disconnect() {
        print("❌ WebSocket bağlantısı kesiliyor")
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        
        // Delegate'e disconnect bildirimi gönder
        DispatchQueue.main.async {
            self.delegate?.signalingClientDidDisconnect(self)
        }
    }
    
    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("📨 WebSocket string mesajı: \(text)")
                    self?.handleMessage(text)
                case .data(let data):
                    print("📨 WebSocket data mesajı: \(data.count) bytes")
                    if let text = String(data: data, encoding: .utf8) {
                        print("📨 Data → String: \(text)")
                        self?.handleMessage(text)
                    } else {
                        print("❌ Data'yı string'e çeviremedik")
                    }
                @unknown default:
                    print("❌ Bilinmeyen WebSocket mesaj türü")
                    break
                }
                self?.startReceiving() // Continue receiving
                
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.delegate?.signalingClientDidDisconnect(self!)
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        print("📨 WebSocket mesajı alındı: \(text)")
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("❌ Invalid message format")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case "welcome":
                self.isConnected = true
                print("✅ WebSocket bağlandı")
                self.delegate?.signalingClientDidConnect(self)
                
            case "offer":
                if let offerDict = json["offer"] as? [String: Any],
                   let sdp = offerDict["sdp"] as? String,
                   let type = offerDict["type"] as? String,
                   type == "offer" {
                    let offer = RTCSessionDescription(type: .offer, sdp: sdp)
                    self.delegate?.signalingClient(self, didReceiveOffer: offer)
                }
                
            case "answer":
                if let answerDict = json["answer"] as? [String: Any],
                   let sdp = answerDict["sdp"] as? String,
                   let type = answerDict["type"] as? String,
                   type == "answer" {
                    let answer = RTCSessionDescription(type: .answer, sdp: sdp)
                    self.delegate?.signalingClient(self, didReceiveAnswer: answer)
                }
                
            case "ice-candidate":
                if let candidateDict = json["candidate"] as? [String: Any],
                   let candidate = candidateDict["candidate"] as? String,
                   let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
                   let sdpMid = candidateDict["sdpMid"] as? String {
                    let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                    self.delegate?.signalingClient(self, didReceiveCandidate: iceCandidate)
                }
                
            default:
                print("⚠️ Unknown message type: \(type)")
            }
        }
    }
    
    func sendOffer(_ offer: RTCSessionDescription) {
        let message: [String: Any] = [
            "type": "offer",
            "offer": [
                "type": "offer",
                "sdp": offer.sdp
            ]
        ]
        sendMessage(message)
    }
    
    func sendAnswer(_ answer: RTCSessionDescription) {
        let message: [String: Any] = [
            "type": "answer",
            "answer": [
                "type": "answer",
                "sdp": answer.sdp
            ]
        ]
        sendMessage(message)
    }
    
    func sendIceCandidate(_ candidate: RTCIceCandidate) {
        let message: [String: Any] = [
            "type": "ice-candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid ?? ""
            ]
        ]
        sendMessage(message)
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            print("❌ Failed to encode message")
            return
        }
        
        print("📤 WebSocket mesajı gönderiliyor: \(text)")
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("❌ WebSocket send error: \(error)")
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket bağlantısı açıldı")
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("❌ WebSocket bağlantısı kapandı: \(closeCode)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.delegate?.signalingClientDidDisconnect(self)
        }
    }
}
