import SwiftUI
import WebRTC
import WebKit

extension View {
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
}

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
    let isEditMode: Bool
    
    func makeUIView(context: Context) -> WKWebView { 
        // WebView configuration ayarları
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        
        // Mevcut webView'ın configuration'ını güncelle
        webView.configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // WebView'a dokunma olaylarını engelle
        webView.scrollView.isUserInteractionEnabled = false
        
        // Edit modda değilken arkaplanı şeffaf yap
        if !isEditMode {
            webView.isOpaque = false
            webView.backgroundColor = UIColor.clear
            webView.scrollView.backgroundColor = UIColor.clear
        } else {
            webView.isOpaque = true
            webView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            webView.scrollView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        }
        
        return webView 
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Edit mod değiştiğinde arkaplan ayarlarını güncelle
        if !isEditMode {
            uiView.isOpaque = false
            uiView.backgroundColor = UIColor.clear
            uiView.scrollView.backgroundColor = UIColor.clear
        } else {
            uiView.isOpaque = true
            uiView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            uiView.scrollView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        }
    }
}

struct DraggableResizableWidget: View {
    @ObservedObject var model: OverlayWidgetModel
    @ObservedObject var overlayManager: OverlayManager
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var resizing: Bool = false
    @State private var lastScale: CGFloat = 1.0
    
    // Web view için aspect ratio (genelde 16:9)
    private let aspectRatio: CGFloat = 16.0 / 9.0
    
    // Edit mod kontrolü
    private var shouldEnableInteraction: Bool {
        overlayManager.isEditMode
    }

    var body: some View {
        WebViewRepresentable(webView: model.webView, isEditMode: overlayManager.isEditMode)
            .frame(width: max(80, model.frame.width * lastScale * magnifyBy), height: max(60, model.frame.height * lastScale * magnifyBy))
            .background(
                // Edit modda değilken arkaplanı şeffaf yap
                overlayManager.isEditMode ? Color.black.opacity(0.2) : Color.clear
            )
            .overlay(
                ZStack {
                    // Border - edit modunda turuncu, normal'de beyaz
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            overlayManager.isEditMode ? Color.orange.opacity(0.8) : Color.white.opacity(0.7),
                            lineWidth: overlayManager.isEditMode ? 2 : 1
                        )
                    
                    // Widget başlığı - sol üst köşede
                    if !model.title.isEmpty {
                        Text(model.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .position(x: 25, y: 15)
                    }
                    
                    // Refresh butonu - sağ üst köşede (sadece edit modunda görünür)
                    if overlayManager.isEditMode {
                        Button(action: {
                            model.webView.reload()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .position(x: model.frame.width - 15, y: 15)
                    }
                    

                    
                    // Resize handles - sadece edit modunda görünür
                    if overlayManager.isEditMode {
                        ForEach(ResizeHandle.allCases, id: \.self) { handle in
                            Circle()
                                .fill(Color.orange)
                                .stroke(Color.white, lineWidth: 1)
                                .frame(width: 12, height: 12)
                                .position(positionForHandle(handle, in: model.frame.size, scale: lastScale * magnifyBy))
                                .gesture(DragGesture().onChanged { value in
                                    resizing = true
                                    applyResizeWithAspectRatio(from: handle, translation: value.translation)
                                }.onEnded { _ in 
                                    resizing = false
                                    overlayManager.updateWidgetFrame(id: model.id, frame: model.frame)
                                })
                        }
                    }
                }
            )
            .position(x: model.frame.midX + dragOffset.width, y: model.frame.midY + dragOffset.height)
            .scaleEffect(lastScale * magnifyBy)
            .if(overlayManager.isEditMode) { view in
                view.gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .updating($dragOffset) { v, s, _ in
                                if !resizing { s = v.translation }
                            }
                            .onEnded { v in 
                                if !resizing {
                                    model.frame.origin.x += v.translation.width
                                    model.frame.origin.y += v.translation.height
                                    overlayManager.updateWidgetFrame(id: model.id, frame: model.frame)
                                }
                            },
                        MagnificationGesture()
                            .updating($magnifyBy) { currentState, gestureState, transaction in
                                gestureState = currentState
                            }
                            .onEnded { value in
                                lastScale *= value
                                // Minimum ve maximum scale sınırları
                                lastScale = max(0.5, min(lastScale, 3.0))
                                // Frame'i güncelle
                                let newWidth = model.frame.width * lastScale
                                let newHeight = newWidth / aspectRatio
                                model.frame.size = CGSize(width: newWidth, height: newHeight)
                                lastScale = 1.0 // Reset scale factor
                                overlayManager.updateWidgetFrame(id: model.id, frame: model.frame)
                            }
                    )
                )
            } else: { view in
                view.allowsHitTesting(false) // Normal modda overlay'e dokunmayı devre dışı bırak
            }
    }

    enum ResizeHandle: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    
    private func positionForHandle(_ h: ResizeHandle, in size: CGSize, scale: CGFloat) -> CGPoint {
        let w = max(80, size.width * scale)
        let hgt = max(60, size.height * scale)
        let inset: CGFloat = 6 // Kutunun içinde 6px'lik inset
        switch h {
        case .topLeft: return CGPoint(x: inset, y: inset)
        case .topRight: return CGPoint(x: w - inset, y: inset)
        case .bottomLeft: return CGPoint(x: inset, y: hgt - inset)
        case .bottomRight: return CGPoint(x: w - inset, y: hgt - inset)
        }
    }
    
    private func applyResizeWithAspectRatio(from handle: ResizeHandle, translation: CGSize) {
        var newFrame = model.frame
        
        // Ana resize işlemi
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
        
        // Minimum boyutları uygula
        newFrame.size.width = max(80, newFrame.size.width)
        newFrame.size.height = max(60, newFrame.size.height)
        
        // Aspect ratio'yu koru - width'e göre height'i hesapla
        let targetHeight = newFrame.size.width / aspectRatio
        
        // Top handle'lar için origin'i ayarla
        if handle == .topLeft || handle == .topRight {
            let heightDiff = newFrame.size.height - targetHeight
            newFrame.origin.y += heightDiff
        }
        
        newFrame.size.height = targetHeight
        model.frame = newFrame
    }
}

// Video overlay kaldırıldı - sadece web widgets destekleniyor


