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
                    .foregroundColor((isSelected && (label == "Mute" || label == "Flash" || label == "HDR" || label == "Night Mode")) ? .white : .secondary)
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

struct StabilizationButton: View {
    let mode: StabilizationMode
    let isSelected: Bool
    let action: () -> Void
    
    private var buttonColor: Color {
        isSelected ? .purple : Color(.systemGray6)
    }
    
    private var icon: String {
        switch mode {
        case .off: return "video.slash"
        case .standard: return "video.badge.checkmark"
        case .cinematic: return "camera.aperture"
        case .cinematicExtended: return "camera.metering.center.weighted"
        case .auto: return "wand.and.stars"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(mode.rawValue)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
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
    @ObservedObject var obsManager: OBSWebSocketManager
    
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
            
            // WebRTC durumu
            HStack(spacing: 4) {
                Image(systemName: vm.isWebRTCConnected ? "video" : "video.slash")
                    .foregroundColor(vm.isWebRTCConnected ? .green : .red)
                    .font(.caption2)
                Text(vm.isWebRTCConnected ? "WebRTC ✅" : "WebRTC ❌")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(vm.isWebRTCConnected ? .green : .red)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
            }
            
            // Publishing durumu
            if vm.isWebRTCConnected {
                HStack(spacing: 4) {
                    Image(systemName: vm.isPublishing ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(vm.isPublishing ? .cyan : .yellow)
                        .font(.caption2)
                    Text(vm.isPublishing ? "Publishing ✅" : "Publishing ⏸️")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(vm.isPublishing ? .cyan : .yellow)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
            }
            
            // WebRTC Reconnecting durumu
            if vm.isWebRTCReconnecting {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("WebRTC Reconnecting \(vm.webRTCReconnectCountdown)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.orange)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
            }
            
            // OBS durumu
            HStack(spacing: 4) {
                Image(systemName: obsManager.isConnected ? "tv" : "tv.slash")
                    .foregroundColor(obsManager.isConnected ? .blue : .gray)
                    .font(.caption2)
                
                if obsManager.isAttemptingConnection {
                    Text("OBS Bağlanıyor \(obsManager.reconnectCountdown)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.orange)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                } else {
                    Text(obsManager.isConnected ? "OBS Connected" : "OBS Offline")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(obsManager.isConnected ? .blue : .gray)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
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
            
            // Yayın süresi (sadece yayın aktifken)
            if vm.isPublishing && vm.isWebRTCConnected {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("Yayın: \(vm.streamDurationFormatted)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
                
                // Toplam yayın boyutu
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive")
                        .foregroundColor(.purple)
                        .font(.caption2)
                    Text("Boyut: \(vm.totalStreamMBFormatted)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.purple)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
                
                // Anlık bitrate
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text("Bitrate: \(String(format: "%.0f", vm.streamBitrateKbps)) kbps")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.green)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                }
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
    @StateObject var obsManager = OBSWebSocketManager()
    @State private var showingOBSControl = false
    @State private var scenesExpanded = false

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

                // Touch to Focus için ekran overlay'i
                if !vm.overlayManager.isEditMode {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            // Dokunulan yerde manuel focus yap
                            vm.setManualFocus(at: location)
                        }
                        .overlay(
                            // Dokunulan yeri gösteren focus indicator
                            vm.focusIndicatorLocation.map { location in
                                ZStack {
                                    // Dış halka
                                    Circle()
                                        .fill(Color.yellow.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                    
                                    // Orta halka
                                    Circle()
                                        .stroke(Color.yellow, lineWidth: 3)
                                        .frame(width: 60, height: 60)
                                    
                                    // İç halka
                                    Circle()
                                        .fill(Color.yellow)
                                        .frame(width: 8, height: 8)
                                }
                                .position(location)
                                .animation(.easeInOut(duration: 0.3), value: location)
                            }
                        )
                }
                
                // Otomatik Focus'a Dön butonu - sabit konumda, sadece manuel focus aktifken görünür
                if !vm.overlayManager.isEditMode && vm.focusIndicatorLocation != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                vm.enableAutoFocus()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "target")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Otomatik Focus'a Dön")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.9))
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                if vm.overlaysShown {
                    ForEach(vm.overlayManager.widgets) { widget in
                        DraggableResizableWidget(model: widget, overlayManager: vm.overlayManager)
                    }
                                    // Video overlays kaldırıldı - sadece web widgets destekleniyor
                }
                
                // Network Stats Overlay - her zaman görünür
                VStack {
                    HStack {
                        NetworkStatsOverlay(client: vm.client, vm: vm, obsManager: obsManager)
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
        .preferredColorScheme(.dark)
        .onAppear {
            OrientationLock.orientationLock = .landscapeRight
            OrientationLock.setLandscapeRight()
        }
        .sheet(isPresented: $showingOBSControl) {
            OBSControlView(obsManager: obsManager)
        }
        .alert("OBS Yayın Başlatılsın mı?", isPresented: $vm.showOBSStartStreamAlert) {
            Button("Evet, OBS'de Yayını Başlat") {
                if obsManager.isConnected {
                    obsManager.startStreaming()
                }
            }
            Button("Hayır, Sadece Video Yayınla", role: .cancel) { }
        } message: {
            Text("Görüntülü iletişim başladı. OBS'de de yayını başlatmak ister misiniz?")
        }
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fast IRL").font(.headline)
            
            WebSocketConnectionView(vm: vm)
            
            VideoQualityView(vm: vm, presets: presets)
            
            BitratePresetsView(vm: vm, bitratePresets: bitratePresets)
            
            CameraControlsView(vm: vm)
            
            OverlayWidgetsView(vm: vm)
            
            OBSControlSection(obsManager: obsManager, showingOBSControl: $showingOBSControl, scenesExpanded: $scenesExpanded, toggleAudioSource: toggleAudioSource)
            
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Separate Views

struct WebSocketConnectionView: View {
    @ObservedObject var vm: CallViewModel
    
    var body: some View {
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
                
                if vm.isPublishing && vm.isWebRTCConnected {
                    Button("Stop") {
                        vm.disconnectWebSocket()
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                } else {
                    Button("Connect") {
                        vm.connectWebSocket()
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
                

            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(8)
    }
}

struct VideoQualityView: View {
    @ObservedObject var vm: CallViewModel
    let presets: [VideoPreset]
    
    var body: some View {
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
                        action: { vm.selectedPreset = preset }
                    )
                }
            }
        }
    }
}

struct CameraControlsView: View {
    @ObservedObject var vm: CallViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kamera Kontrolleri").font(.subheadline).fontWeight(.semibold)
            
            // Ana kamera kontrolleri
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ControlButton(
                    icon: "camera.rotate.fill",
                    label: "Flip Camera",
                    isSelected: false,
                    action: { vm.switchCameraPosition() }
                )
                
                ControlButton(
                    icon: vm.micOn ? "mic.fill" : "mic.slash.fill",
                    label: "Mute",
                    isSelected: !vm.micOn,
                    action: { vm.toggleMic() }
                )
                
                ControlButton(
                    icon: vm.torchOn ? "bolt.fill" : "bolt.fill",
                    label: "Flash",
                    isSelected: vm.torchOn,
                    action: { vm.toggleTorch() }
                )
                
                LensSelectionButton(vm: vm)
                
                
            }
            
            // Lens seçimi
            if vm.currentLens != .wide {
                HStack {
                    Text("Aktif Lens:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(vm.currentLens.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            
            // Stabilization Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Stabilization")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                if vm.supportedStabilizationModes.count > 1 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                        ForEach(vm.supportedStabilizationModes) { mode in
                            StabilizationButton(
                                mode: mode,
                                isSelected: vm.stabilizationMode == mode,
                                action: { vm.setStabilizationMode(mode) }
                            )
                        }
                    }
                } else {
                    Text("Stabilization desteklenmiyor")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}

struct BitratePresetsView: View {
    @ObservedObject var vm: CallViewModel
    let bitratePresets: [BitratePreset]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bitrate Seçimi").font(.subheadline).fontWeight(.semibold)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(bitratePresets) { preset in
                    BitratePresetButton(
                        preset: preset,
                        isSelected: abs(vm.maxBitrateKbps - preset.value) < 1,
                        action: { vm.setMaxBitrate(preset.value) }
                    )
                }
            }
        }
    }
}

struct OverlayWidgetsView: View {
    @ObservedObject var vm: CallViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Overlays", isOn: $vm.overlaysShown)
                
                Spacer()
                
                Button(action: {
                    vm.overlayManager.isEditMode.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: vm.overlayManager.isEditMode ? "pencil.circle.fill" : "pencil.circle")
                        Text("Edit")
                    }
                    .font(.caption)
                    .foregroundColor(vm.overlayManager.isEditMode ? .orange : .blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(spacing: 8) {
                TextField("Widget başlığı (opsiyonel)", text: $vm.newWidgetTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    TextField("https://...", text: $vm.newWidgetURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Add") { vm.addOverlayWidget() }
                }
            }
            
            // Manual focus durumu için auto focus butonu
            if vm.overlayManager.isManualFocus {
                Button(action: {
                    vm.overlayManager.enableAutoFocus()
                }) {
                    HStack {
                        Image(systemName: "scope")
                        Text("Otomatik Focus'a Dön")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(6)
                }
            }
            
            // Eklenen overlay'lerin listesi
            if !vm.overlayManager.widgets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mevcut Overlay'ler:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(vm.overlayManager.widgets, id: \.id) { widget in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(widget.title.isEmpty ? "Başlıksız Widget" : widget.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text(widget.urlString)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Focus butonu (sadece manual focus kapalıyken)
                            if !vm.overlayManager.isManualFocus {
                                Button(action: {
                                    vm.overlayManager.setManualFocus(widgetId: widget.id)
                                }) {
                                    Image(systemName: "target")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Button(action: {
                                vm.removeOverlayWidget(id: widget.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            // Focused widget için farklı arka plan
                            vm.overlayManager.focusedWidgetId == widget.id ? 
                            Color.blue.opacity(0.2) : Color(.systemGray6)
                        )
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}

struct OBSControlSection: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    @Binding var showingOBSControl: Bool
    @Binding var scenesExpanded: Bool
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        if obsManager.isConnected {
            VStack(alignment: .leading, spacing: 8) {
                Text("OBS Remote Control")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                StreamRecordControls(obsManager: obsManager)
                
                CurrentSceneInfo(obsManager: obsManager)
                
                ScenesSection(obsManager: obsManager, scenesExpanded: $scenesExpanded, toggleAudioSource: toggleAudioSource)
                
                Button("Full OBS Control") {
                    showingOBSControl = true
                }
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(6)
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(8)
        } else {
            Button("OBS Ayarları") {
                showingOBSControl = true
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray)
            .cornerRadius(15)
        }
    }
}

struct StreamRecordControls: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: obsManager.toggleStreaming) {
                HStack {
                    Image(systemName: obsManager.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                    Text(obsManager.isStreaming ? "Stop Stream" : "Start Stream")
                }
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(obsManager.isStreaming ? Color.red : Color.green)
                .cornerRadius(6)
            }
            
            Button(action: obsManager.toggleRecording) {
                HStack {
                    Image(systemName: obsManager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    Text(obsManager.isRecording ? "Stop Rec" : "Start Rec")
                }
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(obsManager.isRecording ? Color.red : Color.orange)
                .cornerRadius(6)
            }
        }
    }
}

struct CurrentSceneInfo: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    
    var body: some View {
        if !obsManager.currentScene.isEmpty {
            Text("Current Scene: \(obsManager.currentScene)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ScenesSection: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    @Binding var scenesExpanded: Bool
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        if !obsManager.scenes.isEmpty {
            VStack(spacing: 8) {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scenesExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "tv")
                            .foregroundColor(.blue)
                        Text("Sahneler (\(obsManager.scenes.count))")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: scenesExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.blue)
                            .font(.caption2)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                if scenesExpanded {
                    ScenesList(obsManager: obsManager, toggleAudioSource: toggleAudioSource)
                }
            }
        }
    }
}

struct ScenesList: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(obsManager.scenes, id: \.self) { scene in
                SceneItem(scene: scene, obsManager: obsManager, toggleAudioSource: toggleAudioSource)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct SceneItem: View {
    let scene: String
    @ObservedObject var obsManager: OBSWebSocketManager
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            SceneButton(scene: scene, obsManager: obsManager)
            
            if scene == obsManager.currentScene && !obsManager.audioSources.isEmpty {
                AudioSourcesList(obsManager: obsManager, toggleAudioSource: toggleAudioSource)
            }
        }
    }
}

struct SceneButton: View {
    let scene: String
    @ObservedObject var obsManager: OBSWebSocketManager
    
    var body: some View {
        Button(action: {
            obsManager.changeScene(sceneName: scene)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "tv.circle.fill")
                    .foregroundColor(scene == obsManager.currentScene ? .blue : .secondary)
                    .font(.caption)
                
                Text(scene)
                    .font(.caption)
                    .fontWeight(scene == obsManager.currentScene ? .semibold : .regular)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if scene == obsManager.currentScene {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(scene == obsManager.currentScene ? 
                         Color.blue.opacity(0.1) : 
                         Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(scene == obsManager.currentScene ? 
                           Color.blue.opacity(0.3) : 
                           Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AudioSourcesList: View {
    @ObservedObject var obsManager: OBSWebSocketManager
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            Text("Ses Kaynakları:")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            
            ForEach(obsManager.audioSources) { source in
                AudioSourceButton(source: source, toggleAudioSource: toggleAudioSource)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct AudioSourceButton: View {
    let source: ObsSceneInput
    let toggleAudioSource: (ObsSceneInput) -> Void
    
    var body: some View {
        Button(action: {
            toggleAudioSource(source)
        }) {
            HStack(spacing: 8) {
                Image(systemName: source.muted == true ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill")
                    .foregroundColor(source.muted == true ? .red : .green)
                    .font(.caption)
                
                Text(source.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(source.muted == true ? "Muted" : "Active")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(source.muted == true ? .red : .green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(source.muted == true ? 
                         Color.red.opacity(0.1) : 
                         Color.green.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(source.muted == true ? 
                           Color.red.opacity(0.2) : 
                           Color.green.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 16)
    }
}

// MARK: - Helper Functions

extension MainView {
    func label(_ sys: String) -> some View {
        Image(systemName: sys).foregroundColor(.white).padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
    }
    
    private func toggleAudioSource(_ source: ObsSceneInput) {
        let newMutedState = !(source.muted ?? false)
        obsManager.setInputMute(inputName: source.name, muted: newMutedState) { success in
            if success {
                DispatchQueue.main.async {
                    if let index = obsManager.audioSources.firstIndex(where: { $0.id == source.id }) {
                        obsManager.audioSources[index].muted = newMutedState
                    }
                }
            }
        }
    }
}

struct LensSelectionButton: View {
    @ObservedObject var vm: CallViewModel
    @State private var showLensPicker = false
    
    var body: some View {
        Menu {
            ForEach(LensKind.allCases, id: \.self) { lens in
                Button(action: {
                    vm.setLens(lens)
                }) {
                    HStack {
                        Image(systemName: lensIcon(for: lens))
                        Text(lensDisplayName(for: lens))
                        Spacer()
                        if vm.lens == lens {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "camera.aperture")
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
        .buttonStyle(PlainButtonStyle())
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    private func lensIcon(for lens: LensKind) -> String {
        switch lens {
        case .wide: return "camera.aperture"
        case .ultraWide: return "camera.filters"
        case .tele: return "camera.metering.center"
        }
    }
    
    private func lensDisplayName(for lens: LensKind) -> String {
        switch lens {
        case .wide: return "Normal Lens"
        case .ultraWide: return "Ultra Wide"
        case .tele: return "Tele Lens"
        }
    }
}




