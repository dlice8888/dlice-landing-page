# PRD Master — D’lice (Sisa Pekerjaan Setelah Audit)

**Status:** Disetujui untuk menjadi acuan pekerjaan lanjutan  
**Repository:** https://github.com/dlice8888/dlice-landing-page  
**Website produksi:** https://dlice.vercel.app/  
**Baseline kode yang diperiksa:** `main` — `52564183aada7cd7cd20e25758bdf961aa1905f1`  
**Batas dokumen:** Hanya kebutuhan yang belum terbukti diimplementasikan pada kode produksi atau yang masih memerlukan keputusan/akses teknis. Fitur yang sudah tersedia tidak dicantumkan sebagai pekerjaan baru.

## 1. Temuan rekonsiliasi

### Sudah tersedia pada kode produksi — bukan pekerjaan baru
- Landing page responsif dengan bagian hero, katalog menu, cerita/kemasan, lokasi, dan footer.
- Aset logo serta foto menu/kemasan yang dirujuk dari file gambar repository.
- Pemilihan beberapa menu sekaligus beserta jumlahnya pada form.
- Form saat ini sudah memuat nama, tanggal, rentang waktu, metode penerimaan, alamat delivery bersyarat, catatan, dan ringkasan pesanan.
- Pesan pesanan disusun dan diteruskan ke WhatsApp.
- Tautan Google Maps dan QR website beserta tombol unduh.
- Bagian “Belum yakin menu?” sudah dihapus pada commit `52564183aada7cd7cd20e25758bdf961aa1905f1`; tidak perlu dikerjakan ulang.

### Batasan hasil audit
- Vercel menunjukkan deployment produksi berstatus `READY`, domain `dlice.vercel.app`, dan commit Git yang sama dengan commit terbaru di `main`. Artinya deployment yang terdaftar mengarah ke perubahan terbaru tersebut.
- Repository yang diperiksa tampak berupa landing page statis satu file HTML; alur pemesanan yang terlihat membangun pesan WhatsApp di browser.
- Koneksi Supabase yang tersedia untuk audit tidak menampilkan project apa pun. Karena itu, status database Supabase, skema, RLS, Storage, dan Edge Functions belum dapat diverifikasi. Jangan menganggap komponen tersebut sudah tersedia sebelum project Supabase yang benar dapat diakses.
- Audit ini berbasis kode repository dan metadata deployment yang dapat diakses; bukan klaim bahwa seluruh alur bisnis backend sudah diuji end-to-end.

## 2. Tujuan lanjutan

Mengembangkan alur pemesanan dari form WhatsApp saat ini menjadi proses operasional yang dapat mencatat pesanan, mengelola kapasitas, memverifikasi pembayaran, serta memberi status pesanan secara aman—setelah audit Supabase dapat dilanjutkan.

## 3. Pekerjaan yang masih diperlukan

### 3.1 Identitas dan data pesanan
- Tambahkan nomor WhatsApp pelanggan sebagai field wajib.
- Buat pencatatan pesanan yang persisten, bukan hanya teks pesan yang dibuka di WhatsApp.
- Simpan snapshot nama menu, jumlah, harga satuan, subtotal, total harga produk, tanggal/waktu yang diminta, metode penerimaan, alamat jika delivery, catatan, dan waktu pembuatan pesanan.
- Validasi harga, jumlah, tanggal, ketersediaan, dan total di server.
- Tetapkan ID pesanan unik yang aman untuk digunakan admin dan pelanggan.

### 3.2 Batas pemesanan dan kapasitas
- Zona waktu operasional: `Asia/Makassar` (WITA).
- Batas pemesanan untuk hari yang sama: pukul 18.00 WITA.
- Terapkan kapasitas per produk dan tanggal serta cegah overbooking ketika checkout berlangsung bersamaan.
- Reservasi checkout berlangsung 15 menit.
- Jika pelanggan menyatakan sudah membayar atau mengirim bukti sebelum 15 menit berakhir, tahan kapasitas sampai admin menyelesaikan verifikasi.
- Jika tidak ada pernyataan pembayaran maupun bukti dalam 15 menit, lepaskan reservasi.
- Jika pembayaran terlambat atau kapasitas telah penuh saat verifikasi, arahkan kasus ke admin untuk penyelesaian sesuai kebijakan yang ditetapkan.
- Pisahkan status reservasi, pembayaran, dan operasional pesanan. Catat waktu reservasi, kedaluwarsa, penahanan lanjutan, dan pelepasan.
- Informasi kapasitas publik hanya menampilkan informasi ketersediaan yang aman; jangan membuka data pelanggan.

### 3.3 Pembayaran manual
Metode yang disepakati:
- Transfer bank.
- QRIS D’lice.

Persyaratan:
- Sediakan instruksi pembayaran yang dapat dikelola dan diverifikasi admin.
- Pelanggan dapat mengirim bukti pembayaran atau menyatakan pembayaran telah dilakukan.
- Bukti unggahan tidak otomatis menjadikan status pembayaran lunas.
- Admin memeriksa transaksi melalui sumber tepercaya lalu menetapkan hasil verifikasi.
- Status pembayaran: `unpaid`, `pending_verification`, `paid`, `rejected`, dan `refunded`. Gunakan `refunded` hanya setelah pengembalian dana benar-benar diproses.
- Catat admin, waktu, metode, referensi yang relevan, serta riwayat perubahan status.
- Pembayaran dan reservasi harus konsisten saat ada percobaan ulang, keterlambatan, atau event duplikat.

### 3.4 Panel admin dan akses
- Buat autentikasi admin dan pembatasan izin berbasis peran.
- Peran yang direncanakan: `sales_admin` dan `owner`.
- Admin dapat melihat pesanan, memverifikasi pembayaran, memperbarui status operasional, memeriksa kapasitas, dan melihat riwayat tindakan.
- Terapkan otorisasi di server/database, bukan hanya menyembunyikan elemen antarmuka.
- Simpan audit log untuk tindakan administratif penting.

### 3.5 Status pesanan dan pelacakan
Pisahkan status operasional dari pembayaran. Status operasional yang direncanakan:
- `received`
- `confirmed`
- `preparing`
- `ready_for_pickup`
- `waiting_for_courier`
- `in_delivery`
- `completed`
- `cancelled`
- `delivery_issue`

Setiap perubahan harus mencatat waktu dan aktor. Pelacakan pelanggan menggunakan kode/tautan unik yang sulit ditebak dan hanya menampilkan informasi minimum untuk pesanan miliknya. Tidak diperlukan pelacakan GPS langsung.

### 3.6 Aturan delivery
- Pelanggan dapat memesan ojek online sendiri atau meminta D’lice membantu memesankannya.
- Jika D’lice membantu pemesanan, ongkos dibayar pelanggan langsung kepada pengemudi/penyedia layanan.
- Ongkos delivery terpisah dari harga produk dan tidak termasuk total pembayaran produk kepada D’lice.
- Jangan menjanjikan tarif tetap sebelum tarif aktual diketahui.
- Alamat delivery wajib diisi; status pengantaran terpisah dari status pembayaran.

### 3.7 WhatsApp setelah pembayaran
- Pertahankan pesan WhatsApp awal yang sudah ada dan lengkapi agar mencantumkan nomor pesanan, nomor pelanggan, rincian item, tanggal/waktu, metode penerimaan, alamat jika delivery, dan catatan.
- Kirim satu konfirmasi WhatsApp setelah pembayaran terverifikasi.
- Jangan mengirim pesan otomatis untuk setiap perubahan status operasional.
- Sediakan pencatatan hasil pengiriman dan retry yang idempoten agar tidak menghasilkan pesan duplikat.
- Kegagalan notifikasi tidak boleh membatalkan atau menghilangkan pesanan.

### 3.8 Ulasan Google Maps
- Jika akses resmi dan ketentuan penggunaan memungkinkan, tampilkan carousel ulasan yang bergerak ke kiri dan hanya berisi ulasan 5 bintang.
- Verifikasi sumber data, izin penggunaan, ketersediaan API, dan batas teknis sebelum implementasi. Jangan mengandalkan scraping yang tidak diizinkan.

## 4. Audit teknis wajib sebelum implementasi backend

1. Dapatkan akses ke project Supabase D’lice yang benar.
2. Cocokkan skema tabel, migrasi, kebijakan RLS, Storage, dan Edge Functions dengan kebutuhan pada dokumen ini.
3. Periksa apakah ada implementasi backend di luar repository yang terlihat dan tentukan sumber data pesanan yang menjadi acuan.
4. Pastikan secret tidak terekspos di frontend dan semua operasi penting divalidasi server-side.
5. Pilih rancangan integrasi yang paling kecil risikonya berdasarkan keadaan nyata repository dan Supabase; jangan membuat ulang tabel atau fungsi yang sudah ada tanpa audit.
6. Setelah perubahan, verifikasi dengan pengujian nyata dan pemeriksaan security/performance yang sesuai.

## 5. Kriteria penerimaan

- Pesanan tersimpan persisten dan dapat diakses sesuai hak akses.
- Harga dan total divalidasi server-side.
- Reservasi 15 menit, penahanan setelah pelanggan menyatakan pembayaran/mengirim bukti dalam tenggat, pelepasan reservasi, dan kasus pembayaran terlambat berfungsi konsisten.
- Kapasitas tidak terlampaui pada checkout bersamaan.
- Bukti pembayaran tidak otomatis menandai transaksi sebagai lunas.
- Status pembayaran dan operasional terpisah.
- Pelanggan hanya dapat melihat pelacakan pesanan yang berhak diaksesnya.
- Admin dapat memverifikasi pembayaran dan mengelola status dengan audit trail.
- Pesan konfirmasi WhatsApp hanya dikirim setelah pembayaran terverifikasi dan tidak menghasilkan duplikasi saat retry.
- Kasus kapasitas penuh, pembayaran terlambat, pembatalan, refund, dan kegagalan notifikasi telah diuji.
- Tidak ada data pelanggan, token pelacakan, atau secret yang terbuka secara publik.

## 6. Skenario QA minimum

- Checkout bersamaan untuk kapasitas produk/tanggal yang hampir penuh.
- Reservasi kedaluwarsa tanpa aktivitas pembayaran.
- Pelanggan mengirim pernyataan/bukti sebelum 15 menit, lalu admin memverifikasi setelahnya.
- Pembayaran terlambat ketika kapasitas sudah penuh.
- Bukti tidak valid, verifikasi ditolak, dan refund yang belum/ sudah diproses.
- Permintaan atau event duplikat dan percobaan ulang.
- WhatsApp gagal terkirim lalu dicoba ulang.
- Akses pengguna ke pesanan milik pelanggan lain.
- Hak akses `sales_admin` dibandingkan dengan `owner`.
- Pemesanan melewati batas pukul 18.00 WITA pada tanggal yang sama.

## 7. Batas perubahan

Dokumen ini hanya menjadi backlog kebutuhan lanjutan yang belum terbukti selesai. Fitur yang telah terverifikasi pada baseline tidak ditulis ulang sebagai tugas implementasi. Tidak ada perubahan kode aplikasi, skema Supabase, maupun deployment yang termasuk dalam pembaruan dokumen PRD ini.
