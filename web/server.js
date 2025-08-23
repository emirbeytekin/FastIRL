#!/usr/bin/env node

const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

// Basit HTTP server
const server = http.createServer((req, res) => {
    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    let filePath = path.join(__dirname, req.url === '/' ? 'index.html' : req.url);
    
    // Static dosyaları serve et
    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404);
            res.end('File not found');
            return;
        }
        
        const ext = path.extname(filePath);
        const contentType = {
            '.html': 'text/html',
            '.js': 'text/javascript',
            '.css': 'text/css'
        }[ext] || 'text/plain';
        
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

// WebSocket server
const wss = new WebSocket.Server({ server });

let connections = []; // Tüm bağlantılar
let connectionStats = {
    total: 0,
    active: 0,
    reconnected: 0
};



// Bağlantı durumunu log'la
function logConnectionStats() {
    console.log(`📊 Bağlantı İstatistikleri:`);
    console.log(`   Toplam: ${connectionStats.total}`);
    console.log(`   Aktif: ${connectionStats.active}`);
    console.log(`   Yeniden Bağlanan: ${connectionStats.reconnected}`);
    console.log(`   Başarı Oranı: ${connectionStats.total > 0 ? ((connectionStats.active / connectionStats.total) * 100).toFixed(1) : 0}%`);
}

// Bağlantıları temizle
function cleanupConnections() {
    const beforeCleanup = connections.length;
    connections = connections.filter(conn => {
        if (conn.readyState === WebSocket.OPEN) {
            return true;
        } else {
            console.log('🧹 Kapalı bağlantı temizlendi');
            return false;
        }
    });
    
    if (beforeCleanup !== connections.length) {
        connectionStats.active = connections.length;
        logConnectionStats();
    }
}

// Periyodik temizlik
setInterval(cleanupConnections, 30000); // Her 30 saniyede bir

wss.on('connection', (ws, req) => {
    const clientId = Math.random().toString(36).substr(2, 9);
    const clientIP = req.socket.remoteAddress || 'unknown';
    
    // URL'den oda ID'yi al
    const url = new URL(req.url, `http://${req.headers.host}`);
    const roomId = url.pathname.substring(1); // İlk "/" karakterini kaldır
    
    console.log(`🔗 Yeni client bağlandı [${clientId}] - IP: ${clientIP} - Oda: ${roomId}`);
    
    // Oda ID kontrolü
    if (!roomId || roomId.length !== 6) {
        console.log(`❌ Geçersiz oda ID: ${roomId}`);
        ws.close(1008, 'Geçersiz oda ID');
        return;
    }
    
    // Oda ID'yi client'a ata
    ws.roomId = roomId;
    ws.clientId = clientId;
    ws.clientIP = clientIP;
    ws.connectedAt = Date.now();
    
    connections.push(ws);
    connectionStats.total++;
    connectionStats.active++;
    
    // Welcome mesajı
    ws.send(JSON.stringify({
        type: 'welcome',
        message: 'Fast IRL Signaling Server\'a hoş geldiniz!',
        roomId: roomId,
        clientId: clientId,
        timestamp: Date.now()
    }));
    
    logConnectionStats();
    
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            console.log(`📨 [${clientId}] Oda: ${roomId} - Mesaj alındı: ${data.type}`);
            
            // Sadece aynı oda ID'ye sahip client'lara forward et
            let forwardedCount = 0;
            connections.forEach(client => {
                if (client !== ws && client.readyState === WebSocket.OPEN && client.roomId === roomId) {
                    client.send(JSON.stringify(data));
                    forwardedCount++;
                }
            });
            
            if (forwardedCount > 0) {
                console.log(`📤 [${clientId}] Oda: ${roomId} - Mesaj ${forwardedCount} client'a forward edildi: ${data.type}`);
            } else {
                console.log(`📤 [${clientId}] Oda: ${roomId} - Mesaj forward edilemedi (aynı odada başka client yok)`);
            }
            
        } catch (error) {
            console.error(`❌ [${clientId}] Oda: ${roomId} - Mesaj işleme hatası:`, error);
            // Client'a hata mesajı gönder
            ws.send(JSON.stringify({
                type: 'error',
                message: 'Mesaj işleme hatası: ' + error.message,
                timestamp: Date.now()
            }));
        }
    });
    
    ws.on('close', (code, reason) => {
        const duration = Date.now() - ws.connectedAt;
        console.log(`❌ [${clientId}] Oda: ${roomId} - Client bağlantısı kesildi - Kod: ${code}, Sebep: ${reason || 'Bilinmiyor'}, Süre: ${Math.round(duration / 1000)}s`);
        connections = connections.filter(conn => conn !== ws);
        connectionStats.active = connections.length;
        logConnectionStats();
    });
    
    ws.on('error', (error) => {
        console.error(`❌ [${clientId}] Oda: ${roomId} - WebSocket hatası:`, error);
    });
    
    // Ping/Pong ile bağlantı durumunu kontrol et
    ws.isAlive = true;
    ws.on('pong', () => {
        ws.isAlive = true;
    });
});

// Ping/Pong mekanizması ile bağlantıları kontrol et
const pingInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            console.log(`💀 [${ws.clientId || 'unknown'}] Oda: ${ws.roomId || 'unknown'} - Bağlantı ölü, kapatılıyor`);
            return ws.terminate();
        }
        
        ws.isAlive = false;
        ws.ping();
    });
}, 30000); // Her 30 saniyede bir

// Server kapatılırken temizlik
wss.on('close', () => {
    clearInterval(pingInterval);
    console.log('🔄 WebSocket server kapatılıyor...');
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('🔄 SIGTERM alındı, server kapatılıyor...');
    wss.close(() => {
        server.close(() => {
            console.log('✅ Server başarıyla kapatıldı');
            process.exit(0);
        });
    });
});

process.on('SIGINT', () => {
    console.log('🔄 SIGINT alındı, server kapatılıyor...');
    wss.close(() => {
        server.close(() => {
            console.log('✅ Server başarıyla kapatıldı');
            process.exit(0);
        });
    });
});

const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 Fast IRL Signaling Server başlatıldı:');
    console.log(`   Ana Sayfa: http://0.0.0.0:${PORT}`);
    console.log(`   WebSocket: ws://0.0.0.0:${PORT}`);
    console.log(`   Network: http://173.249.21.219:${PORT}`);
    console.log(`   PID: ${process.pid}`);
    console.log(`   Node.js: ${process.version}`);
    console.log(`   Platform: ${process.platform} ${process.arch}`);
    console.log('📊 Bağlantı izleme aktif (30s ping/pong)');
    console.log('🧹 Otomatik temizlik aktif (30s)');
});