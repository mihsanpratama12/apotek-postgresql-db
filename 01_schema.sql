-- ============================================================
-- APOTEK / PHARMACY MANAGEMENT DATABASE SCHEMA (PostgreSQL)
-- Fitur: stok per batch & tanggal kedaluwarsa, resep dokter,
--        penjualan, pembelian ke supplier, retur, audit stok.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS stock_movements CASCADE;
DROP TABLE IF EXISTS sale_items CASCADE;
DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS prescription_items CASCADE;
DROP TABLE IF EXISTS prescriptions CASCADE;
DROP TABLE IF EXISTS purchase_items CASCADE;
DROP TABLE IF EXISTS purchases CASCADE;
DROP TABLE IF EXISTS medicine_batches CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP TABLE IF EXISTS medicine_categories CASCADE;
DROP TABLE IF EXISTS suppliers CASCADE;
DROP TABLE IF EXISTS doctors CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS employees CASCADE;

-- ============================================================
-- MASTER DATA
-- ============================================================

CREATE TABLE employees (
    employee_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(150) NOT NULL,
    role            VARCHAR(30)  NOT NULL CHECK (role IN ('APOTEKER','ASISTEN_APOTEKER','KASIR','ADMIN')),
    license_number  VARCHAR(50),          -- SIPA untuk apoteker
    phone           VARCHAR(20),
    email           CITEXT UNIQUE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE suppliers (
    supplier_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(150) NOT NULL,
    contact_person  VARCHAR(150),
    phone           VARCHAR(20),
    email           CITEXT,
    address         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE doctors (
    doctor_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(150) NOT NULL,
    str_number      VARCHAR(50),          -- Surat Tanda Registrasi
    specialization  VARCHAR(100),
    phone           VARCHAR(20),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customers (
    customer_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(150) NOT NULL,
    phone           VARCHAR(20),
    address         TEXT,
    date_of_birth   DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE medicine_categories (
    category_id     SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    -- golongan obat sesuai regulasi Indonesia
    drug_class      VARCHAR(30) NOT NULL CHECK (
                        drug_class IN ('BEBAS','BEBAS_TERBATAS','KERAS','NARKOTIKA','PSIKOTROPIKA')
                    )
);

-- ============================================================
-- MEDICINES & STOCK (per batch, FEFO - First Expired First Out)
-- ============================================================

CREATE TABLE medicines (
    medicine_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id         INTEGER REFERENCES medicine_categories(category_id),
    code                VARCHAR(30) UNIQUE NOT NULL,   -- kode internal
    name                VARCHAR(200) NOT NULL,
    generic_name        VARCHAR(200),
    manufacturer        VARCHAR(150),
    unit                VARCHAR(20) NOT NULL DEFAULT 'strip',  -- strip/box/botol/tablet
    requires_prescription BOOLEAN NOT NULL DEFAULT FALSE,
    selling_price       NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
    min_stock_level     INTEGER NOT NULL DEFAULT 10,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Setiap batch obat punya expiry date & harga beli sendiri.
-- Ini kunci sistem apotek: stok TIDAK digabung rata, tapi dilacak per batch.
CREATE TABLE medicine_batches (
    batch_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medicine_id     UUID NOT NULL REFERENCES medicines(medicine_id) ON DELETE CASCADE,
    supplier_id     UUID REFERENCES suppliers(supplier_id),
    batch_number    VARCHAR(50) NOT NULL,
    purchase_price  NUMERIC(12,2) NOT NULL CHECK (purchase_price >= 0),
    quantity        INTEGER NOT NULL CHECK (quantity >= 0),
    expiry_date     DATE NOT NULL,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (medicine_id, batch_number)
);

-- ============================================================
-- PURCHASING (Pembelian dari Supplier)
-- ============================================================

CREATE TABLE purchases (
    purchase_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id     UUID NOT NULL REFERENCES suppliers(supplier_id),
    employee_id     UUID REFERENCES employees(employee_id),
    invoice_number  VARCHAR(50),
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING','RECEIVED','CANCELLED')),
    total_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,
    purchased_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE purchase_items (
    purchase_item_id BIGSERIAL PRIMARY KEY,
    purchase_id      UUID NOT NULL REFERENCES purchases(purchase_id) ON DELETE CASCADE,
    medicine_id      UUID NOT NULL REFERENCES medicines(medicine_id),
    batch_id         UUID REFERENCES medicine_batches(batch_id),
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    unit_price       NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total       NUMERIC(14,2) GENERATED ALWAYS AS (unit_price * quantity) STORED
);

-- ============================================================
-- PRESCRIPTIONS (Resep Dokter)
-- ============================================================

CREATE TABLE prescriptions (
    prescription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID REFERENCES customers(customer_id),
    doctor_id       UUID REFERENCES doctors(doctor_id),
    prescribed_at   DATE NOT NULL DEFAULT CURRENT_DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE prescription_items (
    prescription_item_id BIGSERIAL PRIMARY KEY,
    prescription_id       UUID NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    medicine_id            UUID NOT NULL REFERENCES medicines(medicine_id),
    dosage                 VARCHAR(100),     -- e.g. "3x1 tablet setelah makan"
    quantity_prescribed     INTEGER NOT NULL CHECK (quantity_prescribed > 0)
);

-- ============================================================
-- SALES (Penjualan / Transaksi Kasir)
-- ============================================================

CREATE TABLE sales (
    sale_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID REFERENCES customers(customer_id),      -- NULL = pelanggan umum/walk-in
    employee_id     UUID NOT NULL REFERENCES employees(employee_id),
    prescription_id UUID REFERENCES prescriptions(prescription_id),
    payment_method  VARCHAR(20) NOT NULL DEFAULT 'CASH'
                        CHECK (payment_method IN ('CASH','DEBIT','QRIS','TRANSFER','BPJS')),
    subtotal        NUMERIC(14,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,
    sold_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sale_items (
    sale_item_id    BIGSERIAL PRIMARY KEY,
    sale_id         UUID NOT NULL REFERENCES sales(sale_id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines(medicine_id),
    batch_id        UUID NOT NULL REFERENCES medicine_batches(batch_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total      NUMERIC(14,2) GENERATED ALWAYS AS (unit_price * quantity) STORED
);

-- ============================================================
-- STOCK MOVEMENTS (Audit trail semua perubahan stok)
-- ============================================================

CREATE TABLE stock_movements (
    movement_id     BIGSERIAL PRIMARY KEY,
    batch_id        UUID NOT NULL REFERENCES medicine_batches(batch_id) ON DELETE CASCADE,
    movement_type   VARCHAR(20) NOT NULL CHECK (movement_type IN ('IN','OUT','ADJUSTMENT','EXPIRED_DISPOSAL')),
    quantity        INTEGER NOT NULL,     -- positif utk IN, negatif utk OUT
    reference_table VARCHAR(30),          -- 'purchases' / 'sales' / dsb
    reference_id    UUID,
    note            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
    audit_id        BIGSERIAL PRIMARY KEY,
    table_name      VARCHAR(50) NOT NULL,
    record_id       TEXT NOT NULL,
    action          VARCHAR(10) NOT NULL,
    old_data        JSONB,
    new_data        JSONB,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_medicines_category       ON medicines(category_id);
CREATE INDEX idx_medicines_name_search    ON medicines USING gin (to_tsvector('simple', name));
CREATE INDEX idx_batches_medicine         ON medicine_batches(medicine_id);
CREATE INDEX idx_batches_expiry           ON medicine_batches(expiry_date);
CREATE INDEX idx_sales_sold_at            ON sales(sold_at DESC);
CREATE INDEX idx_sales_customer           ON sales(customer_id);
CREATE INDEX idx_sale_items_sale          ON sale_items(sale_id);
CREATE INDEX idx_sale_items_medicine      ON sale_items(medicine_id);
CREATE INDEX idx_purchase_items_purchase  ON purchase_items(purchase_id);
CREATE INDEX idx_stock_movements_batch    ON stock_movements(batch_id);
CREATE INDEX idx_prescription_items_pres  ON prescription_items(prescription_id);
