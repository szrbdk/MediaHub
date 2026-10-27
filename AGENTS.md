# MediaBar çalışma kuralları

- Uygulamayı çalıştırma; Touch Bar paneli, pencere veya önizleme açarak test yapma.
- Derleme ve uygulamayı açmayan, sistem medyasına erişmeyen mantık testleri yapılabilir.
- Dosya değişikliklerinde Python kullanma.
- Otomatik commit oluşturma. Kullanıcı commit isterse Conventional Commits kullan.
- Touch Bar tasarımı ve görsel etkileşimleri yalnızca `MediaBar/TouchBarView.swift` içinde tut. Medya erişimini ve sistem paneli sunumunu bu dosyaya ekleme.
- Menü çubuğu menüsünde `MediaBar` başlığı, bir ayırıcı ve tek eylem olarak `Quit` olsun. Simgenin araç ipucu da `MediaBar` olsun. Ana pencere, Dock simgesi, ayarlar veya otomatik başlatma ekleme. Parça değişiminde kamera hizasından açılan, odağı almayan geçici bildirim paneli kullanılabilir.
- Yalnızca kullanıcının mevcut Mac’i hedefleniyor. Yayınlama ve dağıtım altyapısı ekleme.
- Swift, Objective-C ve C tercih et; çalışma zamanında Perl, shell, AppleScript veya Python betikleri kullanma.
- Referans `/Users/sezerbudak/Developer/personal/TouchBar` projesini değiştirme.
