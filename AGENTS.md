# MediaBar çalışma kuralları

- Uygulamayı çalıştırma; Touch Bar paneli, pencere veya önizleme açarak test yapma.
- Derleme ve uygulamayı açmayan, sistem medyasına erişmeyen mantık testleri yapılabilir.
- Dosya değişikliklerinde Python kullanma.
- Otomatik commit oluşturma. Kullanıcı commit isterse Conventional Commits kullan.
- Touch Bar tasarımı ve görsel etkileşimleri yalnızca `MediaBar/TouchBarView.swift` içinde tut. Medya erişimini ve sistem paneli sunumunu bu dosyaya ekleme.
- Menü çubuğu menüsünde `MediaBar` başlığı, `Bildirimler`, `Touch Bar` ve `Otomatik atlama` için işaretli aç/kapat seçenekleri, `Karalisteye ekle`, `Karalisteyi yönet` ve `Quit` olsun. Seçimler UserDefaults ile kaydedilsin; ilk kullanımda üç seçenek de açık olsun. Ana pencere, Dock simgesi, ayrı ayarlar penceresi veya otomatik başlatma ekleme. Parça değişiminde kamera hizasından açılan, odağı almayan geçici bildirim paneli kullanılabilir.
- Karaliste `~/Library/Application Support/MediaBar/blacklist.json` dosyasında atomik kaydedilsin. Ekleme mevcut parçayı atlatmasın; filtre yeni parça çalmaya başladığında çalışsın. Sanatçı metnini bölme veya sıralama; yalnızca kaynak gerçek bir sanatçı dizisi sağlarsa ayrı sanatçı seçenekleri sun. Eşleşmede büyük/küçük harf ve dış boşluklar dışında metni koru. Sonsuz atlama döngüsü ve aynı parçaya tekrar komut gönderilmesini engelle.
- Menü çubuğu simgesinin araç ipucu `MediaBar` olarak kalsın.
- Touch Bar’da şarkı adına dokunmak Music’i açmasın; favori, şarkı/sanatçı bilgisi ve iki karaliste düğmesini içeren işlem görünümünü açsın. Aynı alana tekrar dokunmak ana görünüme dönsün. Favori yalnızca işlem görünümünde bulunsun. Karaliste düğmeleri aynı kaydı ekleyip kaldırabilsin; sanatçı düğmesi gerçek dizinin ilk sanatçısını, dizi yoksa tam sanatçı metnini kullansın.
- Yalnızca kullanıcının mevcut Mac’i hedefleniyor. Yayınlama ve dağıtım altyapısı ekleme.
- Swift, Objective-C ve C tercih et; çalışma zamanında Perl, shell, AppleScript veya Python betikleri kullanma.
- Referans `/Users/sezerbudak/Developer/personal/TouchBar` projesini değiştirme.
