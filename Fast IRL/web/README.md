# Fast IRL - Web Client 🎥

Bu klasör Fast IRL iOS uygulamasını test etmek için web client içerir.

## 🚀 Kurulum

### 1. Node.js Kurulumu
```bash
# Node.js yüklü değilse:
# https://nodejs.org/en/download/ 
# veya
brew install node
```

### 2. Dependencies Kurulumu
```bash
cd web
npm install
```

## 🎯 Kullanım

### 1. Web Server'ı Başlat
```bash
npm start
```

Server şu adreslerde çalışacak:
- **Web UI**: http://173.249.21.219:8080
- **WebSocket**: ws://173.249.21.219:8080

### 2. iOS App'i Configüre Et
iOS uygulamasında WebSocket URL'sini şu şekilde ayarla:
```
ws://173.249.21.219:8080
```

### 3. Test Adımları

#### Web Tarafında:
1. http://173.249.21.219:8080 aç
2. "Yayın Başlat" tıkla (kamera izni ver)
3. "Bağlan" tıkla
4. "Offer Gönder" tıkla

#### iOS App'de:
1. Start butonuna bas
2. WebSocket bağlantısını kur
3. Web'den gelen offer'ı kabul et
4. Answer gönder

## 🔧 Test Senaryoları

### Overlay Testi:
1. iOS app'de "Overlays" toggle'ını aç
2. Bir web widget ekle (örn: `https://www.google.com`)
3. Widget'ın web stream'de görünmesini kontrol et
4. Widget'ı drag/resize et
5. Remove et

### Multi-Widget Testi:
1. Birden fazla widget ekle
2. Resize/drag işlemlerini test et
3. Her widget'ı tek tek remove et

## 📊 Debug

### Console Log'ları:
- **Web**: Browser Developer Tools Console
- **iOS**: Xcode Console
- **Server**: Terminal'deki server log'ları

### WebRTC State:
Web UI'da connection state izlenebilir:
- `connecting` → Bağlanıyor
- `connected` → Bağlandı  
- `disconnected` → Bağlantı kesildi

## 🛠️ Troubleshooting

### Kamera İzni:
```javascript
// Browser'da kamera izni verilmemişse:
// Chrome: chrome://settings/content/camera
// Safari: Safari > Preferences > Websites > Camera
```

### WebSocket Bağlantısı:
```bash
# Server çalışıyor mu?
curl http://173.249.21.219:8080

# Port kullanımda mı?
lsof -i :8080
```

### WebRTC Connection:
1. STUN server'lar erişilebilir mi?
2. Network/firewall engeli var mı?
3. ICE candidates oluşuyor mu?

## 📱 iOS App Integration

iOS app'in WebSocket client'ı bu server ile uyumlu olmalı.

### Signal Format:
```json
{
  "type": "offer|answer|ice-candidate",
  "offer": RTCSessionDescription,
  "answer": RTCSessionDescription,
  "candidate": RTCIceCandidate
}
```

## 🎉 Success!

Her şey çalışıyorsa:
- Web'de kendi kameranı görürsün
- iOS'ta web'den gelen video stream'ini görürsün  
- iOS'ta eklediğin overlay'lar web stream'de görünür
- Kamera donma problemi yok!
