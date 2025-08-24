//
//  OBSWebSocketManager.swift
//  FastIRL
//
//  Created by Emir Beytekin
//

import Foundation
import Starscream
import Combine
import CryptoKit
import UIKit

// Op Codes for OBS WebSocket v5
private enum OpCode: Int, Codable {
    case hello = 0
    case identify = 1
    case identified = 2
    case reidentify = 3
    case event = 5
    case request = 6
    case requestResponse = 7
    case requestBatch = 8
    case requestBatchResponse = 9
}

// Authentication structures
private struct Hello: Decodable {
    struct Authentication: Decodable {
        let challenge: String
        let salt: String
    }
    let authentication: Authentication?
}

private struct Identify: Codable {
    let rpcVersion: Int
    let authentication: String?
}

private struct Identified: Codable {
    let negotiatedRpcVersion: Int
}

// MARK: - OBS Models

struct ObsSceneInput: Codable, Identifiable {
    let id = UUID()
    let name: String
    var muted: Bool?
}

struct GetSceneListResponse: Decodable {
    let currentProgramSceneName: String
    let scenes: [GetSceneListResponseScene]
}

struct GetSceneListResponseScene: Decodable {
    let sceneName: String
}

struct GetInputListResponse: Decodable {
    let inputs: [GetInputListResponseInput]
}

struct GetInputListResponseInput: Decodable {
    let inputName: String
}

struct GetInputMuteResponse: Decodable {
    let inputMuted: Bool
}

struct GetStreamingStatusResponse: Decodable {
    let outputActive: Bool
    let outputTimecode: String?
    let outputDuration: Int?
    let outputBytes: Int?
    let outputSkippedFrames: Int?
    let outputTotalFrames: Int?
}

struct GetRecordingStatusResponse: Decodable {
    let outputActive: Bool
    let outputTimecode: String?
    let outputDuration: Int?
    let outputBytes: Int?
    let outputSkippedFrames: Int?
    let outputTotalFrames: Int?
}

struct GetSceneItemListResponse: Decodable {
    let sceneItems: [GetSceneItemListResponseItem]
}

struct GetSceneItemListResponseItem: Decodable {
    let sourceName: String
    let sceneItemEnabled: Bool
}

struct GetSpecialInputsResponse: Decodable {
    let desktop1: String?
    let desktop2: String?
    let mic1: String?
    let mic2: String?
    let mic3: String?
    let mic4: String?

    func mics() -> [String] {
        return [mic1, mic2, mic3, mic4].compactMap { $0 }
    }
}

class OBSWebSocketManager: ObservableObject {
    private var webSocket: WebSocket?
    private var cancellables = Set<AnyCancellable>()
    private var nextRequestId: Int = 0
    private var pendingRequests: [String: (Data?) -> Void] = [:]
    private var streamingStatusTimer: Timer?
    
    // OBS Bağlantı Durumu
    @Published var isConnected = false
    @Published var connectionStatus = "Bağlı Değil"
    @Published var isAuthenticated = false
    
    // OBS Sahne ve Ses Kaynakları
    @Published var scenes: [String] = []
    @Published var currentScene: String = ""
    @Published var audioSources: [ObsSceneInput] = []
    
    // OBS Durum Bilgileri
    @Published var isStreaming = false
    @Published var isRecording = false
    @Published var streamTime = ""
    @Published var recordTime = ""
    @Published var streamDuration: String = "00:00:00"
    @Published var streamBytes: Int = 0
    
    // OBS Ayarları
    var obsWebSocketURL: String = "ws://localhost:4455"
    var obsPassword: String = ""
    
    // Auto-reconnect properties
    @Published var isAttemptingConnection = false
    @Published var reconnectCount = 0
    @Published var reconnectCountdown = 0
    private var reconnectTimer: Timer?
    private var countdownTimer: Timer?
    private let maxReconnectAttempts = 10
    
    init() {
        loadSettings()
        tryAutoConnect()
    }
    
    // MARK: - Auto Connect
    
    private func tryAutoConnect() {
        // OBS ayarları varsa otomatik bağlanmaya çalış
        if !obsWebSocketURL.isEmpty && obsWebSocketURL != "ws://localhost:4455" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.connectToOBS()
            }
        }
    }
    
    // MARK: - OBS Bağlantısı
    
    func connectToOBS() {
        guard !obsWebSocketURL.isEmpty else {
            connectionStatus = "WebSocket URL gerekli"
            return
        }
        
        let url = URL(string: obsWebSocketURL)!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        webSocket = WebSocket(request: request)
        webSocket?.delegate = self
        webSocket?.connect()
        
        connectionStatus = "Bağlanıyor..."
    }
    
    func disconnectFromOBS() {
        stopReconnectTimer()
        webSocket?.disconnect()
        connectionStatus = "Bağlantı kesildi"
        isConnected = false
        isAuthenticated = false
    }
    
    // MARK: - Auto Reconnect
    
    private func startReconnectTimer() {
        guard reconnectCount < maxReconnectAttempts else {
            connectionStatus = "Bağlantı başarısız (10 deneme)"
            isAttemptingConnection = false
            return
        }
        
        isAttemptingConnection = true
        reconnectCount += 1
        reconnectCountdown = 5
        
        connectionStatus = "OBS Bağlanmaya Çalışıyor"
        
        // Countdown timer
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if self.reconnectCountdown > 0 {
                    self.reconnectCountdown -= 1
                } else {
                    timer.invalidate()
                    self.connectToOBS()
                }
            }
        }
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        countdownTimer?.invalidate()
        reconnectTimer = nil
        countdownTimer = nil
        isAttemptingConnection = false
        reconnectCount = 0
        reconnectCountdown = 0
    }
    
    private func onConnectionLost() {
        if !isAttemptingConnection {
            startReconnectTimer()
        }
    }
    
    private func onConnectionSuccess() {
        stopReconnectTimer()
        connectionStatus = "Bağlandı"
    }
    
    // MARK: - Yayın Kontrolü
    
    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    func startStreaming() {
        sendRequest(type: "StartStream") { data in
            print("🎥 Stream başlatıldı")
        }
    }
    
    func stopStreaming() {
        sendRequest(type: "StopStream") { data in
            print("⏹️ Stream durduruldu")
        }
    }
    
    // MARK: - Kayıt Kontrolü
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        sendRequest(type: "StartRecord") { data in
            print("🔴 Kayıt başlatıldı")
        }
    }
    
    func stopRecording() {
        sendRequest(type: "StopRecord") { data in
            print("⏹️ Kayıt durduruldu")
        }
    }
    
    // MARK: - Sahne Kontrolü
    
    func changeScene(sceneName: String) {
        let requestData = ["sceneName": sceneName]
        sendRequest(type: "SetCurrentProgramScene", requestData: requestData) { [weak self] data in
            print("🎬 Sahne değiştirildi: \(sceneName)")
            
            // Sahne değiştiğinde o sahneye ait ses kaynaklarını al
            DispatchQueue.main.async {
                self?.currentScene = sceneName
                self?.getAudioSourcesForScene(sceneName: sceneName)
                
                // WebRTC reconnect countdown'ı sıfırla
                NotificationCenter.default.post(name: NSNotification.Name("SceneChanged"), object: nil)
            }
        }
    }
    
    func getSceneList() {
        sendRequest(type: "GetSceneList") { [weak self] data in
            guard let self = self, let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(GetSceneListResponse.self, from: data)
                DispatchQueue.main.async {
                    self.scenes = response.scenes.map { $0.sceneName }
                    self.currentScene = response.currentProgramSceneName
                    print("📋 Scene list alındı: \(self.scenes.count) sahne")
                }
            } catch {
                print("❌ Scene list parse hatası: \(error)")
            }
        }
    }
    
    // MARK: - Ses Kaynak Kontrolü
    
    func toggleSourceMute(sourceName: String) {
        let requestData = ["inputName": sourceName]
        sendRequest(type: "ToggleInputMute", requestData: requestData) { data in
            print("🔇 Input mute toggled: \(sourceName)")
        }
    }
    
    // Sahne bazlı ses kaynaklarını al (DualCam implementasyonu)
    func getAudioSourcesForScene(sceneName: String) {
        // 1. Önce tüm input'ları al
        sendRequest(type: "GetInputList") { [weak self] inputListData in
            guard let self = self, let inputListData = inputListData else { return }
            
            do {
                let inputListResponse = try JSONDecoder().decode(GetInputListResponse.self, from: inputListData)
                let inputs = inputListResponse.inputs.map { $0.inputName }
                
                // 2. Özel input'ları al
                self.getSpecialInputs { specialInputs in
                    
                    // 3. Sahne item'larını al
                    self.sendRequest(type: "GetSceneItemList", requestData: ["sceneName": sceneName]) { sceneItemData in
                        guard let sceneItemData = sceneItemData else { return }
                        
                        do {
                            let sceneItemResponse = try JSONDecoder().decode(GetSceneItemListResponse.self, from: sceneItemData)
                            let sceneItems = sceneItemResponse.sceneItems
                            
                            guard !sceneItems.isEmpty else {
                                DispatchQueue.main.async {
                                    self.audioSources = []
                                }
                                return
                            }
                            
                            var obsSceneInputs: [ObsSceneInput] = []
                            
                            // 4. Input'ları filtrele: Mic'lerde VEYA sahne içinde enabled olanlar
                            for input in inputs {
                                if specialInputs.mics().contains(input) {
                                    // Mic input'ları dahil et
                                    obsSceneInputs.append(ObsSceneInput(name: input, muted: nil))
                                    print("🎤 Mic input eklendi: \(input)")
                                } else if let sceneItem = sceneItems.first(where: { $0.sourceName == input }), sceneItem.sceneItemEnabled {
                                    // Sahne içinde enabled olan input'ları dahil et
                                    obsSceneInputs.append(ObsSceneInput(name: input, muted: nil))
                                    print("🎤 Scene input eklendi: \(input)")
                                }
                            }
                            
                            DispatchQueue.main.async {
                                self.audioSources = obsSceneInputs
                                print("🎤 \(sceneName) sahnesi için \(obsSceneInputs.count) ses kaynağı bulundu")
                                
                                // Her ses kaynağının mute durumunu güncelle
                                self.updateAudioSourcesMuteStatus()
                            }
                            
                        } catch {
                            print("❌ Scene item list parse hatası: \(error)")
                            // Fallback olarak tüm ses kaynaklarını al
                            self.getAudioSources()
                        }
                    }
                }
                
            } catch {
                print("❌ Input list parse hatası: \(error)")
                // Fallback olarak tüm ses kaynaklarını al
                self.getAudioSources()
            }
        }
    }
    
    // Tüm ses kaynaklarını al (fallback)
    func getAudioSources() {
        sendRequest(type: "GetInputList") { [weak self] data in
            guard let self = self, let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(GetInputListResponse.self, from: data)
                DispatchQueue.main.async {
                    self.audioSources = response.inputs.map { ObsSceneInput(name: $0.inputName, muted: nil) }
                    print("🎤 Tüm audio sources alındı: \(self.audioSources.count) kaynak")
                    self.updateAudioSourcesMuteStatus()
                }
            } catch {
                print("❌ Audio sources parse hatası: \(error)")
            }
        }
    }
    
    // Özel input'ları al
    private func getSpecialInputs(completion: @escaping (GetSpecialInputsResponse) -> Void) {
        sendRequest(type: "GetSpecialInputs") { data in
            guard let data = data else {
                print("❌ GetSpecialInputs: No data")
                return
            }
            
            do {
                let response = try JSONDecoder().decode(GetSpecialInputsResponse.self, from: data)
                completion(response)
            } catch {
                print("❌ GetSpecialInputs parse hatası: \(error)")
            }
        }
    }
    
    // MARK: - Genel OBS Kontrolü
    
    func getOBSVersion() {
        sendRequest(type: "GetVersion") { data in
            print("📋 OBS version alındı")
        }
    }
    
    func getStats() {
        sendRequest(type: "GetStats") { data in
            print("📊 OBS stats alındı")
        }
    }
    
    // MARK: - Audio Source Management
    
    private func updateAudioSourcesForCurrentScene() {
        // Mevcut sahnedeki ses kaynaklarının mute durumunu güncelle
        updateAudioSourcesMuteStatus()
    }
    
    private func updateAudioSourcesMuteStatus() {
        // Her ses kaynağının mute durumunu güncelle
        for (index, source) in audioSources.enumerated() {
            getInputMute(inputName: source.name) { [weak self] muted in
                DispatchQueue.main.async {
                    if index < self?.audioSources.count ?? 0 {
                        self?.audioSources[index].muted = muted
                    }
                }
            }
        }
    }
    
    func getInputMute(inputName: String, completion: @escaping (Bool?) -> Void) {
        sendRequest(type: "GetInputMute", requestData: ["inputName": inputName]) { data in
            if let data = data,
               let response = try? JSONDecoder().decode(GetInputMuteResponse.self, from: data) {
                completion(response.inputMuted)
            } else {
                completion(nil)
            }
        }
    }
    
    func getStreamingStatus(completion: @escaping (GetStreamingStatusResponse?) -> Void) {
        sendRequest(type: "GetStreamingStatus") { data in
            if let data = data,
               let response = try? JSONDecoder().decode(GetStreamingStatusResponse.self, from: data) {
                completion(response)
            } else {
                completion(nil)
            }
        }
    }
    
    func getRecordingStatus(completion: @escaping (GetRecordingStatusResponse?) -> Void) {
        sendRequest(type: "GetRecordingStatus") { data in
            if let data = data,
               let response = try? JSONDecoder().decode(GetRecordingStatusResponse.self, from: data) {
                completion(response)
            } else {
                completion(nil)
            }
        }
    }
    
    func updateStreamingStatus() {
        getStreamingStatus { [weak self] response in
            DispatchQueue.main.async {
                if let response = response {
                    self?.isStreaming = response.outputActive
                    if response.outputActive {
                        self?.streamDuration = self?.formatDuration(response.outputDuration ?? 0) ?? "00:00:00"
                        self?.streamBytes = response.outputBytes ?? 0
                    } else {
                        self?.streamDuration = "00:00:00"
                        self?.streamBytes = 0
                    }
                }
            }
        }
        
        getRecordingStatus { [weak self] response in
            DispatchQueue.main.async {
                if let response = response {
                    self?.isRecording = response.outputActive
                }
            }
        }
    }
    
    private func formatDuration(_ milliseconds: Int) -> String {
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func startStreamingStatusTimer() {
        streamingStatusTimer?.invalidate()
        streamingStatusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStreamingStatus()
        }
    }
    
    private func stopStreamingStatusTimer() {
        streamingStatusTimer?.invalidate()
        streamingStatusTimer = nil
    }
    
    func setInputMute(inputName: String, muted: Bool, onResponse: @escaping (Bool) -> Void) {
        let requestData: [String: Any] = ["inputName": inputName, "inputMuted": muted]
        sendRequest(type: "SetInputMute", requestData: requestData) { data in
            onResponse(true)
        }
    }
    
    // MARK: - Yardımcı Fonksiyonlar
    
    private func sendRequest(_ request: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: data, encoding: .utf8) else { 
            print("❌ JSON serialization hatası")
            return 
        }
        
        print("📤 OBS'e gönderilen: \(jsonString)")
        webSocket?.write(string: jsonString)
    }
    
    private func sendRequest(type: String, requestData: [String: Any]? = nil, onResponse: ((Data?) -> Void)? = nil) {
        let requestId = getNextRequestId()
        
        if let onResponse = onResponse {
            pendingRequests[requestId] = onResponse
        }
        
        var request: [String: Any] = [
            "requestType": type,
            "requestId": requestId
        ]
        
        if let requestData = requestData {
            request["requestData"] = requestData
        }
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: request)
            let message = packMessage(op: .request, data: requestData)
            webSocket?.write(string: message)
//            print("📤 Request gönderildi: \(type)")
        } catch {
            print("❌ Request gönderme hatası: \(error)")
        }
    }
    
    private func loadSettings() {
        obsWebSocketURL = UserDefaults.standard.string(forKey: "obsWebSocketURL") ?? "ws://localhost:4455"
        obsPassword = UserDefaults.standard.string(forKey: "obsPassword") ?? ""
    }
    
    func saveSettings() {
        UserDefaults.standard.set(obsWebSocketURL, forKey: "obsWebSocketURL")
        UserDefaults.standard.set(obsPassword, forKey: "obsPassword")
    }
    
    // MARK: - Message Packing/Unpacking
    
    private func packMessage(op: OpCode, data: Data) -> String {
        let dataString = String(decoding: data, as: UTF8.self)
        return "{\"op\": \(op.rawValue), \"d\": \(dataString)}"
    }
    
    private func unpackMessage(message: String) throws -> (OpCode?, Data) {
        guard let jsonData = message.data(using: .utf8) else {
            throw NSError(domain: "OBSError", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON decode failed"])
        }
        
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        guard let json = json else {
            throw NSError(domain: "OBSError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not a dictionary"])
        }
        
        guard let opInt = json["op"] as? Int,
              let opCode = OpCode(rawValue: opInt) else {
            throw NSError(domain: "OBSError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid op code"])
        }
        
        guard let dataDict = json["d"] as? [String: Any] else {
            return (opCode, Data())
        }
        
        let data = try JSONSerialization.data(withJSONObject: dataDict)
        return (opCode, data)
    }
    
    private func getNextRequestId() -> String {
        nextRequestId += 1
        return String(nextRequestId)
    }
}

// MARK: - WebSocket Delegate

extension OBSWebSocketManager: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(_):
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionStatus = "Bağlandı"
            }
            authenticateWithOBS()
            
        case .disconnected(_, _):
            DispatchQueue.main.async {
                self.isConnected = false
                self.isAuthenticated = false
                self.connectionStatus = "Bağlantı kesildi"
                
                // Otomatik yeniden bağlantı dene
                self.onConnectionLost()
            }
            
        case .text(let string):
            handleOBSResponse(string)
            
        case .error(let error):
            DispatchQueue.main.async {
                self.connectionStatus = "Hata: \(error?.localizedDescription ?? "Bilinmeyen hata")"
            }
            print("❌ OBS WebSocket hatası: \(error?.localizedDescription ?? "Bilinmeyen hata")")
            
        default:
            break
        }
    }
    
    private func authenticateWithOBS() {
        // OBS WebSocket v5 flow: WebSocket connects -> Hello mesajı gelir -> Identify göndeririz
        // Bu otomatik olarak handleMessage'da yapılacak
        print("🔄 Authentication başlatılıyor...")
    }
    
    private func getInitialData() {
        // İlk önce scene list'i al, sonra current scene'e göre ses kaynaklarını al
        sendRequest(type: "GetSceneList") { [weak self] data in
            guard let self = self, let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(GetSceneListResponse.self, from: data)
                DispatchQueue.main.async {
                    self.scenes = response.scenes.map { $0.sceneName }
                    self.currentScene = response.currentProgramSceneName
                    print("📋 Scene list alındı: \(self.scenes.count) sahne, aktif: \(self.currentScene)")
                    
                    // Şimdi aktif sahnenin ses kaynaklarını al
                    self.getAudioSourcesForScene(sceneName: self.currentScene)
                }
            } catch {
                print("❌ Scene list parse hatası: \(error)")
            }
        }
        
        getOBSVersion()
    }
    
    private func handleOBSResponse(_ response: String) {
//        print("📥 OBS'den gelen: \(response)")
        
        do {
            let (opCode, data) = try unpackMessage(message: response)
            
            switch opCode {
            case .hello:
                try handleHello(data: data)
                
            case .identified:
                try handleIdentified(data: data)
                
            case .requestResponse:
                try handleRequestResponse(data: data)
                
            case .event:
                try handleEvent(data: data)
                
            default:
                print("⚠️ Bilinmeyen OpCode: \(opCode?.rawValue ?? -1)")
            }
            
        } catch {
            print("❌ Message parse hatası: \(error)")
        }
    }
    
    private func handleHello(data: Data) throws {
        print("👋 Hello mesajı alındı")
        let hello = try JSONDecoder().decode(Hello.self, from: data)
        
        var authentication: String?
        if let auth = hello.authentication {
            // Password hash'leme
            let saltedPassword = "\(obsPassword)\(auth.salt)"
            let hash1 = Data(SHA256.hash(data: saltedPassword.data(using: .utf8)!))
            
            let challengeString = "\(hash1.base64EncodedString())\(auth.challenge)"
            let hash2 = Data(SHA256.hash(data: challengeString.data(using: .utf8)!))
            authentication = hash2.base64EncodedString()
        }
        
        sendIdentify(authentication: authentication)
    }
    
    private func handleIdentified(data: Data) throws {
        print("✅ Identified - OBS'e bağlandı!")
        let _ = try JSONDecoder().decode(Identified.self, from: data)
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.isAuthenticated = true
            self.onConnectionSuccess()
        }
        
        // Sahne listesini al
        getSceneList()
        
        // Audio input listesini al
        getAudioSources()
        
        // Streaming durumunu kontrol et
        updateStreamingStatus()
        
        // Periyodik olarak streaming durumunu güncelle
        startStreamingStatusTimer()
    }
    
    private func handleRequestResponse(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = json["requestId"] as? String else {
            print("❌ Request response parse hatası")
            return
        }
        
        // Response'u handle et
        if let callback = pendingRequests[requestId] {
            let responseData = json["responseData"] as? [String: Any]
            let responseDataBytes = responseData != nil ? try JSONSerialization.data(withJSONObject: responseData!) : nil
            callback(responseDataBytes)
            pendingRequests.removeValue(forKey: requestId)
        }
    }
    
    private func handleEvent(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["eventType"] as? String else {
            return
        }
        
//        print("📡 Event: \(eventType)")
        
        // Event handling burada olacak
        let eventData = json["eventData"] as? [String: Any]
        handleEventType(eventType, data: eventData ?? [:])
    }
    
    private func sendIdentify(authentication: String?) {
        let identify = Identify(rpcVersion: 1, authentication: authentication)
        
        do {
            let data = try JSONEncoder().encode(identify)
            let message = packMessage(op: .identify, data: data)
            webSocket?.write(string: message)
            print("📤 Identify gönderildi")
        } catch {
            print("❌ Identify gönderme hatası: \(error)")
        }
    }
    
    private func handleEventType(_ eventType: String, data: [String: Any]) {
        DispatchQueue.main.async {
            switch eventType {
            case "StreamStateChanged":
                if let streaming = data["outputActive"] as? Bool {
                    self.isStreaming = streaming
                }
                
            case "RecordStateChanged":
                if let recording = data["outputActive"] as? Bool {
                    self.isRecording = recording
                }
                
            case "CurrentProgramSceneChanged":
                if let sceneName = data["sceneName"] as? String {
                    self.currentScene = sceneName
                }
                
            case "InputMuteStateChanged":
                // Ses kaynağı mute durumu değişti
                break
                
            case "MediaInputPlaybackStarted":
                if let inputName = data["inputName"] as? String {
                    print("🎬 Media input playback başladı: \(inputName)")
                }
                break
                
            case "MediaInputPlaybackEnded":
                if let inputName = data["inputName"] as? String {
//                    print("⏹️ Media input playback bitti: \(inputName)")
                    // Media input bittiğinde ses kaynaklarını güncelle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.updateAudioSourcesForCurrentScene()
                    }
                }
                break
                
            case "InputVolumeMeters":
                // Ses seviyesi bilgisi geldi
                break
                
            case "InputAudioSyncOffsetChanged":
                // Ses sync offset değişti
                break
                
            default:
                print("⚠️ Bilinmeyen event type: \(eventType)")
            }
        }
    }
    
    // MARK: - Screenshot Methods
    
    func getSourceScreenshot(sceneName: String, completion: @escaping (UIImage?) -> Void) {
        let request: [String: Any] = [
            "sourceName": sceneName,
            "imageFormat": "jpg",
            "imageWidth": 640,
            "imageCompressionQuality": 30
        ]
        
        sendRequest(type: "GetSourceScreenshot", requestData: request) { [weak self] responseData in
            guard let self = self, let data = responseData else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                let response = try JSONDecoder().decode(GetSourceScreenshotResponse.self, from: data)
                let imageData = response.imageData
                
                // Base64 data:image/jpeg;base64, prefix'ini kaldır
                let startIndex = imageData.index(imageData.startIndex, offsetBy: 22)
                let base64String = String(imageData[startIndex...])
                
                if let imageDataDecoded = Data(base64Encoded: base64String),
                   let image = UIImage(data: imageDataDecoded) {
                    DispatchQueue.main.async {
                        completion(image)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                print("❌ Screenshot decode error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - Screenshot Structs

struct GetSourceScreenshot: Codable {
    let sourceName: String
    let imageFormat: String
    let imageWidth: Int
    let imageCompressionQuality: Int
}

struct GetSourceScreenshotResponse: Codable {
    let imageData: String
}


