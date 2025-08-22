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

wss.on('connection', (ws) => {
    console.log('🔗 Yeni client bağlandı');
    connections.push(ws);
    
    // Welcome mesajı
    ws.send(JSON.stringify({
        type: 'welcome',
        message: 'Fast IRL Signaling Server\'a hoş geldiniz!'
    }));
    
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            console.log('📨 Mesaj alındı:', data.type);
            
            // Diğer tüm clientlara forward et
            connections.forEach(client => {
                if (client !== ws && client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify(data));
                    console.log('📤 Mesaj forward edildi:', data.type);
                }
            });
            
        } catch (error) {
            console.error('❌ Mesaj işleme hatası:', error);
        }
    });
    
    ws.on('close', () => {
        console.log('❌ Client bağlantısı kesildi');
        connections = connections.filter(conn => conn !== ws);
        console.log('📊 Aktif bağlantı sayısı:', connections.length);
    });
    
    ws.on('error', (error) => {
        console.error('❌ WebSocket hatası:', error);
    });
});

const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 Fast IRL Signaling Server başlatıldı:');
    console.log(`   Ana Sayfa: http://0.0.0.0:${PORT}`);
    console.log(`   WebSocket: ws://0.0.0.0:${PORT}`);
    console.log(`   Network: http://192.168.0.219:${PORT}`);
});