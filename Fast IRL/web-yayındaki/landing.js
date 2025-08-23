// Landing page functionality
document.addEventListener('DOMContentLoaded', function() {
    const createRoomBtn = document.getElementById('createRoomBtn');
    const roomModal = document.getElementById('roomModal');
    
    // Oda oluşturma butonuna tıklandığında
    createRoomBtn.addEventListener('click', createRoom);
    
    // Modal dışına tıklandığında kapat
    window.addEventListener('click', function(event) {
        if (event.target === roomModal) {
            closeModal();
        }
    });
    
    // ESC tuşu ile modal'ı kapat
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            closeModal();
        }
    });
});

// Yeni yayın odası oluştur
async function createRoom() {
    const createRoomBtn = document.getElementById('createRoomBtn');
    
    try {
        // Buton durumunu güncelle
        createRoomBtn.disabled = true;
        createRoomBtn.textContent = '⏳ Oluşturuluyor...';
        
        // API'ye istek gönder
        const response = await fetch('/create-room', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                title: `Yayın ${Date.now()}`
            })
        });
        
        if (!response.ok) {
            throw new Error('Oda oluşturulamadı');
        }
        
        const data = await response.json();
        
        if (data.success) {
            // Modal'ı aç ve bilgileri göster
            showRoomModal(data);
        } else {
            throw new Error(data.message || 'Bilinmeyen hata');
        }
        
    } catch (error) {
        console.error('Oda oluşturma hatası:', error);
        alert('❌ Oda oluşturulamadı: ' + error.message);
        
        // Buton durumunu geri al
        createRoomBtn.disabled = false;
        createRoomBtn.textContent = '🚀 Yayın Odası Oluştur';
    }
}

// Oda modal'ını göster
function showRoomModal(roomData) {
    // Bilgileri doldur
    document.getElementById('roomIdDisplay').textContent = roomData.roomId;
    document.getElementById('roomUrlDisplay').value = roomData.roomUrl;
    document.getElementById('embedUrlDisplay').value = roomData.embedUrl;
    
    // Modal'ı göster
    roomModal.style.display = 'flex';
    
    // Buton durumunu geri al
    const createRoomBtn = document.getElementById('createRoomBtn');
    createRoomBtn.disabled = false;
    createRoomBtn.textContent = '🚀 Yayın Odası Oluştur';
    
    // Başarı animasyonu
    showSuccessMessage('🎉 Yayın odası başarıyla oluşturuldu!');
}

// Modal'ı kapat
function closeModal() {
    roomModal.style.display = 'none';
}

// Oda ID'sini kopyala
function copyRoomId() {
    const roomId = document.getElementById('roomIdDisplay').textContent;
    copyToClipboard(roomId);
    showCopyMessage('Oda ID kopyalandı!');
}

// Yayın linkini kopyala
function copyRoomUrl() {
    const roomUrl = document.getElementById('roomUrlDisplay').value;
    copyToClipboard(roomUrl);
    showCopyMessage('Yayın linki kopyalandı!');
}

// Embed linkini kopyala
function copyEmbedUrl() {
    const embedUrl = document.getElementById('embedUrlDisplay').value;
    copyToClipboard(embedUrl);
    showCopyMessage('Embed linki kopyalandı!');
}

// Odayı aç
function openRoom() {
    const roomUrl = document.getElementById('roomUrlDisplay').value;
    window.open(roomUrl, '_blank');
}

// Odayı paylaş
function shareRoom() {
    const roomUrl = document.getElementById('roomUrlDisplay').value;
    const roomId = document.getElementById('roomIdDisplay').textContent;
    
    if (navigator.share) {
        navigator.share({
            title: `Fast IRL Yayın Odası: ${roomId}`,
            text: `Bu yayın odasına katıl: ${roomId}`,
            url: roomUrl
        });
    } else {
        // Fallback: linki kopyala
        copyRoomUrl();
        showCopyMessage('Link kopyalandı! Artık paylaşabilirsin.');
    }
}

// Panoya kopyala
function copyToClipboard(text) {
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text);
    } else {
        // Fallback: eski yöntem
        const textArea = document.createElement('textarea');
        textArea.value = text;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
    }
}

// Kopyalama mesajı göster
function showCopyMessage(message) {
    showToast(message, 'success');
}

// Başarı mesajı göster
function showSuccessMessage(message) {
    showToast(message, 'success');
}

// Toast mesajı göster
function showToast(message, type = 'info') {
    // Mevcut toast'ları temizle
    const existingToasts = document.querySelectorAll('.toast');
    existingToasts.forEach(toast => toast.remove());
    
    // Yeni toast oluştur
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    
    // Stil ekle
    toast.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${type === 'success' ? '#10b981' : '#3b82f6'};
        color: white;
        padding: 12px 20px;
        border-radius: 8px;
        font-weight: 500;
        z-index: 10000;
        animation: slideIn 0.3s ease-out;
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    `;
    
    // CSS animasyonu ekle
    const style = document.createElement('style');
    style.textContent = `
        @keyframes slideIn {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
    `;
    document.head.appendChild(style);
    
    // Toast'u sayfaya ekle
    document.body.appendChild(toast);
    
    // 3 saniye sonra kaldır
    setTimeout(() => {
        toast.style.animation = 'slideOut 0.3s ease-in';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
    
    // Slide out animasyonu
    const slideOutStyle = document.createElement('style');
    slideOutStyle.textContent = `
        @keyframes slideOut {
            from { transform: translateX(0); opacity: 1; }
            to { transform: translateX(100%); opacity: 0; }
        }
    `;
    document.head.appendChild(slideOutStyle);
}

// Sayfa yüklendiğinde animasyonları başlat
window.addEventListener('load', function() {
    // Hero animasyonu
    const heroTitle = document.querySelector('.hero-title');
    const heroSubtitle = document.querySelector('.hero-subtitle');
    const ctaButton = document.querySelector('.cta-button');
    
    setTimeout(() => heroTitle.style.opacity = '1', 200);
    setTimeout(() => heroSubtitle.style.opacity = '1', 400);
    setTimeout(() => ctaButton.style.opacity = '1', 600);
    
    // Feature kartları animasyonu
    const featureCards = document.querySelectorAll('.feature-card');
    featureCards.forEach((card, index) => {
        setTimeout(() => card.style.opacity = '1', 800 + (index * 100));
    });
    
    // Step kartları animasyonu
    const stepCards = document.querySelectorAll('.step');
    stepCards.forEach((step, index) => {
        setTimeout(() => step.style.opacity = '1', 1200 + (index * 150));
    });
});
