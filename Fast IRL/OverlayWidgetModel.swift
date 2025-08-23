import Foundation
import SwiftUI
import WebKit

final class OverlayWidgetModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var frame: CGRect
    @Published var urlString: String
    @Published var title: String
    let webView: WKWebView

    init(frame: CGRect, urlString: String, title: String = "") {
        self.frame = frame
        self.urlString = urlString
        
        // WebView configuration with audio permissions
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Set title after webView is initialized
        self.title = title.isEmpty ? Self.extractTitleFromURL(urlString) : title
        
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
    }
    
    private static func extractTitleFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "Widget" }
        
        // Extract domain name as title
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        
        return "Widget"
    }
}

final class OverlayManager: ObservableObject {
    @Published var widgets: [OverlayWidgetModel] = []
    @Published var isEditMode: Bool = false
    @Published var isManualFocus: Bool = false
    @Published var focusedWidgetId: UUID? = nil

    func addWidget(urlString: String, frame: CGRect, title: String = "") {
        let w = OverlayWidgetModel(frame: frame, urlString: urlString, title: title)
        widgets.append(w)
        saveWidgets()
    }

    func removeWidget(id: UUID) {
        widgets.removeAll { $0.id == id }
        saveWidgets()
    }
    
    func updateWidgetFrame(id: UUID, frame: CGRect) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].frame = frame
            saveWidgets()
        }
    }
    
    func setManualFocus(widgetId: UUID) {
        isManualFocus = true
        focusedWidgetId = widgetId
    }
    
    func enableAutoFocus() {
        isManualFocus = false
        focusedWidgetId = nil
    }
    
    // MARK: - Persistence
    private let userDefaults = UserDefaults.standard
    private let widgetsKey = "savedWidgets"
    
    init() {
        loadWidgets()
    }
    
    private func saveWidgets() {
        let widgetData = widgets.map { widget in
            [
                "urlString": widget.urlString,
                "title": widget.title,
                "frame": [
                    "x": widget.frame.origin.x,
                    "y": widget.frame.origin.y,
                    "width": widget.frame.size.width,
                    "height": widget.frame.size.height
                ]
            ]
        }
        userDefaults.set(widgetData, forKey: widgetsKey)
    }
    
    private func loadWidgets() {
        guard let widgetData = userDefaults.array(forKey: widgetsKey) as? [[String: Any]] else { return }
        
        for data in widgetData {
            guard let urlString = data["urlString"] as? String,
                  let title = data["title"] as? String,
                  let frameData = data["frame"] as? [String: CGFloat] else { continue }
            
            let frame = CGRect(
                x: frameData["x"] ?? 100,
                y: frameData["y"] ?? 100,
                width: frameData["width"] ?? 200,
                height: frameData["height"] ?? 150
            )
            
            let widget = OverlayWidgetModel(frame: frame, urlString: urlString, title: title)
            widgets.append(widget)
        }
    }
}


