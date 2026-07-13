# Database Manajemen Apotek (PostgreSQL)

Database relasional untuk sistem manajemen apotek: stok obat per batch dengan
tanggal kedaluwarsa (FEFO), resep dokter, penjualan, pembelian ke supplier,
dan audit trail stok.

## Fitur Utama

- **Stok per batch, bukan digabung rata** — setiap batch obat punya harga beli
  dan tanggal kedaluwarsa sendiri (`medicine_batches`), sesuai praktik apotek nyata.
- **FEFO (First Expired First Out)** — fungsi `fn_get_fefo_batch()` otomatis
  memilih batch dengan expiry date terdekat saat menjual, supaya obat lama
  terjual duluan.
- **Validasi resep otomatis** — trigger memblokir penjualan obat golongan keras
  (`requires_prescription = TRUE`) jika transaksi tidak melampirkan resep dokter.
- **Golongan obat sesuai regulasi Indonesia** — Bebas, Bebas Terbatas, Keras,
  Narkotika, Psikotropika (`medicine_categories.drug_class`).
- **Audit trail stok lengkap** — setiap perubahan stok (masuk dari pembelian,
  keluar dari penjualan) tercatat di `stock_movements`.
- **Trigger otomatis**:
  - Rekalkulasi total penjualan & pembelian setiap item berubah.
  - Pengurangan/penambahan stok batch otomatis.
  - Audit log perubahan/penghapusan transaksi penjualan.
- **Views siap pakai**:
  - `vw_expiring_soon` — obat yang akan kedaluwarsa dalam 90 hari.
  - `vw_low_stock` — obat dengan stok di bawah batas minimum.
  - `vw_daily_sales` — ringkasan penjualan harian.
  - `vw_best_selling_medicines` — obat paling laris.
  - `vw_supplier_purchase_history` — riwayat pembelian per supplier.
  - `vw_stock_valuation` — nilai aset stok saat ini.

## Struktur File

```
apotek_db/
├── sql/
│   ├── 01_schema.sql              # Tabel, constraint, index
│   ├── 02_functions_triggers.sql  # Trigger, validasi resep, FEFO
│   ├── 03_views.sql               # View reporting
│   └── 04_seed_data.sql           # Data contoh (termasuk demo alert)
├── erd.md                         # Diagram ERD (Mermaid)
└── README.md
```

## Cara Menjalankan

```bash
createdb apotek_demo
psql -d apotek_demo -f sql/01_schema.sql
psql -d apotek_demo -f sql/02_functions_triggers.sql
psql -d apotek_demo -f sql/03_views.sql
psql -d apotek_demo -f sql/04_seed_data.sql
```

Contoh query untuk dicoba:

```sql
-- Obat yang segera kedaluwarsa (data demo sengaja dibuat 45 hari lagi)
SELECT * FROM vw_expiring_soon;

-- Obat dengan stok menipis (data demo sengaja dibuat rendah)
SELECT * FROM vw_low_stock;

-- Coba jual obat resep TANPA resep -> akan gagal (trigger validasi)
-- INSERT INTO sale_items (sale_id, medicine_id, batch_id, quantity, unit_price)
-- VALUES ('<id-sale-tanpa-resep>', '<id-amoxicillin>', '<id-batch>', 5, 15000);
```

> Catatan: skrip sudah direview manual baris per baris untuk konsistensi FK,
> tipe data, dan urutan trigger, namun belum dijalankan langsung ke server
> PostgreSQL live (tidak tersedia di environment pembuatan). Disarankan
> menjalankan sekali di database lokal/staging sebelum dipakai demo ke client.

## Catatan untuk Proposal Upwork

Cocok dijadikan portofolio untuk pekerjaan seperti:
- "Design a pharmacy/inventory management database"
- "Build a POS system backend with batch/expiry tracking"
- "Implement FEFO/FIFO inventory logic in PostgreSQL"
- "Database with regulatory compliance rules (prescription validation)"

Skema, kolom, atau golongan obat bisa disesuaikan dengan regulasi negara lain
kalau client menargetkan pasar luar Indonesia.
