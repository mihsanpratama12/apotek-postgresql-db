-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- 1) Auto-update updated_at -------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_medicines_updated_at
    BEFORE UPDATE ON medicines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- 2) Blokir penjualan obat resep tanpa resep terkait --------------
CREATE OR REPLACE FUNCTION fn_check_prescription_required()
RETURNS TRIGGER AS $$
DECLARE
    v_requires_prescription BOOLEAN;
    v_sale_prescription_id  UUID;
BEGIN
    SELECT requires_prescription INTO v_requires_prescription
    FROM medicines WHERE medicine_id = NEW.medicine_id;

    SELECT prescription_id INTO v_sale_prescription_id
    FROM sales WHERE sale_id = NEW.sale_id;

    IF v_requires_prescription AND v_sale_prescription_id IS NULL THEN
        RAISE EXCEPTION 'Obat % memerlukan resep dokter, transaksi tidak memiliki resep', NEW.medicine_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sale_items_check_prescription
    BEFORE INSERT ON sale_items
    FOR EACH ROW EXECUTE FUNCTION fn_check_prescription_required();


-- 3) Kurangi stok batch saat penjualan + catat stock_movement -----
CREATE OR REPLACE FUNCTION fn_decrement_batch_stock()
RETURNS TRIGGER AS $$
DECLARE
    v_available INTEGER;
BEGIN
    SELECT quantity INTO v_available FROM medicine_batches WHERE batch_id = NEW.batch_id;

    IF v_available IS NULL THEN
        RAISE EXCEPTION 'Batch % tidak ditemukan', NEW.batch_id;
    ELSIF v_available < NEW.quantity THEN
        RAISE EXCEPTION 'Stok batch % tidak cukup (tersedia %, diminta %)', NEW.batch_id, v_available, NEW.quantity;
    END IF;

    UPDATE medicine_batches
    SET quantity = quantity - NEW.quantity
    WHERE batch_id = NEW.batch_id;

    INSERT INTO stock_movements (batch_id, movement_type, quantity, reference_table, reference_id, note)
    VALUES (NEW.batch_id, 'OUT', -NEW.quantity, 'sales', NEW.sale_id, 'Penjualan');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sale_items_decrement_stock
    AFTER INSERT ON sale_items
    FOR EACH ROW EXECUTE FUNCTION fn_decrement_batch_stock();


-- 4) Tambah stok batch saat purchase item diterima -----------------
CREATE OR REPLACE FUNCTION fn_increment_batch_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.batch_id IS NOT NULL THEN
        INSERT INTO stock_movements (batch_id, movement_type, quantity, reference_table, reference_id, note)
        VALUES (NEW.batch_id, 'IN', NEW.quantity, 'purchases', NEW.purchase_id, 'Pembelian dari supplier');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_purchase_items_increment_stock
    AFTER INSERT ON purchase_items
    FOR EACH ROW EXECUTE FUNCTION fn_increment_batch_stock();


-- 5) Rekalkulasi total penjualan otomatis --------------------------
CREATE OR REPLACE FUNCTION fn_recalc_sale_totals()
RETURNS TRIGGER AS $$
DECLARE
    v_sale_id UUID;
    v_subtotal NUMERIC(14,2);
BEGIN
    v_sale_id := COALESCE(NEW.sale_id, OLD.sale_id);

    SELECT COALESCE(SUM(line_total), 0) INTO v_subtotal
    FROM sale_items WHERE sale_id = v_sale_id;

    UPDATE sales
    SET subtotal     = v_subtotal,
        total_amount = v_subtotal - discount_amount
    WHERE sale_id = v_sale_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sale_items_recalc
    AFTER INSERT OR UPDATE OR DELETE ON sale_items
    FOR EACH ROW EXECUTE FUNCTION fn_recalc_sale_totals();


-- 6) Rekalkulasi total pembelian otomatis --------------------------
CREATE OR REPLACE FUNCTION fn_recalc_purchase_totals()
RETURNS TRIGGER AS $$
DECLARE
    v_purchase_id UUID;
    v_total NUMERIC(14,2);
BEGIN
    v_purchase_id := COALESCE(NEW.purchase_id, OLD.purchase_id);

    SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM purchase_items WHERE purchase_id = v_purchase_id;

    UPDATE purchases SET total_amount = v_total WHERE purchase_id = v_purchase_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_purchase_items_recalc
    AFTER INSERT OR UPDATE OR DELETE ON purchase_items
    FOR EACH ROW EXECUTE FUNCTION fn_recalc_purchase_totals();


-- 7) Fungsi bantu: cari batch terbaik untuk dijual (FEFO) ----------
-- FEFO = First Expired First Out, prinsip wajib di apotek supaya
-- obat yang lebih dulu kedaluwarsa terjual lebih dulu.
CREATE OR REPLACE FUNCTION fn_get_fefo_batch(p_medicine_id UUID, p_quantity INTEGER)
RETURNS UUID AS $$
DECLARE
    v_batch_id UUID;
BEGIN
    SELECT batch_id INTO v_batch_id
    FROM medicine_batches
    WHERE medicine_id = p_medicine_id
      AND quantity >= p_quantity
      AND expiry_date > CURRENT_DATE
    ORDER BY expiry_date ASC
    LIMIT 1;

    IF v_batch_id IS NULL THEN
        RAISE EXCEPTION 'Tidak ada batch dengan stok cukup (%) untuk obat %', p_quantity, p_medicine_id;
    END IF;

    RETURN v_batch_id;
END;
$$ LANGUAGE plpgsql;


-- 8) Audit log untuk perubahan/penghapusan data penjualan ----------
CREATE OR REPLACE FUNCTION fn_audit_sales()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name, record_id, action, old_data, new_data)
        VALUES ('sales', OLD.sale_id::TEXT, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(table_name, record_id, action, old_data, new_data)
        VALUES ('sales', OLD.sale_id::TEXT, 'DELETE', to_jsonb(OLD), NULL);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sales_audit
    AFTER UPDATE OR DELETE ON sales
    FOR EACH ROW EXECUTE FUNCTION fn_audit_sales();
