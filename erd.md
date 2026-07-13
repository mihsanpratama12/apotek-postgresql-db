# Entity Relationship Diagram — Apotek

```mermaid
erDiagram
    SUPPLIERS ||--o{ PURCHASES : supplies
    SUPPLIERS ||--o{ MEDICINE_BATCHES : ships

    MEDICINE_CATEGORIES ||--o{ MEDICINES : classifies

    MEDICINES ||--o{ MEDICINE_BATCHES : "stocked as"
    MEDICINES ||--o{ SALE_ITEMS : sold_as
    MEDICINES ||--o{ PURCHASE_ITEMS : purchased_as
    MEDICINES ||--o{ PRESCRIPTION_ITEMS : prescribed_as

    MEDICINE_BATCHES ||--o{ SALE_ITEMS : "deducted from"
    MEDICINE_BATCHES ||--o{ STOCK_MOVEMENTS : tracks

    PURCHASES ||--o{ PURCHASE_ITEMS : contains
    EMPLOYEES ||--o{ PURCHASES : records
    EMPLOYEES ||--o{ SALES : processes

    DOCTORS ||--o{ PRESCRIPTIONS : writes
    CUSTOMERS ||--o{ PRESCRIPTIONS : receives
    CUSTOMERS ||--o{ SALES : makes

    PRESCRIPTIONS ||--o{ PRESCRIPTION_ITEMS : contains
    PRESCRIPTIONS ||--o{ SALES : "validates (if required)"

    SALES ||--o{ SALE_ITEMS : contains
```

## Ringkasan Relasi

| Tabel | Relasi Utama |
|---|---|
| medicines → medicine_batches | 1-to-many (setiap obat punya banyak batch) |
| medicine_batches → sale_items | 1-to-many (stok dikurangi per batch, prinsip FEFO) |
| suppliers → medicine_batches / purchases | 1-to-many |
| doctors → prescriptions | 1-to-many |
| prescriptions → sales | opsional, wajib untuk obat golongan keras |
| sales → sale_items | 1-to-many |
| medicine_batches → stock_movements | 1-to-many (audit trail masuk/keluar) |
