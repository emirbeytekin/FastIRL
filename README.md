# 🚀 Fast IRL - Canlı Yayın Platformu

Fast IRL, iOS cihazlardan canlı yayın yapmanızı sağlayan modern bir platformdur. Web tabanlı landing page ile rastgele yayın odaları oluşturabilir, iOS uygulaması ile yayın yapabilir ve web üzerinden izleyebilirsiniz.

## ✨ Özellikler

- **🎯 Rastgele Yayın Odaları**: Her kullanıcı için benzersiz oda ID'leri
- **📱 iOS Uygulaması**: Yüksek kaliteli kamera yayını
- **🌐 Web Landing Page**: Modern ve kullanıcı dostu arayüz
- **🔗 Embed Player**: Web sitelerine gömülebilir yayın oynatıcısı
- **⚡ WebRTC**: Düşük gecikme süreli canlı yayın
- **📊 Gerçek Zamanlı İstatistikler**: Yayın kalitesi ve bağlantı durumu
- **🎨 Widget Sistemi**: URL tabanlı overlay'ler (sadece local'de görünür)

## 🏗️ Sistem Mimarisi

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   iOS App       │    │   Web Server    │    │   Web Client    │
│   (Broadcaster) │◄──►│   (Signaling)   │◄──►│   (Viewer)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Camera       │    │   WebSocket     │    │   WebRTC        │
│   + Overlays   │    │   + Room Mgmt   │    │   + Video       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Hızlı Başlangıç

### 1. Web Server'ı Başlat

```bash
cd web
npm install
node server.js
```

Server `http://localhost:8080` adresinde çalışacak.

### 2. Landing Page'e Git

Tarayıcınızda `http://localhost:8080` adresini açın.

### 3. Yayın Odası Oluştur

- "🚀 Yayın Odası Oluştur" butonuna tıklayın
- Rastgele bir oda ID'si oluşturulacak
- Oluşturulan linki kopyalayın

### 4. iOS Uygulamasını Aç

- Xcode'da `Fast IRL.xcodeproj` dosyasını açın
- Simulator'da çalıştırın
- WebSocket URL'ini `ws://192.168.1.100:8080` olarak ayarlayın
- Yayını başlatın

### 5. Web'den İzle

- Yayın linkine tıklayın
- Canlı yayını izleyin

## 📱 iOS Uygulaması

### Özellikler

- **Kamera Kontrolü**: Ön/arka kamera değiştirme
- **Video Kalitesi**: 720p, 1080p, 2K, 4K desteği
- **FPS Seçimi**: 30fps ve 60fps
- **Bitrate Kontrolü**: 1-50 Mbps arası ayarlanabilir
- **Widget Sistemi**: URL tabanlı overlay'ler
- **Otomatik Başlatma**: App açıldığında otomatik yayın

### Kurulum

1. Xcode 15+ gerekli
2. iOS 18.5+ hedef platform
3. WebRTC framework otomatik yüklenir

```bash
# Proje klasörüne git
cd "Fast IRL"

# Xcode'da aç
open "Fast IRL.xcodeproj"
```

## 🌐 Web Server

### Endpoints

- **`/`** - Landing page
- **`/create-room`** - Yeni yayın odası oluştur
- **`/room/{id}`** - Yayın odası sayfası
- **`/embed/{id}`** - Embed player
- **`/script.js`** - JavaScript dosyaları
- **`/style.css`** - CSS dosyaları

### WebSocket Mesajları

#### Oda Oluşturma
```json
{
  "type": "create-room",
  "title": "Yayın Başlığı"
}
```

#### Odaya Katılma
```json
{
  "type": "join-room",
  "roomId": "ABC123"
}
```

#### WebRTC Signaling
```json
{
  "type": "offer|answer|ice-candidate",
  "data": {...}
}
```

#### Yayın Durumu
```json
{
  "type": "broadcast-status",
  "isLive": true,
  "title": "Yayın Başlığı"
}
```

## 🎨 Widget Sistemi

Widget'lar sadece yayıncıya local olarak görünür, izleyicilere gönderilmez.

### Widget Ekleme

1. iOS uygulamasında "Widget Ekle" bölümüne URL girin
2. Widget başlığı ekleyin (opsiyonel)
3. "Ekle" butonuna tıklayın

### Widget Özellikleri

- **Pinch-to-Zoom**: Parmak hareketleri ile boyutlandırma
- **Sürükleme**: Ekranda istediğiniz yere taşıyın
- **Refresh**: Yenileme butonu ile içeriği güncelleyin
- **16:9 Oran**: Otomatik aspect ratio korunur
- **Otomatik Oynatma**: Medya otomatik başlar

## 🔧 Teknik Detaylar

### WebRTC Konfigürasyonu

```swift
// iOS uygulamasında
let configuration = RTCConfiguration()
configuration.iceServers = [
    RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
]
```

### Video Kalitesi Ayarları

```swift
// Çözünürlük ve FPS
client.adaptOutputFormat(width: 1920, height: 1080, fps: 60)

// Bitrate
client.setVideoMaxBitrate(kbps: 15000) // 15 Mbps
```

### Overlay Sistemi

```swift
// CompositorVideoCapturer
compositor.processOverlays(cameraFrame: frame, overlays: widgets)
```

## 📊 Performans

### Önerilen Ayarlar

- **1080p60**: 15 Mbps bitrate
- **2K60**: 25 Mbps bitrate  
- **4K30**: 30 Mbps bitrate

### Sistem Gereksinimleri

- **iOS**: 18.5+
- **RAM**: 4GB+ (4K yayın için)
- **CPU**: A12 Bionic+
- **Ağ**: 20+ Mbps upload

## 🐛 Sorun Giderme

### Yayın Başlamıyor

1. WebSocket bağlantısını kontrol edin
2. Kamera izinlerini kontrol edin
3. Ağ bağlantısını kontrol edin

### Video Kalitesi Düşük

1. Bitrate ayarlarını kontrol edin
2. Ağ hızını test edin
3. Kamera formatını kontrol edin

### Widget Görünmüyor

1. Widget'ın aktif olduğundan emin olun
2. URL'nin doğru olduğunu kontrol edin
3. WebView ayarlarını kontrol edin

## 🔒 Güvenlik

- **Oda ID'leri**: Rastgele 6 karakter
- **WebSocket**: Sadece local network
- **Kamera**: Sadece kullanıcı izni ile
- **Overlay**: Sadece local'de görünür

## 📝 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit yapın (`git commit -m 'Add amazing feature'`)
4. Push yapın (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📞 Destek

- **GitHub Issues**: [Proje sayfasında](https://github.com/username/fast-irl)
- **Email**: support@fastirl.com
- **Discord**: [Sunucu linki]

## 🚀 Gelecek Planları

- [ ] Çoklu yayıncı desteği
- [ ] Chat sistemi
- [ ] Yayın kaydetme
- [ ] Sosyal medya entegrasyonu
- [ ] Analytics dashboard
- [ ] Mobile app (Android)

---

**Fast IRL** ile canlı yayın yapmanın keyfini çıkarın! 🎥✨
