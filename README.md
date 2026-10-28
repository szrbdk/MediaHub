# MediaBar

Bu Mac için geliştirilen, Swift/AppKit ve Objective-C ile yazılmış Touch Bar medya kontrol uygulaması. Xcode 27.1 ile derlenir; hedef macOS 27.0’dır.

Uygulama normal başlatıldığında kayıtlı tercihlere göre Touch Bar panelini ve parça bildirimlerini etkinleştirir. Menü çubuğunda **MediaBar** başlığı, **Bildirimler**, **Touch Bar** ve **Otomatik atlama** aç/kapat seçenekleri, **Karalisteye ekle**, **Karalisteyi yönet** ve **Quit** bulunur. Açık seçenekler işaretlidir. Seçimler UserDefaults ile kaydedilir ve sonraki açılışta korunur; kayıtlı tercih yoksa üç seçenek de açıktır. Simgenin araç ipucu uygulamanın adını gösterir. Ana pencere, Dock simgesi, otomatik başlatma veya ayrı ayarlar penceresi yoktur. Çıkışta paneller kapatılır, bekleyen sarma bitiş komutları gönderilir ve XPC bağlantısı kapatılır.

Bildirimleri kapatmak görünen kartı hemen gizler ve bekleyen kartları iptal eder. Yeniden açıldığında yalnızca sonraki parça değişimleri duyurulur. Touch Bar’ı kapatmak mevcut sarmayı sonlandırır ve sistemin normal Touch Bar görünümünü geri getirir; yeniden açmak paneli tekrar gösterir. İki seçenek birbirinden bağımsızdır.

## Yapı

- `MediaBar/TouchBarView.swift`: Tasarımın tamamı; ölçüler, renkler, düğmeler, kayan metin, ilerleme çizimi ve geniş sarma ekranı. Arayüz değişiklikleri bu dosyada yapılır.
- `MediaBar/MediaController.swift`: Medya durumu, eylemler, süre yenilemesi ve favori isteklerinin yönetimi. Arayüz ile `MediaState` / `MediaAction` üzerinden konuşur.
- `MediaBar/TouchBarPresenter.swift` ve `MediaBar/Native/TouchBarSystem.m`: Sistem genelinde Touch Bar sunumu ve uygulama/masaüstü/uyanma bildirimleri.
- `MediaService`: MediaRemote’a doğrudan erişen Objective-C XPC servisi. Xcode tarafından derlenir ve uygulamanın `Contents/XPCServices` dizinine gömülür. Durum 0,5 saniyede bir alınır; süre gösterimi güncellemeler arasında yerel olarak ilerler.
- `MediaBar/Native/MusicAutomation.m`: Music’e doğrudan Apple Events gönderir. AppleScript, Perl, shell veya başka bir yorumlayıcı kullanmaz. Favorileri 5 saniyede bir okur; düğme sadece favorilere ekler, kaldırmaz.

Önceki/sonraki kontrolleri Podcasts’te 15 saniye geri/ileri çalışır. Uzun basmak sarma başlatır; bırakmak, bağlam değişimi veya 15 saniyelik güvenlik sınırı sarmayı bitirir. Süre alanına dokunmak geniş sarma ekranını açar; sürükleme bitince konum gönderilir. Süre alanına yeniden dokunmak normal görünüme döner. Şarkı adına dokunmak Music’i açmak yerine Touch Bar işlem görünümüne geçer: **favori → şarkı/sanatçı bilgisi → şarkı karaliste düğmesi → sanatçı karaliste düğmesi**. Şarkı adına tekrar dokunmak ana görünüme döner. Favori yalnızca bu görünümde ve Music için gösterilir. Karaliste düğmeleri tekrar dokununca kaydı kaldırır; engelli durum pembe renk ve metinle belirtilir. Sanatçı eylemi gerçek sanatçı dizisinin ilk ismini, dizi yoksa bölünmemiş sanatçı metnini kullanır. Ekleme/kaldırma mevcut parçayı atlatmaz. Parça değişiminde veya Touch Bar kapatıldığında işlem görünümü kapanır. Medya yoksa kontroller devre dışı kalır; süre bilgisi yoksa zaman alanı gizlenir.

## Karaliste ve otomatik atlama

**Karalisteye ekle** menüsünden mevcut şarkıyı (başlık + sanatçı metni) veya sanatçıyı kaydedebilirsiniz. Ekleme mevcut parçayı atlatmaz; aynı şarkı üzerinden birden fazla sanatçı eklenebilir. Zaten ekli seçenekler işaretli ve devre dışıdır. **Karalisteyi yönet** alt menüsünde bir kaydı seçmek onu kaldırır. Menü açıkken parça değişirse seçtiğiniz kayıt, menüde gösterilen parçaya ait kalır.

Sanatçı metni `&`, virgül veya `feat.` gibi işaretlerden bölünmez. `A&B&C` yalnızca aynı metinle eşleşir; `B&A&C` veya tek başına `B` eşleşmez. Büyük/küçük harf ve metnin başındaki/sonundaki boşluklar yok sayılır; iç boşluklar, noktalama ve sıralama korunur. Kaynak sanatçı alanını gerçek bir isim dizisi olarak verirse her sanatçı ayrı eklenebilir; bireysel engel dizideki o isimle veya tam eşleşen solo sanatçı metniyle eşleşir. Mevcut MediaRemote kaynağı çoğunlukla tek bir sanatçı metni sağlar. Menüde adlar **Şarkı** ve **Sanatçılar** bölüm başlıkları altında gösterilir. Albüm adı sanatçı bilgisi yerine engellemede kullanılmaz.

Liste ilk eklemede `~/Library/Application Support/MediaBar/blacklist.json` konumuna atomik kaydedilir:

```json
{
  "version": 1,
  "artists": [{ "name": "A&B&C", "match": "fullText" }],
  "songs": [{ "title": "Şarkı adı", "artistText": "A&B&C" }]
}
```

Ayrı sanatçı kayıtlarının `match` değeri `individual` olur. Menü her açıldığında dosya yeniden okunur; elle düzenlemeler sonraki açılışta veya menü açılınca yüklenir. Bozuk veya desteklenmeyen sürümdeki dosya üzerine yazılmaz; menüde hata gösterilir ve otomatik filtre uygulanmaz. Yazma hatası kaydedilmemiş kaydı belleğe eklemez.

Filtre yalnızca yeni bir parça çalmaya başladığında değerlendirilir. Uygulama açılırken zaten çalan parça, listeyi düzenlemek ve otomatik atlamayı yeniden açmak mevcut parçayı atlatmaz. Engelli yeni parçaya tek bir sonraki-parça komutu gönderilir ve o parçanın bildirimi gösterilmez. Komut başarısızsa aynı parçada tekrar tekrar denenmez. Art arda en fazla 10 parça atlanır; izinli bir parça, 30 saniyeden uzun bir ara veya seçeneği kapatıp açmak sınırı sıfırlar. Eşleşmeler yapay zekâ tespiti yapmaz; yalnızca kaydettiğiniz listeyi uygular.

## Parça bildirim paneli

Yeni bir parça çalmaya başladığında ekranın üst ortasından bağımsız, koyu bir kart açılır; ekranın üstüne bağlanan siyah bir şerit yoktur. Şarkı adı, sanatçı ve varsa albüm adı gösterilir. Oynatıcı kapak verisi sağlıyorsa kapak, aksi halde dalga simgesi kullanılır. Sesli uyarı yoktur. Panel yaklaşık 3 saniye görünür, sonra yukarı kapanır. Aktif uygulamanın ekranı kullanılır; çentikli ekranlarda metin çentiğin altında konumlandırılır.

Kapak, MediaRemote’un `artworkData` alanından alınır; ağdan indirilmez. XPC servisi ImageIO ile en fazla 160 piksel boyutunda bir PNG üretip aynı parça için önbellekte tutar. Sonradan gelen kapak veya albüm bilgisi açık kartta güncellenir; yeni bildirim açılmaz ve görünme süresi uzatılmaz.

`TrackNotificationPresenter.swift` odağı almayan ve tıklamaları engellemeyen bir `NSPanel` kullanır. Tüm Spaces ve diğer uygulamaların tam ekran alanlarına katılması için pencere davranışları ayarlanmıştır. Görsel tasarım `TrackNotificationView.swift` içindedir. Fiziksel tam ekran davranışı kullanıcı tarafından doğrulanmalıdır.

Başlangıçta zaten çalan parça, duraklat/devam et ve aynı parçaya yeniden bağlanma tekrar duyurulmaz. Hızlı değişimlerde son parça gösterilir; bildirim kuyruğu birikmez. Uyku, kilit ve ekran düzeni değişiminde panel kapatılır. Sistem bildirim izni istenmez ve Music’in kendi bildirim ayarları değiştirilmez; iki bildirim istemiyorsanız Music bildirimlerini Sistem Ayarları’ndan kapatabilirsiniz.

## Yerel sistem erişimi

MediaRemote’un macOS 15.4 sonrasındaki erişim denetimi nedeniyle servis kimliği `com.apple.sezerbudak.MediaBar.MediaService` olarak ayarlanmıştır. Ana uygulamanın kimliği `com.sezerbudak.MediaBar` olarak kalır. Bu yaklaşım [mediaremote-adapter’ın belgelenmiş kimlik denetimi davranışına](https://github.com/ungive/mediaremote-adapter#why-this-works) dayanır. Servis Apple tarafından sağlanan veya imzalanan bir bileşen değildir; bu projede yerel olarak derlenir.

Touch Bar sunumu da özel macOS API’lerini kullanır. Derleme ve paket doğrulaması, bu özel API’lerin cihaz üzerindeki çalışma doğrulaması değildir. Eksik semboller veya bağlantı hataları uygulamayı çökertmeden sistem günlüğüne yazılır; medya kontrolleri boş/devre dışı duruma döner. Betik tabanlı yedek yol yoktur.

App Sandbox kapalıdır. Music’in favori özelliği ilk kullanımda macOS otomasyon izni gerektirebilir. Uygulama paketi izin açıklamasını ve Apple Events yetkisini içerir. Yayınlama, dağıtım veya açılış kaydı yapılmaz.

MediaRemote özel API bildirimleri `ungive/mediaremote-adapter` projesinin `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` sürümünden alınmıştır. BSD-3-Clause lisansı `MediaBar/Resources/MediaRemoteAdapter-LICENSE.txt` içinde tutulur ve uygulamaya kopyalanır. Eski TouchBar projesi değiştirilmez.

## Uygulamayı açmadan doğrulama

Uygulama simgesinin PNG boyutları ve menü çubuğunun tek renkli vektör PDF simgesi `Assets.xcassets` içinde bulunur. Tasarımın Swift/CoreGraphics kaynağı `Tools/GenerateIcons.swift` dosyasıdır. Yeniden üretmek için `xcrun swift -module-cache-path build/ModuleCache Tools/GenerateIcons.swift` kullanılabilir; bu işlem uygulamayı açmaz.

```sh
xcodebuild -project MediaBar.xcodeproj -scheme MediaBar -configuration Debug -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build
xcodebuild -project MediaBar.xcodeproj -scheme MediaBar -configuration Release -derivedDataPath build/Verification CODE_SIGN_IDENTITY=- build

xcrun swiftc -module-cache-path build/ModuleCache MediaBar/Models/*.swift Tests/main.swift -o build/MediaBarModelTests
build/MediaBarModelTests
```

Model testleri Foundation kullanır; MediaBar’ı veya XPC servisini başlatmaz, Touch Bar oluşturmaz ve Music’e erişmez. Süre/oynatma hızı, geçersiz veriler, sarma sınırları, oynatıcı/parça kimliği ve favori isteklerinin gecikmiş sonuçları kontrol edilir.

Fiziksel Touch Bar görünümü, Music/Podcasts ve diğer sistem oynatıcılarının verisi, otomasyon izni, uygulama geçişi/uyanma sonrası panel ve Quit sonrası eski Touch Bar’a dönüş kullanıcı tarafından doğrulanmalıdır. Geliştirme sırasında uygulama veya önizleme açılmaz.
