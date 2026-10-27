# MediaBar

Bu Mac için geliştirilen, Swift/AppKit ve Objective-C ile yazılmış Touch Bar medya kontrol uygulaması. Xcode 27.1 ile derlenir; hedef macOS 27.0’dır.

Uygulama normal başlatıldığında Touch Bar panelini gösterir ve uygulamalar arasında geçişte korur. Menü çubuğundaki nota simgesinde yalnızca **Quit** bulunur. Pencere, Dock simgesi, otomatik başlatma ve ayarlar yoktur. Çıkışta panel kapatılır, bekleyen sarma bitiş komutları gönderilir ve XPC bağlantısı kapatılır.

## Yapı

- `MediaBar/TouchBarView.swift`: Tasarımın tamamı; ölçüler, renkler, düğmeler, kayan metin, ilerleme çizimi ve geniş sarma ekranı. Arayüz değişiklikleri bu dosyada yapılır.
- `MediaBar/MediaController.swift`: Medya durumu, eylemler, süre yenilemesi ve favori isteklerinin yönetimi. Arayüz ile `MediaState` / `MediaAction` üzerinden konuşur.
- `MediaBar/TouchBarPresenter.swift` ve `MediaBar/Native/TouchBarSystem.m`: Sistem genelinde Touch Bar sunumu ve uygulama/masaüstü/uyanma bildirimleri.
- `MediaService`: MediaRemote’a doğrudan erişen Objective-C XPC servisi. Xcode tarafından derlenir ve uygulamanın `Contents/XPCServices` dizinine gömülür. Durum 0,5 saniyede bir alınır; süre gösterimi güncellemeler arasında yerel olarak ilerler.
- `MediaBar/Native/MusicAutomation.m`: Music’e doğrudan Apple Events gönderir. AppleScript, Perl, shell veya başka bir yorumlayıcı kullanmaz. Favorileri 5 saniyede bir okur; düğme sadece favorilere ekler, kaldırmaz.

Önceki/sonraki kontrolleri Podcasts’te 15 saniye geri/ileri çalışır. Uzun basmak sarma başlatır; bırakmak, bağlam değişimi veya 15 saniyelik güvenlik sınırı sarmayı bitirir. Süre alanına dokunmak geniş sarma ekranını açar; sürükleme bitince konum gönderilir. Süre alanına yeniden dokunmak normal görünüme döner. Parça bilgisine dokunmak oynatıcıyı öne getirir. Medya yoksa kontroller devre dışı kalır; süre bilgisi yoksa zaman alanı gizlenir.

## Yerel sistem erişimi

MediaRemote’un macOS 15.4 sonrasındaki erişim denetimi nedeniyle servis kimliği `com.apple.sezerbudak.MediaBar.MediaService` olarak ayarlanmıştır. Ana uygulamanın kimliği `com.sezerbudak.MediaBar` olarak kalır. Bu yaklaşım [mediaremote-adapter’ın belgelenmiş kimlik denetimi davranışına](https://github.com/ungive/mediaremote-adapter#why-this-works) dayanır. Servis Apple tarafından sağlanan veya imzalanan bir bileşen değildir; bu projede yerel olarak derlenir.

Touch Bar sunumu da özel macOS API’lerini kullanır. Derleme ve paket doğrulaması, bu özel API’lerin cihaz üzerindeki çalışma doğrulaması değildir. Eksik semboller veya bağlantı hataları uygulamayı çökertmeden sistem günlüğüne yazılır; medya kontrolleri boş/devre dışı duruma döner. Betik tabanlı yedek yol yoktur.

App Sandbox kapalıdır. Music’in favori özelliği ilk kullanımda macOS otomasyon izni gerektirebilir. Uygulama paketi izin açıklamasını ve Apple Events yetkisini içerir. Yayınlama, dağıtım veya açılış kaydı yapılmaz.

MediaRemote özel API bildirimleri `ungive/mediaremote-adapter` projesinin `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` sürümünden alınmıştır. BSD-3-Clause lisansı `MediaBar/Resources/MediaRemoteAdapter-LICENSE.txt` içinde tutulur ve uygulamaya kopyalanır. Eski TouchBar projesi değiştirilmez.

## Uygulamayı açmadan doğrulama

```sh
xcodebuild -project MediaBar.xcodeproj -scheme MediaBar -configuration Debug -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build
xcodebuild -project MediaBar.xcodeproj -scheme MediaBar -configuration Release -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build

xcrun swiftc -module-cache-path build/ModuleCache MediaBar/Models/PlaybackTimeline.swift MediaBar/Models/FavoriteRequestState.swift MediaBar/Models/MediaState.swift Tests/main.swift -o build/MediaBarModelTests
build/MediaBarModelTests
```

Model testleri Foundation kullanır; MediaBar’ı veya XPC servisini başlatmaz, Touch Bar oluşturmaz ve Music’e erişmez. Süre/oynatma hızı, geçersiz veriler, sarma sınırları, oynatıcı/parça kimliği ve favori isteklerinin gecikmiş sonuçları kontrol edilir.

Fiziksel Touch Bar görünümü, Music/Podcasts ve diğer sistem oynatıcılarının verisi, otomasyon izni, uygulama geçişi/uyanma sonrası panel ve Quit sonrası eski Touch Bar’a dönüş kullanıcı tarafından doğrulanmalıdır. Geliştirme sırasında uygulama veya önizleme açılmaz.
