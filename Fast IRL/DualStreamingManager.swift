import Foundation
import AVFoundation
import HaishinKit
import SRTHaishinKit
import WebRTC
import VideoToolbox
import AudioToolbox

enum StreamingStatus {
    case stopped
    case starting
    case streaming
    case error(String)
}

final class DualStreamingManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var selectedMode: StreamingMode = .webRTC
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var isStreaming = false
    @Published var errorMessage: String?
    
    // MARK: - SRT Settings
    @Published var srtServerURL = "srt://localhost:9001"
    @Published var srtLatency = 120 // milliseconds
    @Published var srtBufferSize = 1024 * 1024 // 1MB
    
    // MARK: - WebRTC Settings (existing)
    @Published var webRTCServerURL = "ws://173.249.21.219:8080"
    @Published var roomId = ""
    
    // MARK: - Video Settings
    @Published var videoWidth: Int32 = 1920
    @Published var videoHeight: Int32 = 1080
    @Published var videoFPS: Int32 = 30
    @Published var videoBitrate: Int32 = 5000 // 5 Mbps
    
    // MARK: - Stream Objects
    private var webRTCClient: WebRTCClient?
    
    // MARK: - SRT Objects
    private var srtConnection: SRTConnection?
    private var srtStream: SRTStream?
    
    // MARK: - Error Handling
    private var lastError: Error?
    private var retryCount = 0
    private let maxRetries = 3
    
    // MARK: - Video Pipeline
    private var videoCaptureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    // MARK: - Video Processing (handled by SRTHaishinKit internally)
    
    override init() {
        super.init()
        setupErrorHandling()
    }
    
    private func setupVideoPipeline() {
        videoCaptureSession = AVCaptureSession()
        videoCaptureSession?.sessionPreset = .high
        
        guard let session = videoCaptureSession else { return }
        
        // Add video input (back camera)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("❌ Failed to setup video input")
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        // Keep default activeFormat and frame durations
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("❌ Failed to setup audio input")
            return
        }
        
        if session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Add video output
        videoOutput = AVCaptureVideoDataOutput()
        // NV12 (BiPlanarFullRange) tercih et
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput?.alwaysDiscardsLateVideoFrames = false
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
        
        if session.canAddOutput(videoOutput!) {
            session.addOutput(videoOutput!)
        }
        // Keep default orientation
        
        // Add audio output
        audioOutput = AVCaptureAudioDataOutput()
        audioOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
        
        if session.canAddOutput(audioOutput!) {
            session.addOutput(audioOutput!)
        }
        
        // Start capture session (background thread)
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        
        print("✅ Video pipeline setup complete")
    }
    
    deinit {
        Task {
            await cleanup()
        }
    }
    
    // MARK: - Public Methods
    func startStreaming() {
        guard !isStreaming else { return }
        
        streamingStatus = .starting
        isStreaming = true
        
        switch selectedMode {
        case .webRTC:
            startWebRTCStream()
        case .srt:
            startSRTStream()
        case .dual:
            startDualStream()
        }
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        stopWebRTCStream()
        stopSRTStream()
        
        streamingStatus = .stopped
        isStreaming = false
    }
    
    func updateVideoSettings(width: Int32, height: Int32, fps: Int32, bitrate: Int32) {
        videoWidth = width
        videoHeight = height
        videoFPS = fps
        videoBitrate = bitrate
        
        print("✅ Video settings updated: \(width)x\(height) @ \(fps)fps, \(bitrate)kbps")
        
        // TODO: Update SRT stream settings when real implementation is added
    }
    
    // MARK: - Private Streaming Methods
    private func startSRTStream() {
        print("🔄 Starting REAL SRT stream to: \(srtServerURL)")
        print("📡 SRT Settings: Latency=\(srtLatency)ms, Buffer=\(srtBufferSize)B")
        print("🎥 Video Codec: H.265 \(videoWidth)x\(videoHeight) @ \(videoFPS)fps, \(videoBitrate)kbps")
        
        guard let url = URL(string: srtServerURL) else {
            let error = "Invalid SRT URL format. Expected: srt://host:port"
            streamingStatus = .error(error)
            errorMessage = error
            print("❌ \(error)")
            return
        }
        
        // Kamera capture'ı başlat (UI donmaması için arka thread)
        setupVideoPipeline()
        
        // SRT bağlantısı ve stream'i oluştur ve bağlan
        srtConnection = SRTConnection()
        guard let srtConnection else { return }
        srtStream = SRTStream(connection: srtConnection)
        guard let srtStream else { return }
        
        streamingStatus = .starting
        errorMessage = nil
        
        Task(priority: .userInitiated) {
            do {
                try await srtConnection.connect(url)
                // Video ayarları (H.264)
                var videoSettings = VideoCodecSettings(
                    videoSize: .init(width: Int(CGFloat(videoWidth)), height: Int(CGFloat(videoHeight))),
                    bitRate: Int(videoBitrate) * 1000,
                    profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
                    scalingMode: .trim,
                    bitRateMode: .average,
                    maxKeyFrameIntervalDuration: Int32(max(2, videoFPS))
                )
                // 30 fps için frame interval ayarı
                videoSettings.frameInterval = VideoCodecSettings.frameInterval30
                videoSettings.isLowLatencyRateControlEnabled = true
                try await srtStream.setVideoSettings(videoSettings)
                await srtStream.publish("")
                await MainActor.run {
                    self.streamingStatus = .streaming
                    self.isStreaming = true
                    self.errorMessage = nil
                    print("✅ SRT connected & publishing (HEVC)")
                }
            } catch {
                await MainActor.run {
                    self.streamingStatus = .error("SRT connect failed: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.isStreaming = false
                    print("❌ SRT connect failed: \(error)")
                }
            }
        }
    }
    
    // SRT bağlantı durumu SRTHaishinKit tarafında yönetiliyor; ayrıca izlemeye gerek yok
    
    private func stopSRTStream() {
        print("🛑 Stopping SRT stream...")
        Task {
            if let srtStream { await srtStream.close() }
            if let srtConnection { await srtConnection.close() }
            await MainActor.run {
                self.streamingStatus = .stopped
                self.isStreaming = false
            }
            print("✅ SRT stream stopped")
        }
    }
    
    private func startWebRTCStream() {
        print("🔄 Starting WebRTC stream...")
        // WebRTC is handled by existing CallViewModel
        // This method is called for dual mode coordination
        print("✅ WebRTC stream coordination started")
    }
    
    private func stopWebRTCStream() {
        print("🛑 Stopping WebRTC stream...")
        // WebRTC is handled by existing CallViewModel
        print("✅ WebRTC stream coordination stopped")
    }
    
    private func startDualStream() {
        print("🔄 Starting Dual stream (WebRTC + SRT)...")
        
        // Start both streams
        startWebRTCStream()
        startSRTStream()
        
        streamingStatus = .streaming
        print("✅ Dual stream started")
    }
    
    // MARK: - Error Handling
    private func setupErrorHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleError), name: AVCaptureSession.runtimeErrorNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleError), name: AVCaptureSession.wasInterruptedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleError), name: AVCaptureSession.interruptionEndedNotification, object: nil)
    }
    
    @objc private func handleError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
        lastError = error
        print("🚫 Error: \(error.localizedDescription)")
        if retryCount < maxRetries {
            retryConnection()
        } else {
            streamingStatus = .error("Max retries reached for connection.")
            isStreaming = false
            errorMessage = error.localizedDescription
        }
    }
    
    private func retryConnection() {
        retryCount += 1
        print("🔄 Retrying connection... (\(retryCount)/\(maxRetries))")
        // TODO: Implement actual retry logic
    }
    
    private func cleanup() async {
        NotificationCenter.default.removeObserver(self)
        
        // Stop video pipeline
        videoCaptureSession?.stopRunning()
        videoCaptureSession = nil
        videoOutput = nil
        audioOutput = nil
        
        // Close SRT connection
        if let stream = srtStream {
            await stream.close()
        }
        if let connection = srtConnection {
            await connection.close()
        }
        srtConnection = nil
        srtStream = nil
        
        // Encoders SRTHaishinKit tarafından yönetiliyor
        
        print("🧹 Cleanup complete.")
    }
}

// MARK: - SRTConnection Delegate
// SRTHaishinKit SRTConnection actor tabanlıdır; ayrı bir delegate gerektirmez

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension DualStreamingManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming else { return }
        
        if output == videoOutput {
            // Process video frame
            processVideoFrame(sampleBuffer)
        } else if output == audioOutput {
            // Process audio frame
            processAudioFrame(sampleBuffer)
        }
    }
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        // Video sample'ı doğrudan SRTStream'e gönder (ek kontrol olmadan)
        if let stream = srtStream {
            Task.detached(priority: .utility) { await stream.append(sampleBuffer) }
        }
    }
    
    private func processAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        // TODO: İleride PCM/AAC olarak AVAudioBuffer'a çevrilip stream.append(buffer) yapılabilir
    }
    // Eski manuel paketleme fonksiyonları kaldırıldı; HaishinKit TSWriter kullanır
}

// MARK: - Video Encoder
class VideoEncoder {
    private var session: VTCompressionSession?
    private var callback: ((Data) -> Void)?
    
    func setup(width: Int, height: Int, fps: Int, bitrate: Int) {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC, // H.265
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("❌ Failed to create video compression session")
            return
        }
        
        self.session = session
        
        // Configure session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate * 1000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps * 2))
        
        // Start session
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        print("✅ Video encoder setup complete: H.265 \(width)x\(height) @ \(fps)fps, \(bitrate)kbps")
    }
    
    func encodeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = session else { return }
        
        var flagsOut: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: CMTime.invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        
        if status != noErr {
            print("❌ Video encoding failed: \(status)")
        }
    }
    
    func setOutputCallback(_ callback: @escaping (Data) -> Void) {
        self.callback = callback
    }
}

// MARK: - Audio Encoder
class AudioEncoder {
    private var converter: AudioConverterRef?
    private var callback: ((Data) -> Void)?
    
    func setup(sampleRate: Int, channels: Int, bitrate: Int) {
        var inputFormat = AudioStreamBasicDescription()
        inputFormat.mSampleRate = Float64(sampleRate)
        inputFormat.mFormatID = kAudioFormatLinearPCM
        inputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        inputFormat.mBytesPerPacket = 4
        inputFormat.mFramesPerPacket = 1
        inputFormat.mBytesPerFrame = 4
        inputFormat.mChannelsPerFrame = UInt32(channels)
        inputFormat.mBitsPerChannel = 32
        
        var outputFormat = AudioStreamBasicDescription()
        outputFormat.mSampleRate = Float64(sampleRate)
        outputFormat.mFormatID = kAudioFormatMPEG4AAC
        outputFormat.mFormatFlags = kAudioFormatFlagIsPacked
        outputFormat.mBytesPerPacket = 0
        outputFormat.mFramesPerPacket = 1024
        outputFormat.mBytesPerFrame = 0
        outputFormat.mChannelsPerFrame = UInt32(channels)
        outputFormat.mBitsPerChannel = 0
        
        let status = AudioConverterNew(&inputFormat, &outputFormat, &converter)
        
        guard status == noErr, let converter = converter else {
            print("❌ Failed to create audio converter")
            return
        }
        
        // Configure converter
        var bitrate = UInt32(bitrate * 1000)
        AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitrate)
        
        print("✅ Audio encoder setup complete: AAC \(sampleRate)Hz, \(channels)ch, \(bitrate/1000)kbps")
    }
    
    func encodeAudio(_ buffer: CMSampleBuffer) {
        // Audio encoding implementation
        // This is a simplified version - in real implementation you'd convert CMSampleBuffer to raw audio data
        // and then encode it using the AudioConverter
    }
    
    func setOutputCallback(_ callback: @escaping (Data) -> Void) {
        self.callback = callback
    }
}
