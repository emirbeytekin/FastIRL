import Foundation
import AVFoundation
import WebRTC

final class WebRTCClient: NSObject {
    private let factory: RTCPeerConnectionFactory
    private(set) var pc: RTCPeerConnection!
    private(set) var videoSource: RTCVideoSource!
    private(set) var localVideoTrack: RTCVideoTrack!
    private(set) var localAudioTrack: RTCAudioTrack!

    private let audioSession = RTCAudioSession.sharedInstance()

    override init() {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement":"true"])
        self.pc = factory.peerConnection(with: config, constraints: constraints, delegate: nil)

        self.videoSource = factory.videoSource()
        self.localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        let vsender = pc.add(localVideoTrack, streamIds: ["stream0"])!
        var params = vsender.parameters
        let enc = RTCRtpEncodingParameters()
        enc.isActive = true
        enc.maxBitrateBps = NSNumber(value: 4_000_000)
        params.encodings = [enc]
        vsender.parameters = params

        let aSrc = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        self.localAudioTrack = factory.audioTrack(with: aSrc, trackId: "audio0")
        _ = pc.add(localAudioTrack, streamIds: ["stream0"])!

        audioSession.lockForConfiguration()
        try? audioSession.setCategory(.playAndRecord,
                                      with: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        try? audioSession.setMode(.videoChat)
        try? audioSession.setActive(true)
        audioSession.unlockForConfiguration()
    }

    func makePeerConnectionFactory() -> RTCPeerConnectionFactory { factory }

    func makeVideoSource() -> RTCVideoSource { videoSource }

    func createOffer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio":"false","OfferToReceiveVideo":"false"], optionalConstraints: nil)
        pc.offer(for: constraints) { [weak self] sdp, err in
            guard let self, let sdp = sdp, err == nil else { return }
            self.pc.setLocalDescription(sdp) { _ in completion(sdp.sdp) }
        }
    }
    func setRemoteAnswer(_ sdp: String) {
        let desc = RTCSessionDescription(type: .answer, sdp: sdp)
        pc.setRemoteDescription(desc, completionHandler: { _ in })
    }

    func setMicEnabled(_ on: Bool) { localAudioTrack.isEnabled = on }

    func setVideoMaxBitrate(kbps: Int) {
        guard let sender = pc.senders.first(where: { $0.track?.kind == "video" }) else { return }
        var p = sender.parameters
        if !p.encodings.isEmpty {
            var encodings = p.encodings
            encodings[0].maxBitrateBps = NSNumber(value: max(100_000, kbps * 1000))
            p.encodings = encodings
            sender.parameters = p
        }
    }

    func adaptOutputFormat(width: Int32, height: Int32, fps: Int) {
        videoSource.adaptOutputFormat(toWidth: width, height: height, fps: Int32(fps))
    }

    func getStats(_ completion: @escaping (RTCStatisticsReport) -> Void) {
        pc.statistics(completionHandler: completion)
    }
}


