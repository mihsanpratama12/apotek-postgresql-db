-- ============================================================
-- SEED / DEMO DATA
-- ============================================================

-- Employees
INSERT INTO employees (full_name, role, license_number, email) VALUES
('Apt. Dewi Kartika, S.Farm', 'APOTEKER', 'SIPA-1234/2020', 'dewi.kartika@apotek.local'),
('Rina Marlina', 'KASIR', NULL, 'rina.marlina@apotek.local');

-- Suppliers
INSERT INTO suppliers (name, contact_person, phone, email) VALUES
('PT Kimia Farma Trading', 'Andi Wijaya', '021-5551234', 'sales@kimiafarma-trading.co.id'),
('PT Enseval Putera Megatrading', 'Siti Aminah', '021-5559876', 'order@enseval.co.id');

-- Doctors
INSERT INTO doctors (full_name, str_number, specialization, phone) VALUES
('dr. Bambang Sutrisno, Sp.PD', 'STR-998877', 'Penyakit Dalam', '081211112222'),
('dr. Lina Wijaya', 'STR-556644', 'Umum', '081233334444');

-- Customers
INSERT INTO customers (full_name, phone, date_of_birth) VALUES
('Hendra Gunawan', '081311112222', '1985-04-12'),
('Maya Sari', '081322223333', '1992-09-30');

-- Medicine categories
INSERT INTO medicine_categories (name, drug_class) VALUES
('Analgesik', 'BEBAS'),
('Antibiotik', 'KERAS'),
('Obat Batuk & Flu', 'BEBAS_TERBATAS'),
('Vitamin & Suplemen', 'BEBAS');

-- Medicines
INSERT INTO medicines (category_id, code, name, generic_name, manufacturer, unit, requires_prescription, selling_price, min_stock_level) VALUES
(1, 'MED-001', 'Paracetamol 500mg', 'Paracetamol', 'Kimia Farma', 'strip', FALSE, 8000, 20),
(2, 'MED-002', 'Amoxicillin 500mg', 'Amoxicillin', 'Sanbe Farma', 'strip', TRUE, 15000, 15),
(3, 'MED-003', 'OBH Combi Batuk Flu', 'Guaifenesin + Paracetamol', 'Combiphar', 'botol', FALSE, 22000, 10),
(4, 'MED-004', 'Vitamin C 1000mg', 'Ascorbic Acid', 'Sido Muncul', 'strip', FALSE, 25000, 15);

-- Medicine batches
INSERT INTO medicine_batches (medicine_id, supplier_id, batch_number, purchase_price, quantity, expiry_date)
SELECT m.medicine_id, s.supplier_id, 'B-PCT-2025-01', 5000, 100, CURRENT_DATE + INTERVAL '18 months'
FROM medicines m, suppliers s WHERE m.code='MED-001' AND s.name LIKE 'PT Kimia Farma%';

INSERT INTO medicine_batches (medicine_id, supplier_id, batch_number, purchase_price, quantity, expiry_date)
SELECT m.medicine_id, s.supplier_id, 'B-AMX-2025-01', 10000, 60, CURRENT_DATE + INTERVAL '45 days'  -- segera exp, untuk demo alert
FROM medicines m, suppliers s WHERE m.code='MED-002' AND s.name LIKE 'PT Enseval%';

INSERT INTO medicine_batches (medicine_id, supplier_id, batch_number, purchase_price, quantity, expiry_date)
SELECT m.medicine_id, s.supplier_id, 'B-OBH-2025-01', 15000, 8, CURRENT_DATE + INTERVAL '1 year'    -- stok rendah, untuk demo alert
FROM medicines m, suppliers s WHERE m.code='MED-003' AND s.name LIKE 'PT Kimia Farma%';

INSERT INTO medicine_batches (medicine_id, supplier_id, batch_number, purchase_price, quantity, expiry_date)
SELECT m.medicine_id, s.supplier_id, 'B-VTC-2025-01', 18000, 80, CURRENT_DATE + INTERVAL '2 years'
FROM medicines m, suppliers s WHERE m.code='MED-004' AND s.name LIKE 'PT Enseval%';

-- Contoh resep dokter
DO $$
DECLARE
    v_doctor UUID;
    v_customer UUID;
    v_prescription UUID;
    v_medicine_amx UUID;
BEGIN
    SELECT doctor_id INTO v_doctor FROM doctors WHERE full_name LIKE 'dr. Bambang%';
    SELECT customer_id INTO v_customer FROM customers WHERE full_name = 'Hendra Gunawan';
    SELECT medicine_id INTO v_medicine_amx FROM medicines WHERE code = 'MED-002';

    INSERT INTO prescriptions (customer_id, doctor_id, notes)
    VALUES (v_customer, v_doctor, 'Infeksi saluran pernapasan ringan')
    RETURNING prescription_id INTO v_prescription;

    INSERT INTO prescription_items (prescription_id, medicine_id, dosage, quantity_prescribed)
    VALUES (v_prescription, v_medicine_amx, '3x1 tablet setelah makan selama 5 hari', 15);
END $$;

-- Contoh transaksi penjualan (obat bebas, tanpa resep)
DO $$
DECLARE
    v_employee UUID;
    v_customer UUID;
    v_sale UUID;
    v_medicine UUID;
    v_batch UUID;
BEGIN
    SELECT employee_id INTO v_employee FROM employees WHERE role = 'KASIR' LIMIT 1;
    SELECT customer_id INTO v_customer FROM customers WHERE full_name = 'Maya Sari';
    SELECT medicine_id INTO v_medicine FROM medicines WHERE code = 'MED-001';
    v_batch := fn_get_fefo_batch(v_medicine, 2);

    INSERT INTO sales (customer_id, employee_id, payment_method)
    VALUES (v_customer, v_employee, 'CASH')
    RETURNING sale_id INTO v_sale;

    INSERT INTO sale_items (sale_id, medicine_id, batch_id, quantity, unit_price)
    VALUES (v_sale, v_medicine, v_batch, 2, 8000);
END $$;

-- Contoh transaksi penjualan obat resep (dengan prescription_id, jadi lolos trigger validasi)
DO $$
DECLARE
    v_employee UUID;
    v_customer UUID;
    v_prescription UUID;
    v_sale UUID;
    v_medicine UUID;
    v_batch UUID;
BEGIN
    SELECT employee_id INTO v_employee FROM employees WHERE role = 'APOTEKER' LIMIT 1;
    SELECT customer_id INTO v_customer FROM customers WHERE full_name = 'Hendra Gunawan';
    SELECT prescription_id INTO v_prescription FROM prescriptions LIMIT 1;
    SELECT medicine_id INTO v_medicine FROM medicines WHERE code = 'MED-002';
    v_batch := fn_get_fefo_batch(v_medicine, 15);

    INSERT INTO sales (customer_id, employee_id, prescription_id, payment_method)
    VALUES (v_customer, v_employee, v_prescription, 'CASH')
    RETURNING sale_id INTO v_sale;

    INSERT INTO sale_items (sale_id, medicine_id, batch_id, quantity, unit_price)
    VALUES (v_sale, v_medicine, v_batch, 15, 15000);
END $$;
