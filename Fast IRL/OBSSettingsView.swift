//
//  OBSSettingsView.swift
//  FastIRL
//
//  Created by Emir Beytekin
//

import SwiftUI

struct OBSSettingsView: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var obsWebSocketURL = ""
    @State private var obsPassword = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OBS WebSocket Ayarları")) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        TextField("WebSocket URL", text: $obsWebSocketURL)
                            .textContentType(.none)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.orange)
                        SecureField("Şifre (Opsiyonel)", text: $obsPassword)
                    }
                }
                
                Section(header: Text("Kullanım")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📋 Kurulum:")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("1. OBS'de Tools → WebSocket Server Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("2. Enable WebSocket server ✅")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("3. Port: 4455 (varsayılan)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("4. Enable Authentication ✅ (opsiyonel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button("Bağlantıyı Test Et") {
                        testConnection()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
                    
                    Button("Ayarları Kaydet") {
                        saveSettings()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                }
            }
            .navigationTitle("OBS Ayarları")
            .navigationBarItems(
                leading: Button("İptal") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                loadCurrentSettings()
            }
            .alert("OBS Bağlantısı", isPresented: $showingAlert) {
                Button("Tamam") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Ayarları Yükle
    
    private func loadCurrentSettings() {
        obsWebSocketURL = obsManager.obsWebSocketURL
        obsPassword = obsManager.obsPassword
    }
    
    // MARK: - Bağlantı Testi
    
    private func testConnection() {
        // Geçici olarak ayarları uygula
        obsManager.obsWebSocketURL = obsWebSocketURL
        obsManager.obsPassword = obsPassword
        
        // Bağlantıyı test et
        obsManager.connectToOBS()
        
        // 3 saniye sonra sonucu kontrol et
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.obsManager.isConnected {
                self.alertMessage = "✅ OBS'e başarıyla bağlandı!"
            } else {
                self.alertMessage = "❌ OBS'e bağlanılamadı. Ayarları kontrol edin."
            }
            self.showingAlert = true
        }
    }
    
    // MARK: - Ayarları Kaydet
    
    private func saveSettings() {
        // URL'yi doğrula
        guard !obsWebSocketURL.isEmpty else {
            alertMessage = "❌ WebSocket URL boş olamaz"
            showingAlert = true
            return
        }
        
        // Ayarları kaydet
        obsManager.obsWebSocketURL = obsWebSocketURL
        obsManager.obsPassword = obsPassword
        obsManager.saveSettings()
        
        alertMessage = "✅ Ayarlar kaydedildi!"
        showingAlert = true
        
        // 1 saniye sonra kapat
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    OBSSettingsView(obsManager: OBSWebSocketManager())
}