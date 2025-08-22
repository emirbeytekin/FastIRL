# 🚀 Fast IRL - Local Test Guide

Bu dosya Fast IRL uygulamanızı lokal olarak test etmek için adım adım rehberdir.

## 📋 Gereksinimler

✅ **Mac (iOS Simulator için)**  
✅ **Node.js** (v14+) - https://nodejs.org  
✅ **Xcode** (iOS geliştirme için)  

## 🎯 1. Adım - Web Server Başlatma

```bash
# Terminal'de FastIRL dizinine git
cd /Users/emirbeytekin/Documents/works/FastIRL/web

# Dependencies kurulumu (ilk kez)
npm install

# Web server'ı başlat
npm start
```

**✅ Sonuç:** Terminal'de şunları göreceksin:
```
🚀 Fast IRL Signaling Server başlatıldı:
   Web UI: http://localhost:8080
   WebSocket: ws://localhost:8080
   Bağlı client sayısı: 0
```

## 🎯 2. Adım - iOS App Test

### Xcode'da iOS App Başlat:
1. `Fast IRL.xcodeproj` aç
2. iPhone Simulator seç
3. ▶️ Run buton bas

### App'de WebSocket Bağlantısı:
1. **"Start"** butonuna bas (kamera başlatılsın)
2. Sağ panelde WebSocket URL'sini kontrol et: **`ws://192.168.0.140:8080`** 
3. **"Connect"** butonuna bas
4. **Yeşil** "Connected" mesajını gör

**⚠️ ÖNEMLİ**: `192.168.0.140` IP'sini kendi bilgisayarının IP'si ile değiştir:
```bash
# Terminal'de IP adresini öğren:
ifconfig en0 | grep inet | grep -v inet6 | awk '{print $2}'
```

## 🎯 3. Adım - Web Client Test

### Browser'da web client aç:
1. http://localhost:8080 adresine git
2. **"Yayın Başlat"** butonuna bas (kamera izni ver)
3. **"Bağlan"** butonuna bas
4. **"Offer Gönder"** butonuna bas

### iOS App'de Answer Gönder:
- iOS app otomatik olarak answer gönderecek
- Console'da log'ları takip et

## 🎯 4. Adım - Overlay Test

### iOS'ta overlay ekle:
1. **"Overlays"** toggle'ını aç
2. URL field'ına `https://www.google.com` yaz
3. **"Add"** butonuna bas
4. Widget görününceye kadar bekle

### Web'de overlay'ı gör:
- Browser'daki **"Uzak Video"** bölümünde Google'ın overlay olarak görünmesi gerekiyor

## 🎯 5. Adım - Widget Manipülasyonu

### Drag & Drop:
- iOS'ta widget'ı parmağınla sürükle

### Resize:
- Widget köşelerindeki küçük dairelerden resize et
- Pinch gesture ile de resize edebilirsin

### Remove:
- Sağ panelden widget'ın yanındaki **"Remove"** butonuna bas

## 🔧 Troubleshooting

### ❌ Web Server Bağlanamıyor:
```bash
# Port kullanımda mı kontrol et
lsof -i :8080

# Eğer kullanımdaysa kill et
kill -9 PID_NUMBER
```

### ❌ iOS Kamera İzni:
1. Simulator > Device > Erase All Content and Settings
2. App'i yeniden başlat
3. İzin ver

### ❌ WebRTC Bağlantı Sorunu:
1. Her iki tarafın da konsol log'larını kontrol et
2. ICE candidates oluşuyor mu?
3. STUN server erişilebilir mi?

### ❌ Overlay Görünmüyor:
1. iOS Console'da pipeline log'larını kontrol et
2. `hasActiveOverlays` true mu?
3. `compositor` nil değil mi?

## 📊 Debug Log'ları

### Web Console (F12):
```
📨 Signal alındı: offer
📤 Signal gönderildi: answer
📡 ICE connection state changed: connected
```

### iOS Console (Xcode):
```
✅ WebSocket bağlandı
📨 Offer alındı
✅ Answer gönderildi
📡 ICE connection state changed: connected
🔄 setupPipeline: hasOverlays=true, compositor=true, camera=true
✅ Pipeline aynı türde, restart etmiyoruz
```

## 🎉 Success Indicators

✅ **Web'de yerel kameranı görüyorsun**  
✅ **Web'de iOS'tan gelen video stream'ini görüyorsun**  
✅ **iOS'ta eklediğin overlay'lar web'de görünüyor**  
✅ **Widget drag/resize/remove çalışıyor**  
✅ **Kamera donma problemi yok**  

## 🎯 Test Senaryoları

### Senaryo 1: Temel WebRTC
1. Web + iOS kamera başlat
2. WebSocket bağlan
3. Offer/Answer değişimi
4. Video stream akışı

### Senaryo 2: Single Overlay
1. İlk widget'ı ekle
2. Web'de görünmesini bekle
3. Drag et
4. Resize et
5. Remove et

### Senaryo 3: Multiple Overlays
1. 3-4 widget ekle
2. Her birini manipüle et
3. Kamera donma olmadığını kontrol et
4. Hepsini tek tek remove et

### Senaryo 4: Stress Test
1. Çok hızlı widget ekleme/çıkarma
2. Sürekli resize işlemleri
3. Overlay toggle açıp kapama
4. WebSocket disconnect/reconnect

---

**🎯 Sorun yaşarsan:** Console log'larını kontrol et ve hata mesajlarını not al!
