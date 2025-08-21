import SwiftUI
import WebRTC
import WebKit

struct RTCVideoViewRepresentable: UIViewRepresentable {
    class Wrapped: UIView {
        let v = RTCMTLVideoView()
        var onPinch: ((CGFloat) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            v.videoContentMode = .scaleAspectFill
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor),
                v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor),
                v.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinch)
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            defer { g.scale = 1.0 }
            onPinch?(g.scale)
        }
    }

    var track: RTCVideoTrack?
    var onPinch: (CGFloat) -> Void

    func makeUIView(context: Context) -> Wrapped { Wrapped() }
    func updateUIView(_ ui: Wrapped, context: Context) {
        ui.onPinch = onPinch
        if let t = track {
            t.remove(ui.v)
            t.add(ui.v)
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

struct DraggableResizableWidget: View {
    @ObservedObject var model: OverlayWidgetModel
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var scaleState: CGFloat = 1.0
    @State private var resizing: Bool = false

    var body: some View {
        WebViewRepresentable(webView: model.webView)
            .frame(width: max(80, model.frame.width * scaleState), height: max(60, model.frame.height * scaleState))
            .background(Color.black.opacity(0.2))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 1)
                    // Resize handles at corners
                    ForEach(ResizeHandle.allCases, id: \.self) { handle in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .position(positionForHandle(handle, in: model.frame.size, scale: scaleState))
                            .gesture(DragGesture().onChanged { value in
                                resizing = true
                                applyResize(from: handle, translation: value.translation)
                            }.onEnded { _ in resizing = false })
                    }
                }
            )
            .position(x: model.frame.midX + dragOffset.width, y: model.frame.midY + dragOffset.height)
            .gesture(DragGesture().updating($dragOffset) { v, s, _ in s = v.translation }
                        .onEnded { v in model.frame.origin.x += v.translation.width; model.frame.origin.y += v.translation.height })
    }

    enum ResizeHandle: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private func positionForHandle(_ h: ResizeHandle, in size: CGSize, scale: CGFloat) -> CGPoint {
        let w = max(80, size.width * scale)
        let hgt = max(60, size.height * scale)
        switch h {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: w, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: hgt)
        case .bottomRight: return CGPoint(x: w, y: hgt)
        }
    }
    private func applyResize(from handle: ResizeHandle, translation: CGSize) {
        var newFrame = model.frame
        switch handle {
        case .topLeft:
            newFrame.origin.x += translation.width
            newFrame.origin.y += translation.height
            newFrame.size.width -= translation.width
            newFrame.size.height -= translation.height
        case .topRight:
            newFrame.origin.y += translation.height
            newFrame.size.width += translation.width
            newFrame.size.height -= translation.height
        case .bottomLeft:
            newFrame.origin.x += translation.width
            newFrame.size.width -= translation.width
            newFrame.size.height += translation.height
        case .bottomRight:
            newFrame.size.width += translation.width
            newFrame.size.height += translation.height
        }
        newFrame.size.width = max(80, newFrame.size.width)
        newFrame.size.height = max(60, newFrame.size.height)
        model.frame = newFrame
    }
}

final class SecondaryCameraOverlayModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var frame: CGRect
    var track: RTCVideoTrack
    @Published var lastPixelBuffer: CVPixelBuffer?
    init(frame: CGRect, track: RTCVideoTrack) { self.frame = frame; self.track = track }
}

struct SecondaryCameraView: UIViewRepresentable {
    let track: RTCVideoTrack
    func makeUIView(context: Context) -> RTCMTLVideoView { RTCMTLVideoView() }
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        track.add(uiView)
    }
}

struct DraggableResizableVideoOverlay: View {
    @ObservedObject var model: SecondaryCameraOverlayModel
    @GestureState private var dragOffset: CGSize = .zero
    @State private var resizing: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            SecondaryCameraView(track: model.track)
                .frame(width: max(80, model.frame.width), height: max(60, model.frame.height))
                .background(Color.black.opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 1))
                .position(x: model.frame.midX + dragOffset.width, y: model.frame.midY + dragOffset.height)
                .gesture(DragGesture().updating($dragOffset) { v, s, _ in s = v.translation }
                            .onEnded { v in model.frame.origin.x += v.translation.width; model.frame.origin.y += v.translation.height })

            // Bottom-right resize handle
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .position(x: model.frame.maxX + dragOffset.width, y: model.frame.maxY + dragOffset.height)
                .gesture(DragGesture().onChanged { value in
                    resizing = true
                    var f = model.frame
                    f.size.width = max(80, f.size.width + value.translation.width)
                    f.size.height = max(60, f.size.height + value.translation.height)
                    model.frame = f
                }.onEnded { _ in resizing = false })
        }
    }
}


