//
//  OBSControlView.swift
//  FastIRL
//
//  Created by Emir Beytekin
//

import SwiftUI

struct OBSControlView: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedScene = ""
    @State private var selectedAudioSource = ""
    @State private var sceneSearchText = ""
    @State private var audioSearchText = ""
    @State private var currentScreenshot: UIImage?
    @State private var screenshotTimer: Timer?
    
    init(obsManager: OBSWebSocketManager? = nil) {
        if let manager = obsManager {
            self.obsManager = manager
        } else {
            self.obsManager = OBSWebSocketManager()
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredScenes: [String] {
        if sceneSearchText.isEmpty {
            return obsManager.scenes
        } else {
            return obsManager.scenes.filter { $0.localizedCaseInsensitiveContains(sceneSearchText) }
        }
    }
    
    private var filteredAudioSources: [ObsSceneInput] {
        if audioSearchText.isEmpty {
            return obsManager.audioSources
        } else {
            return obsManager.audioSources.filter { $0.name.localizedCaseInsensitiveContains(audioSearchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "video.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        Text("OBS Kontrol Paneli")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Connection Status
                    connectionStatusView
                    
                    // Connection Form
                    if !obsManager.isConnected {
                        simpleConnectionForm
                    }
                    
                    // Control Buttons
                    if obsManager.isConnected {
                        controlButtonsView
                        
                        // Screenshot Preview
                        screenshotPreviewView
                        
                        // Scenes Section
                        scenesSection
                        
                        // Audio Sources Section
                        audioSourcesSection
                    }
                    
                    Spacer(minLength: 100) // Bottom padding for scroll
                }
                .padding()
            }
            .navigationTitle("OBS Kontrol")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Kapat") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                startScreenshotTimer()
            }
            .onDisappear {
                stopScreenshotTimer()
            }
        }
    }
    
    // MARK: - Connection Status View
    
    private var connectionStatusView: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(obsManager.isConnected ? Color.green : Color.red)
                    .frame(width: 16, height: 16)
                
                Text(obsManager.connectionStatus)
                    .font(.headline)
                    .foregroundColor(obsManager.isConnected ? .green : .red)
            }
            
            if !obsManager.isConnected {
                Button("OBS'e Bağlan") {
                    obsManager.connectToOBS()
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    // MARK: - Simple Connection Form
    
    private var simpleConnectionForm: some View {
        VStack(spacing: 15) {
            Text("OBS WebSocket Bağlantısı")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("WebSocket URL:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("wss://live.beytekin.net/obs-remote-control-relay/remote-controller/emir123", text: Binding(
                    get: { obsManager.obsWebSocketURL },
                    set: { newValue in
                        obsManager.obsWebSocketURL = newValue
                        obsManager.saveSettings()
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                
                Text("Şifre (Opsiyonel):")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                SecureField("Şifre", text: Binding(
                    get: { obsManager.obsPassword },
                    set: { newValue in
                        obsManager.obsPassword = newValue
                        obsManager.saveSettings()
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    // MARK: - Control Buttons View
    
    private var controlButtonsView: some View {
        VStack(spacing: 15) {
            Text("Yayın & Kayıt Kontrolü")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 15) {
                // Yayın Kontrolü
                Button(action: obsManager.toggleStreaming) {
                    VStack(spacing: 8) {
                        Image(systemName: obsManager.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                        Text(obsManager.isStreaming ? "Yayını Durdur" : "Yayını Başlat")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(obsManager.isStreaming ? Color.red : Color.green)
                    .cornerRadius(10)
                }
                
                // Kayıt Kontrolü
                Button(action: obsManager.toggleRecording) {
                    VStack(spacing: 8) {
                        Image(systemName: obsManager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.system(size: 30))
                        Text(obsManager.isRecording ? "Kaydı Durdur" : "Kaydı Başlat")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(obsManager.isRecording ? Color.red : Color.orange)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    // MARK: - Scenes Section
    
    private var scenesSection: some View {
        VStack(spacing: 15) {
            Text("Sahne Kontrolü")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Scene Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Sahne ara...", text: $sceneSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            if filteredScenes.isEmpty {
                Text(sceneSearchText.isEmpty ? "Sahne bulunamadı" : "Arama sonucu bulunamadı")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredScenes, id: \.self) { scene in
                        Button(action: {
                            obsManager.changeScene(sceneName: scene)
                        }) {
                            HStack {
                                Text(scene)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if scene == obsManager.currentScene {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(scene == obsManager.currentScene ? Color.green.opacity(0.2) : Color(.systemGray5))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    // MARK: - Audio Sources Section
    
    private var audioSourcesSection: some View {
        VStack(spacing: 15) {
            Text("Ses Kaynakları")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Audio Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Ses kaynağı ara...", text: $audioSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            if filteredAudioSources.isEmpty {
                Text(audioSearchText.isEmpty ? "Ses kaynağı bulunamadı" : "Arama sonucu bulunamadı")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredAudioSources) { source in
                        Button(action: {
                            toggleAudioSource(source)
                        }) {
                            HStack {
                                Text(source.name)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(systemName: source.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(source.muted == true ? .red : .green)
                            }
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    // MARK: - Helper Functions
    
    private func toggleAudioSource(_ source: ObsSceneInput) {
        let newMutedState = !(source.muted ?? false)
        obsManager.setInputMute(inputName: source.name, muted: newMutedState) { success in
            if success {
                // Update local state
                if let index = obsManager.audioSources.firstIndex(where: { $0.id == source.id }) {
                    obsManager.audioSources[index].muted = newMutedState
                }
            }
        }
    }
    
    // MARK: - Screenshot Preview View
    
    private var screenshotPreviewView: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text("OBS Canlı Görüntü")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Her 2sn")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Screenshot Image
            if let screenshot = currentScreenshot {
                Image(uiImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 150)
                    
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Görüntü yükleniyor...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            }
            
            // Current Scene Info
            if !obsManager.currentScene.isEmpty {
                HStack {
                    Image(systemName: "tv.fill")
                        .foregroundColor(.blue)
                    Text("Aktif Sahne: \(obsManager.currentScene)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(15)
    }
    
    // MARK: - Screenshot Timer Methods
    
    private func startScreenshotTimer() {
        guard obsManager.isConnected else { return }
        
        // İlk screenshot'ı al
        updateScreenshot()
        
        // Timer'ı başlat - her 2 saniyede bir
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateScreenshot()
        }
    }
    
    private func stopScreenshotTimer() {
        screenshotTimer?.invalidate()
        screenshotTimer = nil
    }
    
    private func updateScreenshot() {
        guard obsManager.isConnected, !obsManager.currentScene.isEmpty else { return }
        
        obsManager.getSourceScreenshot(sceneName: obsManager.currentScene) { [self] image in
            currentScreenshot = image
        }
    }
}

// MARK: - Preview

struct OBSControlView_Previews: PreviewProvider {
    static var previews: some View {
        OBSControlView()
    }
}
