import Foundation
import SwiftUI
import WebKit

final class OverlayWidgetModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var frame: CGRect
    @Published var urlString: String
    let webView: WKWebView

    init(frame: CGRect, urlString: String) {
        self.frame = frame
        self.urlString = urlString
        self.webView = WKWebView(frame: .zero, configuration: .init())
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
    }
}

final class OverlayManager: ObservableObject {
    @Published var widgets: [OverlayWidgetModel] = []
    @Published var videoOverlays: [SecondaryCameraOverlayModel] = []

    func addWidget(urlString: String, frame: CGRect) {
        let w = OverlayWidgetModel(frame: frame, urlString: urlString)
        widgets.append(w)
    }

    func removeWidget(id: UUID) {
        widgets.removeAll { $0.id == id }
    }

    func addVideoOverlay(_ overlay: SecondaryCameraOverlayModel) {
        videoOverlays.append(overlay)
    }
    func removeVideoOverlay(id: UUID) { videoOverlays.removeAll { $0.id == id } }
}


