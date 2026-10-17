# PRD Master — D’lice (Backlog Terkonsolidasi)

**Status:** Acuan pekerjaan lanjutan yang disetujui; kebutuhan tambahan dari diskusi 18 Oktober 2026 digabungkan.  
**Repository:** https://github.com/dlice8888/dlice-landing-page  
**Website produksi:** https://dlice.vercel.app/  
**Baseline kode yang diperiksa sebelumnya:** `main` — `52564183aada7cd7cd20e25758bdf961aa1905f1`  
**Dokumen ini:** Memuat keputusan dan backlog yang diketahui. Status implementasi harus diverifikasi pada kode produksi dan layanan aktif; penulisan PRD tidak berarti fitur sudah diterapkan.

## 1. Temuan rekonsiliasi dan baseline

### Sudah tersedia pada kode landing page yang diaudit — jangan dibuat ulang tanpa alasan
- Landing page responsif dengan hero, katalog menu, cerita/kemasan, lokasi, dan footer.
- Aset logo serta foto menu/kemasan yang dirujuk dari repository.
- Pemilihan beberapa menu sekaligus beserta jumlahnya.
- Form memuat nama, tanggal, rentang waktu, metode penerimaan, alamat delivery bersyarat, catatan, dan ringkasan pesanan.
- Pesan order dibangun di browser dan diteruskan ke WhatsApp.
- Tautan Google Maps dan QR website beserta tombol unduh.
- Bagian “Belum yakin menu?” sudah dihapus pada commit `52564183aada7cd7cd20e25758bdf961aa1905f1`.

### Batasan audit sebelumnya
- Vercel pernah menunjukkan deployment produksi `READY`, domain `dlice.vercel.app`, dan commit yang sama dengan `main` pada saat audit.
- Repository yang diperiksa berupa landing page statis satu file HTML; alur order saat itu membangun pesan WhatsApp di browser.
- Supabase project `dlice-production`, region Singapore (`ap-southeast-1`), ref `gdjlkrmlsurcdbwnmqgg`, status saat audit `ACTIVE_HEALTHY`.
- Dua migration awal dan skema tabel privat dengan RLS sudah tercatat. Akses `anon`/`authenticated` ke tabel operasional dicabut; operasi aplikasi harus lewat backend tepercaya.
- URL project dan publishable key pernah dikonfigurasi sebagai environment variables Vercel untuk Production, Preview, dan Development. Konfigurasi environment tidak membuktikan frontend/backend sudah terintegrasi.
- Pada audit sebelumnya belum ada data produk, harga, kapasitas, admin, atau pesanan yang dimasukkan. Belum ada API/Edge Function pemesanan, upload bukti, panel admin, atau integrasi frontend end-to-end yang terverifikasi.
- RLS tanpa policy pada tabel privat disengaja untuk menolak akses langsung dari client pada tahap awal. Backend harus menggunakan jalur server-side tepercaya dan diuji ulang keamanannya.
- Jangan mengasumsikan kondisi historis tersebut masih sama: audit ulang branch, commit, database, fungsi, environment, dan deployment sebelum implementasi.

## 2. Tujuan produk
Mengubah formulir pemesanan saat ini menjadi alur penjualan yang konsisten dari pilihan menu, simulasi total, konfirmasi struk, pembayaran manual, verifikasi admin, status operasional, pelacakan pelanggan, dan notifikasi WhatsApp—dengan data persisten serta validasi server-side.

## 3. Pengalaman pelanggan: pemilihan menu, total langsung, dan konfirmasi struk

### 3.1 Kalkulasi langsung saat kuantitas berubah
- Total simulasi harus langsung terlihat setelah pelanggan memilih menu dan mengisi/mengubah jumlah; pelanggan tidak perlu menekan tombol “Buat Pesanan” untuk mengetahui total.
- Setiap perubahan kuantitas, penambahan/penghapusan menu, atau perubahan pilihan yang memengaruhi harga harus langsung memperbarui subtotal per item, total produk, dan ringkasan di seluruh komponen yang relevan.
- Perhitungan UI harus reaktif dan tidak bergantung pada nilai lama yang hanya diperbarui saat submit.
- Harga satuan harus berasal dari data produk yang aktif. Server menghitung ulang harga dan total saat membuat/memperbarui pesanan; jangan mempercayai total yang dikirim browser.
- Jika total berubah setelah struk dikonfirmasi, konfirmasi sebelumnya menjadi tidak berlaku dan pelanggan harus melihat serta menyetujui struk versi terbaru sebelum melanjutkan pembayaran.
- Tampilkan dengan jelas bahwa simulasi total adalah harga produk. Ongkos delivery dari pihak ketiga tidak termasuk total pembayaran produk ke D’lice.

### 3.2 Pop-up struk sebelum pembayaran
- Sebelum pelanggan menuju langkah pembayaran, tampilkan modal/pop-up berbentuk struk yang mudah dibaca dan cocok untuk ponsel.
- Struk mencakup ID/nomor order, nama dan nomor WhatsApp pelanggan, setiap nama menu, jumlah, harga satuan, subtotal item, total harga produk, tanggal/waktu yang diminta, metode penerimaan, alamat jika delivery, catatan, dan versi/waktu ringkasan.
- Pelanggan harus secara eksplisit mengonfirmasi bahwa rincian dan total benar sebelum melanjutkan.
- Jika pelanggan menutup/membatalkan pop-up, jangan lanjutkan ke pembayaran seolah-olah sudah disetujui.
- Jika kuantitas/menu atau detail yang memengaruhi pesanan diubah setelah konfirmasi, tandai struk lama sebagai kedaluwarsa, hitung ulang, lalu tampilkan struk versi baru untuk dikonfirmasi lagi.
- Pesanan dan pembayaran harus merujuk ke snapshot versi struk yang sama. Jangan izinkan bukti pembayaran terikat pada total atau rincian yang sudah tidak berlaku.
- Simpan riwayat perubahan/snapshot penting agar admin dapat mengetahui rincian mana yang dikonfirmasi pelanggan.

### 3.3 Tombol akhir dan WhatsApp admin
- Setelah pelanggan mengonfirmasi struk dan menyelesaikan langkah-langkah yang diperlukan, tombol aksi paling bawah mengirim/membuka WhatsApp admin dengan satu pesan order yang telah dirangkai otomatis.
- Pesan memuat ID order, nama dan nomor pelanggan, rincian semua menu dan kuantitas, harga satuan/subtotal, total produk, metode pembayaran yang dipilih, tanggal/waktu, metode penerimaan, alamat jika delivery, catatan, serta status bukti pembayaran (jika sudah diunggah).
- Gunakan ID order yang sama dengan database, struk, pembayaran, dan panel admin.
- Pesan WhatsApp adalah notifikasi/kanal komunikasi, bukan sumber kebenaran transaksi. Kegagalan membuka WhatsApp tidak boleh menghapus order yang sudah tersimpan.
- Hindari membuat pesanan duplikat saat pelanggan menekan tombol berkali-kali atau membuka ulang WhatsApp; gunakan operasi server-side yang idempoten.

## 4. Identitas dan data pesanan
- Nomor WhatsApp pelanggan wajib diisi dan divalidasi.
- Buat pencatatan pesanan persisten, bukan hanya teks pesan yang dibuka di WhatsApp.
- Simpan snapshot nama menu, jumlah, harga satuan, subtotal, total harga produk, versi struk yang disetujui, tanggal/waktu yang diminta, metode penerimaan, alamat jika delivery, catatan, metode pembayaran, dan waktu pembuatan/pembaruan.
- ID order/transaksi harus unik dan konsisten pada UI pelanggan, struk, database, bukti pembayaran, admin, dan WhatsApp.
- Format ID yang diminta: `DLC-dd/mm/yyyy-xxxxx` (contoh ilustratif: `DLC-18/10/2026-00001`). Implementasi harus menjamin keunikan dan menghindari race condition; tetapkan secara konsisten bagaimana tanggal dan urutan dibuat.
- Validasi harga, jumlah, tanggal, ketersediaan, total, perubahan versi struk, dan hak akses di server.

## 5. Pembayaran manual

Metode yang disepakati hanya:
- Transfer bank.
- QRIS D’lice.

Cash tidak digunakan. Jangan menambahkan gateway atau metode lain tanpa keputusan baru dari Owner.

### 5.1 Pengaturan pembayaran di akun Owner
- Sediakan bagian pengaturan pembayaran khusus Owner.
- Owner dapat mengisi dan memperbarui nama bank, nama pemilik rekening, nomor rekening, serta petunjuk transfer yang diperlukan.
- Owner dapat mengunggah/mengganti gambar QRIS dan melihat pratinjau sebelum menyimpan.
- Perubahan data rekening atau QRIS harus tersimpan persisten dan ditampilkan pada checkout pelanggan sesuai metode yang dipilih.
- Jika pelanggan memilih transfer bank, tampilkan detail rekening terbaru yang aktif. Jika pelanggan memilih QRIS, tampilkan gambar QRIS terbaru yang aktif.
- Hanya Owner yang boleh mengubah/mengunggah informasi rekening dan QRIS; staf admin biasa tidak boleh mengubahnya kecuali izin eksplisit ditambahkan kemudian.
- Gunakan penyimpanan file yang aman, validasi tipe/ukuran berkas, dan akses publik hanya untuk aset QRIS yang memang dimaksudkan untuk dilihat pelanggan. Jangan simpan rahasia di frontend.
- Simpan snapshot metode dan instruksi pembayaran yang dipakai pada saat order dibuat/dikonfirmasi, atau versi konfigurasi pembayaran yang bisa diaudit, sehingga perubahan pengaturan Owner tidak mengubah diam-diam instruksi transaksi lama.
- Jika detail pembayaran berubah saat checkout berlangsung, tampilkan instruksi aktif yang terbaru sebelum pelanggan membayar dan pastikan order menyimpan versi yang sesuai.

### 5.2 Bukti dan verifikasi
- Pelanggan wajib mengunggah bukti pembayaran untuk alur pembayaran manual.
- Upload bukti tidak otomatis menandai pembayaran lunas.
- Admin memeriksa transaksi melalui sumber tepercaya lalu menetapkan hasil verifikasi.
- Status pembayaran: `unpaid`, `pending_verification`, `paid`, `rejected`, dan `refunded`. Gunakan `refunded` hanya setelah pengembalian dana benar-benar diproses.
- Catat admin, waktu, metode, referensi yang relevan, bukti, dan riwayat perubahan status.
- Upload ulang bukti harus memperbarui/menambah bukti untuk pembayaran yang sama sesuai desain audit; jangan menciptakan record pembayaran duplikat hanya karena pelanggan memperbaiki unggahan.
- Pembayaran, snapshot struk, reservasi, dan order harus konsisten saat ada percobaan ulang, keterlambatan, atau event duplikat.

## 6. Batas pemesanan dan kapasitas
- Zona waktu operasional: `Asia/Makassar` (WITA).
- Batas pemesanan untuk hari yang sama: pukul 18.00 WITA.
- Terapkan kapasitas per produk dan tanggal serta cegah overbooking ketika checkout berlangsung bersamaan.
- Reservasi checkout berlangsung 15 menit.
- Jika pelanggan menyatakan sudah membayar atau mengirim bukti sebelum 15 menit berakhir, tahan kapasitas sampai admin menyelesaikan verifikasi.
- Jika tidak ada pernyataan pembayaran maupun bukti dalam 15 menit, lepaskan reservasi.
- Jika pembayaran terlambat atau kapasitas telah penuh saat verifikasi, arahkan kasus ke admin untuk penyelesaian sesuai kebijakan.
- Pisahkan status reservasi, pembayaran, dan operasional pesanan. Catat waktu reservasi, kedaluwarsa, penahanan lanjutan, dan pelepasan.
- Informasi kapasitas publik hanya menampilkan ketersediaan yang aman; jangan membuka data pelanggan.

## 7. Panel staf admin, konfirmasi pembayaran, dan komunikasi pelanggan

### 7.1 Verifikasi dan konfirmasi pembayaran
- Staf admin yang memiliki izin dapat melihat pesanan dan bukti pembayaran serta menerima/menolak hasil verifikasi berdasarkan pemeriksaan yang sah.
- Setelah pembayaran terverifikasi, sistem wajib menyediakan konfirmasi kepada pelanggan yang berisi status pembayaran, nomor order, jumlah yang diterima, metode pembayaran, waktu verifikasi, dan ringkasan pesanan.
- Konfirmasi pembayaran kepada pelanggan harus menyertakan panduan cara memeriksa progress order melalui halaman pelacakan D’lice, dengan pengalaman/status yang familiar seperti aplikasi ojek online atau perusahaan logistik.
- Sertakan tautan/kode pelacakan unik yang sulit ditebak, langkah singkat membuka tautan atau memasukkan kode, dan arti status pesanan yang relevan.
- Konfirmasi harus disiapkan/dikirim sebelum staf melanjutkan perubahan status operasional ke tahap berikutnya. Jika pengiriman gagal, catat kegagalan dan sediakan retry; jangan mengubah pembayaran menjadi tidak valid hanya karena notifikasi gagal.
- Simpan status notifikasi dan waktu/aktor yang mengirim. Retry harus idempoten agar pelanggan tidak menerima duplikat yang tidak perlu.
- Jangan mengirim WhatsApp otomatis untuk setiap perubahan status operasional kecuali disetujui kemudian; persyaratan yang ada adalah satu konfirmasi setelah pembayaran terverifikasi, berisi instruksi tracking.

### 7.2 Peran dan hak akses
- Peran yang direncanakan: `owner` dan `sales_admin`/staf admin.
- Owner memiliki akses penuh, termasuk pengaturan rekening dan QRIS serta manajemen akun staf.
- Staf hanya dapat melakukan tindakan operasional sesuai izin; staf tidak boleh mengubah pengaturan pembayaran Owner.
- Terapkan otorisasi di server/database, bukan hanya dengan menyembunyikan elemen antarmuka.
- Simpan audit log untuk tindakan administratif penting, termasuk verifikasi pembayaran, perubahan status, perubahan pengaturan pembayaran, dan pengelolaan akun.

## 8. Status pesanan dan pelacakan
Status operasional dipisahkan dari status pembayaran:
- `received`
- `confirmed`
- `preparing`
- `ready_for_pickup`
- `waiting_for_courier`
- `in_delivery`
- `completed`
- `cancelled`
- `delivery_issue`

- Setiap perubahan mencatat waktu dan aktor.
- Pelacakan pelanggan memakai kode/tautan unik yang sulit ditebak dan hanya menampilkan informasi minimum untuk order miliknya.
- Halaman pelacakan menunjukkan nomor order, ringkasan status, waktu pembaruan terakhir, dan urutan tahap yang sudah/akan dilalui dengan bahasa sederhana.
- Tidak diperlukan pelacakan GPS langsung.
- Jangan izinkan staf melompati tahapan tanpa validasi/otorisasi dan pencatatan alasan bila diperlukan.

## 9. Aturan delivery
- Pelanggan dapat memesan ojek online sendiri atau meminta D’lice membantu memesankannya.
- Jika D’lice membantu pemesanan, ongkos dibayar pelanggan langsung kepada pengemudi/penyedia layanan.
- Ongkos delivery terpisah dari harga produk dan tidak termasuk total pembayaran produk kepada D’lice.
- Jangan menjanjikan tarif tetap sebelum tarif aktual diketahui.
- Alamat delivery wajib diisi; status pengantaran terpisah dari status pembayaran.

## 10. WhatsApp setelah pembayaran
- Pertahankan notifikasi order awal yang sudah ada dan lengkapi dengan nomor order, nomor pelanggan, rincian item, harga, tanggal/waktu, metode penerimaan, alamat jika delivery, catatan, metode pembayaran, dan status bukti.
- Kirim satu konfirmasi setelah pembayaran terverifikasi, termasuk petunjuk tracking seperti dijelaskan di bagian 7.
- Jangan mengirim pesan otomatis untuk setiap perubahan status operasional.
- Sediakan pencatatan hasil pengiriman dan retry idempoten.
- Kegagalan notifikasi tidak boleh membatalkan atau menghilangkan order.
- Pesan WhatsApp ke admin dan konfirmasi WhatsApp ke pelanggan merupakan dua pesan dengan penerima dan tujuan berbeda; keduanya harus menggunakan nomor order yang sama.

## 11. Ulasan Google Maps
- Jika akses resmi dan ketentuan penggunaan memungkinkan, tampilkan carousel ulasan yang bergerak ke kiri dan hanya berisi ulasan bintang lima.
- Verifikasi sumber data, izin penggunaan, ketersediaan API, dan batas teknis sebelum implementasi. Jangan mengandalkan scraping yang tidak diizinkan.

## 12. Audit teknis wajib sebelum implementasi
1. Periksa repository, branch `main`, commit terbaru, dan deployment produksi aktual.
2. Cocokkan skema tabel, migrasi, kebijakan RLS, Storage, dan Edge Functions Supabase dengan PRD.
3. Periksa apakah ada implementasi backend di luar repository dan tentukan sumber data order yang menjadi acuan.
4. Pastikan secret tidak terekspos di frontend dan semua operasi penting divalidasi server-side.
5. Jangan membuat ulang tabel/fungsi yang sudah ada tanpa audit.
6. Pastikan data produk/harga, setting pembayaran Owner, order, bukti, role, dan tracking memiliki relasi serta aturan akses yang benar.
7. Uji alur end-to-end dari perubahan kuantitas sampai pembayaran, notifikasi, dan pelacakan.
8. Periksa keamanan upload bukti dan QRIS, idempotensi, race condition, akses lintas pelanggan, dan audit log.

## 13. Kriteria penerimaan
- Total simulasi berubah segera setiap kali menu/kuantitas berubah tanpa perlu submit.
- Struk konfirmasi menunjukkan rincian dan total terkini; perubahan setelah konfirmasi mewajibkan konfirmasi struk versi baru.
- Harga yang tersimpan dan dibayar cocok dengan snapshot struk yang disetujui, serta divalidasi ulang di server.
- Order persisten memiliki ID DLC yang sama di struk, database, pembayaran, panel admin, tracking, dan WhatsApp.
- Tombol akhir mengirim pesan WhatsApp admin dengan seluruh detail penting dan tidak menggandakan order.
- Owner dapat mengubah nomor rekening dan mengunggah/mengganti QRIS; checkout menampilkan instruksi sesuai metode pembayaran yang dipilih.
- Pengaturan pembayaran hanya dapat diubah oleh Owner dan riwayat/versinya dapat diaudit.
- Bukti pembayaran wajib, tetapi tidak otomatis menandai lunas.
- Setelah pembayaran terverifikasi, pelanggan menerima konfirmasi pembayaran beserta tutorial tracking sebelum proses operasional diteruskan.
- Reservasi 15 menit, penahanan setelah pernyataan/bukti sebelum tenggat, pelepasan reservasi, dan kasus pembayaran terlambat berjalan konsisten.
- Kapasitas tidak terlampaui pada checkout bersamaan.
- Status pembayaran dan status operasional terpisah.
- Pelanggan hanya dapat melihat tracking order yang berhak diakses.
- Admin dapat mengelola status sesuai izin dengan audit trail.
- Kasus kapasitas penuh, pembayaran terlambat, pembatalan, refund, notifikasi gagal, dan retry telah diuji.
- Tidak ada data pelanggan, token tracking, atau secret yang terbuka untuk publik.

## 14. Skenario QA minimum
- Mengubah kuantitas dari bagian atas form memperbarui total di semua bagian terkait.
- Mengubah kuantitas setelah struk muncul membatalkan persetujuan lama dan memunculkan struk terbaru.
- Mengirim pembayaran/bukti untuk snapshot struk yang sudah usang ditolak atau diarahkan ke konfirmasi ulang.
- Checkout bersamaan untuk kapasitas produk/tanggal yang hampir penuh.
- Reservasi kedaluwarsa tanpa aktivitas pembayaran.
- Pelanggan menyatakan/mengirim bukti sebelum 15 menit, lalu admin memverifikasi sesudahnya.
- Pembayaran terlambat ketika kapasitas sudah penuh.
- Bukti tidak valid, ditolak, upload ulang, serta refund yang belum/sudah diproses.
- Mengubah rekening atau QRIS sebagai Owner dan memverifikasi pilihan metode yang dilihat pelanggan.
- Staf mencoba mengubah rekening/QRIS dan harus ditolak.
- WhatsApp admin/pelanggan gagal lalu dicoba ulang tanpa order/notifikasi duplikat.
- Pelanggan mencoba mengakses tracking milik pelanggan lain.
- Hak akses staf dibandingkan dengan Owner.
- Pemesanan melewati batas pukul 18.00 WITA pada hari yang sama.

## 15. Batas perubahan
Dokumen ini adalah backlog dan kontrak kebutuhan. Menambahkan persyaratan ke PRD tidak berarti kode aplikasi, skema Supabase, atau deployment telah berubah. Setiap implementasi harus mengikuti audit baseline, perubahan sekecil yang diperlukan, pengujian, serta verifikasi produksi.
