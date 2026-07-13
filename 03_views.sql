-- ============================================================
-- REPORTING VIEWS
-- ============================================================

-- Obat yang akan kedaluwarsa dalam 90 hari ke depan
CREATE OR REPLACE VIEW vw_expiring_soon AS
SELECT
    m.medicine_id,
    m.name,
    m.code,
    b.batch_id,
    b.batch_number,
    b.quantity,
    b.expiry_date,
    (b.expiry_date - CURRENT_DATE) AS days_remaining
FROM medicine_batches b
JOIN medicines m ON m.medicine_id = b.medicine_id
WHERE b.quantity > 0
  AND b.expiry_date <= CURRENT_DATE + INTERVAL '90 days'
ORDER BY b.expiry_date ASC;

-- Obat dengan stok di bawah batas minimum (total semua batch)
CREATE OR REPLACE VIEW vw_low_stock AS
SELECT
    m.medicine_id,
    m.name,
    m.code,
    m.min_stock_level,
    COALESCE(SUM(b.quantity), 0) AS current_stock
FROM medicines m
LEFT JOIN medicine_batches b ON b.medicine_id = m.medicine_id AND b.expiry_date > CURRENT_DATE
WHERE m.is_active = TRUE
GROUP BY m.medicine_id, m.name, m.code, m.min_stock_level
HAVING COALESCE(SUM(b.quantity), 0) <= m.min_stock_level
ORDER BY current_stock ASC;

-- Ringkasan penjualan harian
CREATE OR REPLACE VIEW vw_daily_sales AS
SELECT
    date_trunc('day', s.sold_at)::DATE AS sale_date,
    COUNT(DISTINCT s.sale_id)          AS total_transactions,
    SUM(s.total_amount)                AS total_revenue,
    ROUND(AVG(s.total_amount), 2)      AS avg_transaction_value
FROM sales s
GROUP BY 1
ORDER BY 1 DESC;

-- Obat paling laris
CREATE OR REPLACE VIEW vw_best_selling_medicines AS
SELECT
    m.medicine_id,
    m.name,
    m.code,
    SUM(si.quantity)     AS total_units_sold,
    SUM(si.line_total)   AS total_revenue
FROM medicines m
JOIN sale_items si ON si.medicine_id = m.medicine_id
GROUP BY m.medicine_id, m.name, m.code
ORDER BY total_units_sold DESC;

-- Riwayat pembelian per supplier
CREATE OR REPLACE VIEW vw_supplier_purchase_history AS
SELECT
    sup.supplier_id,
    sup.name AS supplier_name,
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    SUM(p.total_amount)           AS total_spent,
    MAX(p.purchased_at)           AS last_purchase_date
FROM suppliers sup
JOIN purchases p ON p.supplier_id = sup.supplier_id AND p.status = 'RECEIVED'
GROUP BY sup.supplier_id, sup.name
ORDER BY total_spent DESC;

-- Nilai stok saat ini (berdasarkan harga beli, untuk laporan aset)
CREATE OR REPLACE VIEW vw_stock_valuation AS
SELECT
    m.medicine_id,
    m.name,
    SUM(b.quantity)                       AS total_quantity,
    SUM(b.quantity * b.purchase_price)    AS total_purchase_value,
    SUM(b.quantity * m.selling_price)     AS total_selling_value
FROM medicines m
JOIN medicine_batches b ON b.medicine_id = m.medicine_id
WHERE b.quantity > 0
GROUP BY m.medicine_id, m.name
ORDER BY total_purchase_value DESC;
