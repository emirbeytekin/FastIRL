import Foundation
import WebRTC
import AVFoundation

final class ABRManager {
    private weak var client: WebRTCClient?
    private var timer: Timer?
    private var lastBytesSent: UInt64 = 0
    private var lastTs: CFTimeInterval = CACurrentMediaTime()

    var enabled = true
    var thermalProtectEnabled = true
    var targetMaxKbps: Int = 8000
    var minKbps: Int = 800
    var stepDownFactor: Double = 0.8
    var stepUpFactor: Double = 1.15

    // UI senkronizasyonu için geri bildirimler
    var onAdaptQuality: ((Int32, Int32, Int) -> Void)?
    var onBitrateChanged: ((Int) -> Void)?

    private var consecutiveBad = 0
    private var consecutiveGood = 0

    init(client: WebRTCClient) {
        self.client = client
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    @objc private func thermalChanged() {
        guard thermalProtectEnabled else { return }
        let state = ProcessInfo.processInfo.thermalState
        guard let client else { return }
        switch state {
        case .nominal, .fair:
            break
        case .serious:
            let kbps = max(minKbps, Int(Double(targetMaxKbps) * 0.5))
            client.setVideoMaxBitrate(kbps: kbps)
            onBitrateChanged?(kbps)
            client.adaptOutputFormat(width: 1280, height: 720, fps: 30)
            onAdaptQuality?(1280, 720, 30)
        case .critical:
            client.setVideoMaxBitrate(kbps: minKbps)
            onBitrateChanged?(minKbps)
            client.adaptOutputFormat(width: 960, height: 540, fps: 24)
            onAdaptQuality?(960, 540, 24)
        @unknown default:
            break
        }
    }

    private func tick() {
        guard enabled, let client else { return }
        client.getStats { [weak self] report in
            guard let self else { return }
            var bytesSent: UInt64 = 0
            var fractionLost: Double = 0
            var rttMs: Double = 0
            var foundVideoOutbound = false

            for (_, stat) in report.statistics {
                if stat.type == "outbound-rtp" {
                    let mediaTypeStr: String? = (stat.values["mediaType"] as? String) ?? (stat.values["mediaType"] as? NSNumber)?.stringValue
                    if mediaTypeStr == "video" {
                        foundVideoOutbound = true
                        if let bStr = stat.values["bytesSent"] as? String, let u = UInt64(bStr) {
                            bytesSent = u
                        } else if let bNum = stat.values["bytesSent"] as? NSNumber {
                            bytesSent = bNum.uint64Value
                        }

                        if let flStr = stat.values["fractionLost"] as? String, let d = Double(flStr) {
                            fractionLost = d
                        } else if let flNum = stat.values["fractionLost"] as? NSNumber {
                            fractionLost = flNum.doubleValue
                        }

                        if let rStr = stat.values["roundTripTime"] as? String, let d = Double(rStr) {
                            rttMs = d * 1000.0
                        } else if let rNum = stat.values["roundTripTime"] as? NSNumber {
                            rttMs = rNum.doubleValue * 1000.0
                        }
                    }
                }
            }

            // WebRTC outbound video akışı yoksa (bağlı değil ya da henüz track eklenmemiş), uyarlamayı atla
            if !foundVideoOutbound { return }

            let now = CACurrentMediaTime()
            let dt = now - self.lastTs
            self.lastTs = now
            let deltaBytes = bytesSent > self.lastBytesSent ? (bytesSent - self.lastBytesSent) : 0
            self.lastBytesSent = bytesSent
            let kbps = dt > 0 ? Int( Double(deltaBytes) * 8.0 / dt / 1000.0 ) : 0

            let badNetwork = fractionLost > 0.02 || rttMs > 250 || kbps < Int(Double(self.targetMaxKbps) * 0.7)
            if badNetwork { self.consecutiveBad += 1; self.consecutiveGood = 0 } else { self.consecutiveGood += 1; self.consecutiveBad = 0 }

            if self.consecutiveBad >= 3 {
                let newMax = max(self.minKbps, Int(Double(self.targetMaxKbps) * self.stepDownFactor))
                self.targetMaxKbps = newMax
                client.setVideoMaxBitrate(kbps: newMax)
                self.onBitrateChanged?(newMax)
                client.adaptOutputFormat(width: 1280, height: 720, fps: 30)
                self.onAdaptQuality?(1280, 720, 30)
                self.consecutiveBad = 0
            } else if self.consecutiveGood >= 4 {
                let newMax = min(8_000, Int(Double(self.targetMaxKbps) * self.stepUpFactor))
                self.targetMaxKbps = newMax
                client.setVideoMaxBitrate(kbps: newMax)
                self.onBitrateChanged?(newMax)
                self.consecutiveGood = 0
            }
        }
    }
}


