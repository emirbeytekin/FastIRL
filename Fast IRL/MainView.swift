import SwiftUI
import WebRTC

struct MainView: View {
    @StateObject var vm = CallViewModel()

    let presets: [VideoPreset] = [
        VideoPreset(w: 1920, h: 1080, fps: 30, label: "1080p30"),
        VideoPreset(w: 1920, h: 1080, fps: 60, label: "1080p60"),
        VideoPreset(w: 1280, h: 720, fps: 60, label: "720p60")
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
                    ForEach(vm.overlayManager.videoOverlays) { v in
                        DraggableResizableVideoOverlay(model: v)
                    }
                }
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

            Picker("Preset", selection: $vm.selectedPreset) {
                ForEach(presets) { p in Text(p.label).tag(p) }
            }.pickerStyle(.segmented)

            HStack {
                Button(action: { vm.isPublishing ? vm.stop() : vm.start() }) {
                    Text(vm.isPublishing ? "Stop" : "Start").bold().frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(vm.isPublishing ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            Group {
                HStack {
                    Button(action: { vm.switchCameraPosition() }) { label("camera.rotate") }
                    Menu {
                        ForEach(LensKind.allCases) { l in
                            Button(l.rawValue) { vm.setLens(l) }
                        }
                    } label: { label("viewfinder") }
                    Button(action: { vm.toggleTorch() }) { label(vm.torchOn ? "bolt.fill" : "bolt") }
                    Button(action: { vm.toggleMic() }) { label(vm.micOn ? "mic.fill" : "mic.slash") }
                }

                VStack(alignment: .leading) {
                    Text("FPS: \(vm.currentFps)")
                    Slider(value: Binding(get: { Double(vm.currentFps) }, set: { vm.applyFPS(Int($0.rounded())) }), in: 15...60, step: 1)
                }

                VStack(alignment: .leading) {
                    Text("Max Bitrate: \(Int(vm.maxBitrateKbps)) kbps")
                    Slider(value: Binding(get: { vm.maxBitrateKbps }, set: { vm.setMaxBitrate($0) }), in: 500...8000, step: 100)
                }
            }

            Divider()

            Toggle("Overlays", isOn: $vm.overlaysShown)

            HStack {
                TextField("https://...", text: $vm.newWidgetURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") { vm.addOverlayWidget() }
            }

            if !vm.overlayManager.widgets.isEmpty {
                ForEach(vm.overlayManager.widgets) { w in
                    HStack {
                        Text(w.urlString).lineLimit(1)
                        Spacer()
                        Button("Remove") { vm.removeOverlayWidget(id: w.id) }
                    }
                }
            }

            Divider()
            Text("Secondary Camera").font(.subheadline)
            HStack {
                Menu("Add Sec Camera") {
                    Button("Front") { vm.addSecondaryCamera(position: .front) }
                    Button("Back") { vm.addSecondaryCamera(position: .back) }
                }
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    func label(_ sys: String) -> some View {
        Image(systemName: sys).foregroundColor(.white).padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
    }
}


