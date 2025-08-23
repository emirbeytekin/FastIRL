// WebRTC ve WebSocket bağlantı yönetimi
class FastIRLClient {
    constructor() {
        this.ws = null;
        this.pc = null;
        this.localStream = null;
        this.remoteStream = null;
        
        this.localVideo = document.getElementById('localVideo');
        this.remoteVideo = document.getElementById('remoteVideo');
        this.statusEl = document.getElementById('status');
        this.logsEl = document.getElementById('logs');
        
        // Video stats monitoring
        this.statsInterval = null;
        this.lastStats = null;
        
        this.setupPeerConnection();
    }

    log(message) {
        const timestamp = new Date().toLocaleTimeString();
        this.logsEl.textContent += `[${timestamp}] ${message}\n`;
        this.logsEl.scrollTop = this.logsEl.scrollHeight;
        console.log(message);
    }

    startStatsMonitoring() {
        if (this.statsInterval) {
            clearInterval(this.statsInterval);
        }
        
        this.log('📊 Video stats monitoring başlatıldı');
        this.lastStats = {};
        
        this.statsInterval = setInterval(async () => {
            try {
                const stats = await this.pc.getStats();
                this.processVideoStats(stats);
            } catch (error) {
                console.error('Stats alınamadı:', error);
            }
        }, 1000); // Her saniye
    }

    stopStatsMonitoring() {
        if (this.statsInterval) {
            clearInterval(this.statsInterval);
            this.statsInterval = null;
            this.log('📊 Video stats monitoring durduruldu');
        }
    }

    processVideoStats(stats) {
        let inboundVideo = null;
        let candidate = null;
        
        stats.forEach((report) => {
            if (report.type === 'inbound-rtp' && report.mediaType === 'video') {
                inboundVideo = report;
            } else if (report.type === 'candidate-pair' && report.state === 'succeeded') {
                candidate = report;
            }
        });
        
        if (inboundVideo) {
            const now = Date.now();
            const currentStats = {
                timestamp: now,
                bytesReceived: inboundVideo.bytesReceived || 0,
                packetsReceived: inboundVideo.packetsReceived || 0,
                packetsLost: inboundVideo.packetsLost || 0,
                frameWidth: inboundVideo.frameWidth || 0,
                frameHeight: inboundVideo.frameHeight || 0,
                framesDecoded: inboundVideo.framesDecoded || 0,
                framesDropped: inboundVideo.framesDropped || 0,
                framesReceived: inboundVideo.framesReceived || 0
            };
            
            // Önceki stats varsa kbps ve fps hesapla
            if (this.lastStats.timestamp) {
                const timeDiff = (now - this.lastStats.timestamp) / 1000; // saniye
                const bytesDiff = currentStats.bytesReceived - this.lastStats.bytesReceived;
                const framesDiff = currentStats.framesDecoded - this.lastStats.framesDecoded;
                
                const kbps = ((bytesDiff * 8) / timeDiff / 1000).toFixed(1);
                const fps = (framesDiff / timeDiff).toFixed(1);
                const resolution = `${currentStats.frameWidth}x${currentStats.frameHeight}`;
                const packetsLostPercent = currentStats.packetsReceived > 0 ? 
                    ((currentStats.packetsLost / (currentStats.packetsReceived + currentStats.packetsLost)) * 100).toFixed(1) : '0.0';
                
                console.log(`📊 Video Stats: ${kbps} kbps, ${fps} FPS, ${resolution}, Loss: ${packetsLostPercent}%`);
                this.log(`📊 ${kbps} kbps | ${fps} FPS | ${resolution} | Loss: ${packetsLostPercent}%`);
            }
            
            this.lastStats = currentStats;
        }
    }

    updateStatus(status) {
        this.statusEl.textContent = status;
        this.log(`Status: ${status}`);
    }

    setupPeerConnection() {
        // STUN server konfigürasyonu
        const config = {
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
                { urls: 'stun:stun1.l.google.com:19302' }
            ]
        };

        this.pc = new RTCPeerConnection(config);

        // ICE candidate event
        this.pc.onicecandidate = (event) => {
            if (event.candidate) {
                this.log('ICE Candidate oluşturuldu');
                this.sendSignal({
                    type: 'ice-candidate',
                    candidate: event.candidate
                });
            }
        };

        // Remote stream event
        this.pc.ontrack = (event) => {
            this.log('Remote stream alındı');
            this.remoteStream = event.streams[0];
            this.remoteVideo.srcObject = this.remoteStream;
            
            // Video stats monitoring başlat
            this.startStatsMonitoring();
        };

        // Connection state değişiklikleri
        this.pc.onconnectionstatechange = () => {
            this.log(`PeerConnection state: ${this.pc.connectionState}`);
            this.updateStatus(`WebRTC: ${this.pc.connectionState}`);
            
            if (this.pc.connectionState === 'disconnected' || 
                this.pc.connectionState === 'failed' || 
                this.pc.connectionState === 'closed') {
                this.stopStatsMonitoring();
            }
        };
    }

    connect() {
        const url = document.getElementById('signalingUrl').value;
        
        if (this.ws) {
            this.ws.close();
        }

        this.ws = new WebSocket(url);

        this.ws.onopen = () => {
            this.updateStatus('WebSocket bağlandı');
            document.getElementById('offerBtn').disabled = false;
            document.getElementById('answerBtn').disabled = false;
        };

        this.ws.onclose = () => {
            this.updateStatus('WebSocket bağlantısı kapandı');
            document.getElementById('offerBtn').disabled = true;
            document.getElementById('answerBtn').disabled = true;
        };

        this.ws.onerror = (error) => {
            this.log(`WebSocket hatası: ${error}`);
            this.updateStatus('WebSocket bağlantı hatası');
        };

        this.ws.onmessage = async (event) => {
            try {
                console.log('Raw event.data:', event.data, typeof event.data);
                
                // Blob check
                if (event.data instanceof Blob) {
                    this.log('❌ Blob mesajı alındı, text bekleniyor');
                    const text = await event.data.text();
                    console.log('Blob içeriği:', text);
                    const data = JSON.parse(text);
                    await this.handleSignal(data);
                } else if (typeof event.data === 'string') {
                    const data = JSON.parse(event.data);
                    await this.handleSignal(data);
                } else {
                    this.log(`❌ Desteklenmeyen mesaj türü: ${typeof event.data}`);
                }
            } catch (error) {
                this.log(`Mesaj işleme hatası: ${error}`);
                console.error('Parse hatası:', error);
                console.error('Ham data:', event.data);
            }
        };
    }

    disconnect() {
        if (this.ws) {
            this.ws.close();
            this.ws = null;
        }
        this.updateStatus('Bağlantı kesildi');
    }

    sendSignal(data) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(data));
            this.log(`Signal gönderildi: ${data.type}`);
        } else {
            this.log('WebSocket bağlantısı yok!');
        }
    }

    async handleSignal(data) {
        this.log(`Signal alındı: ${data.type}`);

        switch (data.type) {
            case 'offer':
                await this.handleOffer(data.offer);
                break;
            case 'answer':
                await this.handleAnswer(data.answer);
                break;
            case 'ice-candidate':
                await this.handleIceCandidate(data.candidate);
                break;
            case 'welcome':
                this.log('Welcome mesajı alındı');
                break;
            default:
                this.log(`Bilinmeyen signal türü: ${data.type}`);
        }
    }

    async handleOffer(offer) {
        this.log('Offer alındı, answer oluşturuluyor...');
        
        await this.pc.setRemoteDescription(offer);
        const answer = await this.pc.createAnswer();
        await this.pc.setLocalDescription(answer);

        this.sendSignal({
            type: 'answer',
            answer: answer
        });
    }

    async handleAnswer(answer) {
        this.log('Answer alındı');
        await this.pc.setRemoteDescription(answer);
    }

    async handleIceCandidate(candidate) {
        this.log('ICE Candidate alındı');
        await this.pc.addIceCandidate(candidate);
    }

    async startStream() {
        try {
            this.localStream = await navigator.mediaDevices.getUserMedia({
                video: { width: 1280, height: 720 },
                audio: true
            });

            this.localVideo.srcObject = this.localStream;

            // Local stream'i PeerConnection'a ekle
            this.localStream.getTracks().forEach(track => {
                this.pc.addTrack(track, this.localStream);
            });

            this.log('Kamera başlatıldı');
            document.getElementById('startBtn').disabled = true;
            document.getElementById('stopBtn').disabled = false;

        } catch (error) {
            this.log(`Kamera hatası: ${error}`);
            alert('Kamera erişimi başarısız! Tarayıcı izinlerini kontrol edin.');
        }
    }

    stopStream() {
        if (this.localStream) {
            this.localStream.getTracks().forEach(track => track.stop());
            this.localStream = null;
            this.localVideo.srcObject = null;
        }

        this.log('Kamera durduruldu');
        document.getElementById('startBtn').disabled = false;
        document.getElementById('stopBtn').disabled = true;
    }

    async createOffer() {
        if (!this.localStream) {
            alert('Önce kamerayı başlatın!');
            return;
        }

        try {
            const offer = await this.pc.createOffer();
            await this.pc.setLocalDescription(offer);

            this.sendSignal({
                type: 'offer',
                offer: offer
            });

            this.log('Offer oluşturuldu ve gönderildi');
        } catch (error) {
            this.log(`Offer hatası: ${error}`);
        }
    }

    async createAnswer() {
        try {
            const answer = await this.pc.createAnswer();
            await this.pc.setLocalDescription(answer);

            this.sendSignal({
                type: 'answer',
                answer: answer
            });

            this.log('Answer oluşturuldu ve gönderildi');
        } catch (error) {
            this.log(`Answer hatası: ${error}`);
        }
    }
}

// Global client instance
let client;

// Sayfa yüklendiğinde başlat
document.addEventListener('DOMContentLoaded', () => {
    client = new FastIRLClient();
    client.log('Fast IRL Web Client başlatıldı');
});

// Global functions for buttons
function connect() {
    client.connect();
}

function disconnect() {
    client.disconnect();
}

function startStream() {
    client.startStream();
}

function stopStream() {
    client.stopStream();
}

function createOffer() {
    client.createOffer();
}

function createAnswer() {
    client.createAnswer();
}

function setupFullscreenControls() {
    const fullscreenBtn = document.getElementById('fullscreenBtn');
    if (fullscreenBtn) {
        fullscreenBtn.addEventListener('click', () => {
            enterFullscreen();
        });
    }
}

function enterFullscreen() {
    const fullscreenPlayer = document.getElementById('fullscreenPlayer');
    const fullscreenVideo = document.getElementById('fullscreenVideo');
    const remoteVideo = document.getElementById('remoteVideo');
    
    if (remoteVideo.srcObject) {
        fullscreenVideo.srcObject = remoteVideo.srcObject;
        fullscreenPlayer.style.display = 'block';
        
        // Request browser fullscreen if supported
        if (fullscreenPlayer.requestFullscreen) {
            fullscreenPlayer.requestFullscreen();
        } else if (fullscreenPlayer.webkitRequestFullscreen) {
            fullscreenPlayer.webkitRequestFullscreen();
        } else if (fullscreenPlayer.msRequestFullscreen) {
            fullscreenPlayer.msRequestFullscreen();
        }
        
        client.log('🖥️ Fullscreen mode açıldı');
    } else {
        client.log('❌ Remote video stream yok - fullscreen açılamadı');
    }
}

function exitFullscreen() {
    const fullscreenPlayer = document.getElementById('fullscreenPlayer');
    fullscreenPlayer.style.display = 'none';
    
    // Exit browser fullscreen if active
    if (document.exitFullscreen) {
        document.exitFullscreen();
    } else if (document.webkitExitFullscreen) {
        document.webkitExitFullscreen();
    } else if (document.msExitFullscreen) {
        document.msExitFullscreen();
    }
    
    client.log('📱 Fullscreen mode kapatıldı');
}

// Initialize fullscreen controls when page loads
document.addEventListener('DOMContentLoaded', () => {
    setupFullscreenControls();
    
    // ESC key to exit fullscreen
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            const fullscreenPlayer = document.getElementById('fullscreenPlayer');
            if (fullscreenPlayer.style.display === 'block') {
                exitFullscreen();
            }
        }
    });
    
    // Handle browser fullscreen exit
    document.addEventListener('fullscreenchange', () => {
        if (!document.fullscreenElement) {
            const fullscreenPlayer = document.getElementById('fullscreenPlayer');
            if (fullscreenPlayer.style.display === 'block') {
                exitFullscreen();
            }
        }
    });
});
