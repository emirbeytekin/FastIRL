import SwiftUI
import WebRTC

struct PresetButton: View {
    let preset: VideoPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(preset.label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text("\(preset.w)×\(preset.h)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .secondary)
                
                Text("\(preset.fps) FPS")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue.opacity(0.8) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct BitratePresetButton: View {
    let preset: BitratePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(preset.label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)

                Text("bitrate")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.orange : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    private var buttonColor: Color {
        if label == "Mute" {
            return isSelected ? .red : Color(.systemGray6)  // Mute edilmişse (kapalıysa) kırmızı, açıksa gri
        } else if label == "Flash" {
            return isSelected ? .orange : Color(.systemGray6)  // Flash açıksa turuncu
        } else {
            return Color(.systemGray6)  // Diğer butonlar gri
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundColor((isSelected && (label == "Mute" || label == "Flash")) ? .white : .primary)

                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundColor((isSelected && (label == "Mute" || label == "Flash")) ? .white : .secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(buttonColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(buttonColor.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NetworkStatsOverlay: View {
    @ObservedObject var client: WebRTCClient
    @ObservedObject var vm: CallViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Socket durumu
            HStack(spacing: 4) {
                Image(systemName: vm.isWebSocketConnected ? "wifi" : "wifi.slash")
                    .foregroundColor(vm.isWebSocketConnected ? .green : .red)
                    .font(.caption2)
                Text(vm.isWebSocketConnected ? "Connected" : "Disconnected")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(vm.isWebSocketConnected ? .green : .red)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
            }
            
            // Çözünürlük ve FPS
            HStack(spacing: 4) {
                Image(systemName: "rectangle.3.offgrid")
                    .foregroundColor(.cyan)
                    .font(.caption2)
                Text("\(vm.selectedPreset.w)×\(vm.selectedPreset.h)@\(vm.currentFps)fps")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
            }
            
            // Sadece socket bağlıysa network stats göster
            if vm.isWebSocketConnected {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("UP: \(String(format: "%.1f", client.uploadSpeedKbps)) kbps")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("DOWN: \(String(format: "%.1f", client.downloadSpeedKbps)) kbps")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
                
                let qualityText = client.uploadSpeedKbps > 2000 ? "Good" : client.uploadSpeedKbps > 1000 ? "Fair" : "Poor"
                let qualityColor: Color = client.uploadSpeedKbps > 2000 ? .green : client.uploadSpeedKbps > 1000 ? .orange : .red
                let qualityIcon = client.uploadSpeedKbps > 2000 ? "🟢" : client.uploadSpeedKbps > 1000 ? "🟠" : "🔴"
                
                HStack(spacing: 4) {
                    Text(qualityIcon)
                        .font(.caption2)
                    Text(qualityText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(qualityColor)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
    }
}

struct MainView: View {
    @StateObject var vm = CallViewModel()

    let presets: [VideoPreset] = [
        VideoPreset(w: 1280, h: 720, fps: 60, label: "720p60"),
        VideoPreset(w: 1920, h: 1080, fps: 30, label: "1080p30"),
        VideoPreset(w: 1920, h: 1080, fps: 60, label: "1080p60"),
        VideoPreset(w: 3840, h: 2160, fps: 30, label: "4K30"),
        VideoPreset(w: 2560, h: 1440, fps: 60, label: "1440p60"),
        VideoPreset(w: 3840, h: 2160, fps: 60, label: "4K60")
    ]
    
    let bitratePresets: [BitratePreset] = [
        BitratePreset(value: 1500, label: "1.5 MB"),
        BitratePreset(value: 2000, label: "2 MB"),
        BitratePreset(value: 3000, label: "3 MB"),
        BitratePreset(value: 5000, label: "5 MB"),
        BitratePreset(value: 8000, label: "8 MB"),
        BitratePreset(value: 10000, label: "10 MB"),
        BitratePreset(value: 15000, label: "15 MB")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RTCVideoViewRepresentable(track: vm.client.localVideoTrack, onPinch: { scale in vm.onPinch(scale: scale) })
                    .ignoresSafeArea()

                if vm.overlaysShown {
                    ForEach(vm.overlayManager.widgets) { widget in
                        DraggableResizableWidget(model: widget)
                    }
                                    // Video overlays kaldırıldı - sadece web widgets destekleniyor
                }
                
                // Network Stats Overlay - her zaman görünür
                VStack {
                    HStack {
                        NetworkStatsOverlay(client: vm.client, vm: vm)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.leading, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.white.opacity(0.1))

            VStack(spacing: 0) {
                HStack {
                    Button(action: { vm.sidePanelCollapsed.toggle() }) {
                        Image(systemName: vm.sidePanelCollapsed ? "sidebar.right" : "sidebar.leading")
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                if !vm.sidePanelCollapsed {
                    ScrollView { controls }
                }
            }
            .frame(width: vm.sidePanelCollapsed ? 44 : 360)
                .background(Color.black.opacity(0.35))
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            OrientationLock.orientationLock = .landscapeRight
            OrientationLock.setLandscapeRight()
        }

    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fast IRL").font(.headline)
            
            // Computed properties for button text and color
            var buttonText: String {
                if vm.isWebSocketConnected {
                    if vm.isWebRTCConnected {
                        if vm.isPublishing {
                            return "🛑 Stop"
                        } else {
                            return "Disconnect"
                        }
                    } else {
                        return "Reconnect"
                    }
                } else {
                    return "Connect"
                }
            }
            
            var buttonColor: Color {
                if vm.isWebSocketConnected {
                    if vm.isWebRTCConnected {
                        if vm.isPublishing {
                            return .red
                        } else {
                            return .red
                        }
                    } else {
                        return .orange
                    }
                } else {
                    return .green
                }
            }
            
            // WebSocket Connection - En Üstte
            VStack(alignment: .leading, spacing: 8) {
                Text("WebRTC Signaling")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: vm.isWebSocketConnected ? "wifi" : "wifi.slash")
                        .foregroundColor(vm.isWebSocketConnected ? .green : .red)
                    Text("WebSocket: \(vm.isWebSocketConnected ? "Connected" : "Disconnected")")
                        .font(.caption)
                        .foregroundColor(vm.isWebSocketConnected ? .green : .red)
                    Spacer()
                }
                

                
                HStack {
                    TextField("ws://192.168.0.219:8080", text: $vm.webSocketURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.caption)
                    Button(buttonText) {
                        if vm.isWebSocketConnected {
                            if vm.isWebRTCConnected {
                                if vm.isPublishing {
                                    vm.stop()
                                } else {
                                    vm.disconnectWebSocket()
                                }
                            } else {
                                // WebRTC bağlantısı kesildi ama WebSocket bağlı - sadece offer gönder
                                vm.sendOffer()
                                
                            }
                        } else {
                            // WebSocket bağlı değil - önce bağlan
                            vm.connectWebSocket()
                        }
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(buttonColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
                
                // Manuel SDP Offer gönderme butonu
                if vm.isWebSocketConnected && !vm.isWebRTCConnected {
                    Button(action: {
                        vm.sendOffer()
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send SDP Offer")
                        }
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                }
                

            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(8)

            // Custom Video Preset Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(presets) { preset in
                        PresetButton(
                            preset: preset,
                            isSelected: vm.selectedPreset.label == preset.label,
                            action: { 
                                vm.selectedPreset = preset
                                if vm.isPublishing {
//                                    vm.stop()
//                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                                        vm.start()
//                                    }
                                }
                            }
                        )
                    }
                }
            }

            // Start butonu kaldırıldı - otomatik başlatılıyor

            // Kamera Kontrolleri
            VStack(alignment: .leading, spacing: 8) {
                Text("Kamera Kontrolleri").font(.subheadline).fontWeight(.semibold)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ControlButton(
                        icon: "camera.rotate.fill",
                        label: "Flip Camera",
                        isSelected: false,
                        action: { vm.switchCameraPosition() }
                    )
                    
                    Menu {
                        ForEach(LensKind.allCases) { lens in
                            Button(lens.rawValue) { 
                                vm.setLens(lens)
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.metering.center.weighted")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("Lens")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.systemGray6).opacity(0.8), lineWidth: 1)
                                )
                        )
                    }
                    
                    ControlButton(
                        icon: vm.micOn ? "mic.fill" : "mic.slash.fill",
                        label: "Mute",
                        isSelected: !vm.micOn,
                        action: { vm.toggleMic() }
                    )
                    
                    ControlButton(
                        icon: vm.torchOn ? "bolt.fill" : "bolt",
                        label: "Flash",
                        isSelected: vm.torchOn,
                        action: { vm.toggleTorch() }
                    )
                }
            }
            
            // Bitrate Presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Bitrate Seçimi").font(.subheadline).fontWeight(.semibold)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(bitratePresets) { preset in
                        BitratePresetButton(
                            preset: preset,
                            isSelected: abs(vm.maxBitrateKbps - preset.value) < 1,
                            action: {
                                vm.setMaxBitrate(preset.value)
                            }
                        )
                    }
                }
            }

            Divider()

            Toggle("Overlays", isOn: $vm.overlaysShown)

            VStack(spacing: 8) {
                TextField("Widget başlığı (opsiyonel)", text: $vm.newWidgetTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    TextField("https://...", text: $vm.newWidgetURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Add") { vm.addOverlayWidget() }
                }
            }
            

            
            // WebSocket UI yukarıya taşındı
            
            // Send Offer butonu kaldırıldı - otomatik gönderiliyor
            


            if !vm.overlayManager.widgets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kayıtlı Widget'lar:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(vm.overlayManager.widgets) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(w.title.isEmpty ? "Widget" : w.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Remove") { vm.removeOverlayWidget(id: w.id) }
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            Text(w.urlString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(6)
                    }
                }
            }



            Spacer(minLength: 0)
        }
        .padding(12)
    }

    func label(_ sys: String) -> some View {
        Image(systemName: sys).foregroundColor(.white).padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
    }
}


