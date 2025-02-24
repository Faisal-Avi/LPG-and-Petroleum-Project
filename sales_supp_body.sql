CREATE OR REPLACE PACKAGE BODY sales_supp
IS  

    FUNCTION get_customer_security_rate (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT p.security_rate
        FROM inv_sales_price_d p,
             inv_sales_price_m m
        WHERE P.PRICE_ID = M.PRICE_ID
        AND m.price_status = 'APPROVED'
        AND p.status = 'APPROVED'
        AND p.item_id = in_item_id
        AND m.customer_type = in_customer_type;
        
        l_security_rate NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_security_rate;
        CLOSE c1;
        
        RETURN l_security_rate;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_cust_type_wise_item_rate (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT p.item_rate
        FROM inv_sales_price_d p,
             inv_sales_price_m m
        WHERE P.PRICE_ID = M.PRICE_ID
        AND m.price_status = 'APPROVED'
        AND p.status = 'APPROVED'
        AND p.item_id = in_item_id
        AND m.customer_type = in_customer_type;
        
        l_item_rate NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_item_rate;
        CLOSE c1;
        
        RETURN l_item_rate;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_cust_type_wise_vat1 (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT p.vat_amount_1
        FROM inv_sales_price_d p,
             inv_sales_price_m m
        WHERE P.PRICE_ID = M.PRICE_ID
        AND m.price_status = 'APPROVED'
        AND p.status = 'APPROVED'
        AND p.item_id = in_item_id
        AND m.customer_type = in_customer_type;
        
        l_vat_amount1 NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_vat_amount1;
        CLOSE c1;
        
        RETURN l_vat_amount1;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_cust_type_wise_vat2 (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT p.vat_amount_2
        FROM inv_sales_price_d p,
             inv_sales_price_m m
        WHERE P.PRICE_ID = M.PRICE_ID
        AND m.price_status = 'APPROVED'
        AND p.status = 'APPROVED'
        AND p.item_id = in_item_id
        AND m.customer_type = in_customer_type;
        
        l_vat_amount2 NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_vat_amount2;
        CLOSE c1;
        
        RETURN l_vat_amount2;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE sales_rate_update (
        in_date IN DATE,
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT sales_invoice_id,
               challan_id,
               sale_order_id,
               sale_order_item_id,
               new_item_rate,
               new_security_rate,
               new_vat_amount1,
               new_vat_amount2,
               item_id
        FROM inv_sales_item_rate_v v
        WHERE v.invoice_date >= in_date
        AND v.sale_order_id IN (SELECT sales_order_id
                                FROM inv_sales_orders
                                WHERE po_date < in_date);
    BEGIN
        FOR i IN c1 LOOP
            
            FOR j IN (SELECT qty ,delivered_qty, sales_order_item_id FROM inv_sales_order_items WHERE sales_order_item_id = i.sale_order_item_id) LOOP
                
                IF NVL(j.delivered_qty,0) = 0 THEN
                
                    sales_supp.sales_table_log_write(in_date);    
                
                    UPDATE inv_sales_order_items oi
                    SET rate1 = i.new_security_rate,
                        rate = i.new_item_rate,
                        amount = qty * i.new_item_rate,
                        sales_tax_1 = i.new_vat_amount1,
                        sales_tax_2 = i.new_vat_amount2,
                        vat_amount_1 = qty * i.new_vat_amount1,
                        vat_amount_2 = qty * i.new_vat_amount2
                    WHERE sales_order_item_id = j.sales_order_item_id;
                    
                    UPDATE inv_delivery_challan_items
                    SET rate1 = i.new_security_rate,
                        amount1 = qty * i.new_security_rate,
                        rate = i.new_item_rate,
                        amount = qty * i.new_item_rate,
                        sales_tax_1 = i.new_vat_amount1,
                        sales_tax_2 = i.new_vat_amount2,
                        vat_amount_1 = qty * i.new_vat_amount1,
                        vat_amount_2 = qty * i.new_vat_amount2
                    WHERE sale_order_item_id = j.sales_order_item_id;
                    
                    UPDATE inv_sales_invoice_items
                    SET security_rate = i.new_security_rate,
                        security_amount = qty * i.new_security_rate,
                        rate = i.new_item_rate,
                        amount = qty * i.new_item_rate,
                        sales_tax_1 = i.new_vat_amount1,
                        sales_tax_2 = i.new_vat_amount2,
                        vat_amount_1 = qty * i.new_vat_amount1,
                        vat_amount_2 = qty * i.new_vat_amount2,
                        st_amount = NVL((qty * i.new_vat_amount1),0) + NVL((qty * i.new_vat_amount2),0)
                    WHERE sale_order_item_id = j.sales_order_item_id;
                    
                    UPDATE inv_sales_invoices si
                    SET (invoice_amount, sales_tax_amount, total_invoice_amount) = (SELECT SUM(amount),
                                                                                           SUM(st_amount),
                                                                                           SUM(amount) + SUM(st_amount)
                                                                                    FROM inv_sales_invoice_items ii
                                                                                    WHERE si.sales_invoice_id = ii.sales_invoice_id
                                                                                    AND si.sales_invoice_id = i.sales_invoice_id
                                                                                    GROUP BY ii.sales_invoice_id )
                    WHERE si.sales_invoice_id = i.sales_invoice_id;
                    
                    COMMIT;
                    
                ELSIF j.delivered_qty < j.qty THEN
                    sales_supp.sales_table_log_write(in_date);
                    COMMIT;
                ELSIF j.delivered_qty >= j.qty THEN
                    sales_supp.sales_table_log_write(in_date);
                    COMMIT;
                END IF;
                
            END LOOP;
            
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    PROCEDURE sales_table_log_write (
        in_date IN DATE
    ) IS
        CURSOR c1
        IS
        SELECT sales_invoice_id,
               challan_id,
               sale_order_id
        FROM inv_sales_item_rate_v v
        WHERE v.invoice_date >= in_date
        AND v.sale_order_id IN (SELECT sales_order_id
                                FROM inv_sales_orders
                                WHERE po_date < in_date);
    BEGIN
        FOR i IN c1 LOOP
            INSERT INTO inv_sales_order_items_log
            SELECT sales_order_item_id, 
                   sales_order_id, 
                   item_id, 
                   qty, 
                   rate1, 
                   amount, 
                   delivered_qty, 
                   created_by, 
                   creation_date, 
                   last_update_by, 
                   last_update_date, 
                   rate, 
                   sales_tax, 
                   commission, 
                   old_qty, 
                   closed, 
                   closed_by, 
                   closed_date, 
                   discount, 
                   excise_duty, 
                   mapic_inv_qty, 
                   vat_amount_1, 
                   vat_amount_2, 
                   sales_tax_1, 
                   sales_tax_2, 
                   mapic_inv_no, 
                   remarks
            FROM inv_sales_order_items
            WHERE sales_order_id = i.sale_order_id;
            
            INSERT INTO inv_delivery_challan_items_log
            SELECT challan_item_id, 
                   challan_id, 
                   item_id, 
                   qty, 
                   sale_order_id, 
                   sale_order_item_id, 
                   created_by, 
                   creation_date, 
                   last_updated_by, 
                   last_update_date, 
                   rate, 
                   amount, 
                   sale_rate, 
                   sale_amount, 
                   packing_information, 
                   no_cartons, 
                   rate1, 
                   amount1, 
                   vat_percent, 
                   vat_amount, 
                   avg_rate, 
                   local_sale_rate, 
                   issue_ref, 
                   buffer_qty, 
                   vat_amount_1, 
                   vat_amount_2, 
                   sales_tax_1, 
                   sales_tax_2, 
                   rate_temp, 
                   new_rate
            FROM inv_delivery_challan_items
            WHERE challan_id = i.challan_id;
            
            INSERT INTO inv_sales_invoice_items_log 
            SELECT sales_invoice_id, 
                   item_id, 
                   qty, 
                   sale_order_id, 
                   sale_order_item_id, 
                   created_by, 
                   creation_date, 
                   last_updated_by, 
                   last_update_date, 
                   rate, 
                   amount, 
                   sales_tax_percent, 
                   excise_duty, 
                   debit_qty, 
                   debit_amount, 
                   account_id, 
                   inv_sales_invoice_items_id, 
                   extra_sales_tax_percent, 
                   further_sales_tax_percent, 
                   incom_tax_percent, 
                   security_rate, 
                   security_amount, 
                   st_amount, 
                   vat_amount_1, 
                   vat_amount_2, 
                   sales_tax_1, 
                   sales_tax_2, 
                   rate_temp
            FROM inv_sales_invoice_items
            WHERE sales_invoice_id = i.sales_invoice_id;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_sales_data
    IS
    BEGIN
        INSERT INTO mapics_sales (
            store_id, 
            item_code, 
            invoice_no, 
            invoice_date, 
            customer_id, 
            qty_pcs, 
            qty_kgs, 
            rate, 
            comm, 
            amount, 
            company_id, 
            branch_id,
            sales_item_id,
            sales_location_id
        )
        SELECT store_id,
               item_code,
               invoice_no,
               invoice_date,
               customer_id,
               qty_pcs,
               qty_kgs,
               rate,
               comm,
               amount,
               company_id,
               branch_id,
               item_id,
               location_id
        FROM sales_data_v;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_production_data
    IS
    BEGIN
        
        INSERT INTO mapics_production (
            location_code, 
            refill_no, 
            production_date, 
            item_code, 
            qty_pcs, 
            qty_kgs, 
            company_id, 
            branch_id,
            prod_item_id,
            prod_location_id
        )
        SELECT location_code,
               refill_no,
               production_date,
               item_code,
               qty_pcs,
               qty_kgs,
               company_id,
               branch_id,
               item_id,
               location_id_t
        FROM production_data_v;
        
        COMMIT;
    
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE sync_customer_amt_balance (
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS
    BEGIN
        MERGE INTO ar_customers_detail b
        USING customer_ledger_sum s
        ON (
                b.customer_id = s.customer_id
              --  AND b.opening_balance <> s.balance
        )
        WHEN MATCHED THEN
        UPDATE SET b.opening_balance = s.balance
        WHERE b.customer_id = s.customer_id
        WHEN NOT MATCHED THEN
        INSERT  (
            customer_detail_id, 
            customer_id
        )
        VALUES (
            0,
            0
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    FUNCTION get_own_stock (
        in_company_id  IN NUMBER,
        in_branch_id   IN VARCHAR2,
        in_location_id IN NUMBER,
        in_customer_id IN NUMBER,
        in_item_id     IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT own_stock
        FROM customer_stock_v
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND customer_id = in_customer_id
        AND item_id = in_item_id;
        
        l_own_stock NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_own_stock;
        CLOSE c1;
        
        RETURN l_own_stock;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_customer_stock (
        in_company_id  IN NUMBER,
        in_branch_id   IN VARCHAR2,
        in_location_id IN NUMBER,
        in_customer_id IN NUMBER,
        in_item_id     IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT customer_stock
        FROM customer_stock_v
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND customer_id = in_customer_id
        AND item_id = in_item_id;
        
        l_customer_stock NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_customer_stock;
        CLOSE c1;
        
        RETURN l_customer_stock;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    PROCEDURE sales_rate_correction (
        in_prev_month_year IN VARCHAR2,
        in_curr_month_year IN VARCHAR2,
        in_company_id      IN NUMBER,
        in_branch_id       IN VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT so.sales_order_id,
               so.order_status,
               so.customer_id,
               so.company_id,
               so.branch_id,
               so.location_id,
               so.payment_terms,
               so.created_by, 
               so.creation_date,
               so.approved_by, 
               so.approved_date, 
               so.po_currency,
               so.customer_type,
               so.gl_voucher_id,
               so.po_date,
               so.validity_date,
               so.po_no,
               soi.item_id,
               soi.qty order_qty,
               d.challan_qty challan_qty_curr_month,
               soi.qty - d.challan_qty diff_qty,
               soi.sales_tax,
               soi.commission,
               soi.sales_order_item_id,
               d.sale_order_item_id
        FROM inv_sales_orders so,
             inv_sales_order_items soi,
             (
             SELECT idc.sale_order_id,
                    idc.item_id,
                    idc.sale_order_item_id,
                    SUM(idc.qty) challan_qty
             FROM inv_delivery_challans dc ,
                  inv_delivery_challan_items idc
             WHERE dc.challan_id = idc.challan_id
             AND TRUNC(dc.challan_date) BETWEEN TO_DATE('01-'||in_curr_month_year) AND LAST_DAY(TO_DATE('01-'||in_curr_month_year))
             GROUP BY idc.sale_order_id,
                      idc.item_id,
                      idc.sale_order_item_id
             ) d
        WHERE so.sales_order_id = soi.sales_order_id
        AND so.sales_order_id = d.sale_order_id
        AND soi.item_id = d.item_id
        AND soi.sales_order_item_id = d.sale_order_item_id
        AND TRUNC(so.po_date) BETWEEN TO_DATE('01-'||in_prev_month_year) AND LAST_DAY(TO_DATE('01-'||in_prev_month_year)) 
        AND d.challan_qty > 0
        AND soi.item_id <> 1
        AND so.customer_id <> 419
        AND so.order_status <> 'CANCELED'
        AND so.company_id = NVL(in_company_id,so.company_id)
        AND so.branch_id = NVL(in_branch_id,so.branch_id);
        
        l_so_id NUMBER;
        l_po_id NUMBER;
        l_po_no NUMBER;
        l_so_dtl_id NUMBER;
        
    BEGIN
  
        FOR m IN c1 LOOP
            
            SELECT inv_sales_orders_s.NEXTVAL 
            INTO l_so_id
            FROM dual;
            
            SELECT NVL(MAX(po_id),0)+1 
            INTO l_po_id
            FROM inv_sales_orders 
            WHERE company_id=m.company_id
            AND branch_id=m.branch_id;
            
            l_po_no := m.company_id||m.branch_id||l_po_id;
                
            INSERT INTO inv_sales_orders (
                sales_order_id, 
                po_no,
                po_date, 
                customer_id, 
                validity_date, 
                payment_terms, 
                created_by, 
                creation_date, 
                last_update_by, 
                last_update_date, 
                approved_by, 
                approved_date, 
                order_status, 
                po_currency, 
                proforma_inv_no, 
                proforma_inv_date, 
                active, 
                closed_by, 
                closed_date, 
                scn_id, 
                po_id, 
                remarks, 
                mrn_id, 
                company_id, 
                branch_id, 
                location_id, 
                customer_type, 
                delivery_address, 
                sof_no, 
                sof_date, 
                mapics_do_no, 
                old_customer_id, 
                gl_voucher_id,
                old_do_id
            )
            VALUES (
                l_so_id,
                l_po_no,
                TO_DATE('01-'||in_curr_month_year),
                m.customer_id,
                LAST_DAY(TO_DATE('01-'||in_curr_month_year)),
                m.payment_terms,
                m.created_by, 
                TO_DATE('01-'||in_curr_month_year),
                NULL,
                NULL,
                m.approved_by, 
                TO_DATE('01-'||in_curr_month_year),
                'CLOSED',
                m.po_currency,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                l_po_id,
                'Automated DO creation due to month change against Old DO # ' || m.po_no ,
                NULL,
                m.company_id,
                m.branch_id,
                m.location_id,
                m.customer_type,
                NULL,
                NULL,
                TO_DATE('01-'||in_curr_month_year),
                NULL,
                NULL,
                m.gl_voucher_id,
                m.sales_order_id           
            );
            
            
            SELECT inv_sales_order_items_s.NEXTVAL 
            INTO l_so_dtl_id
            FROM dual;
            
            INSERT INTO inv_sales_order_items (
                sales_order_item_id, 
                sales_order_id, 
                item_id, 
                qty, 
                rate1, 
                amount, 
                delivered_qty, 
                created_by, 
                creation_date, 
                last_update_by, 
                last_update_date, 
                rate, 
                sales_tax, 
                commission, 
                old_qty, 
                closed, 
                closed_by, 
                closed_date, 
                discount, 
                excise_duty, 
                mapic_inv_qty, 
                vat_amount_1, 
                vat_amount_2, 
                sales_tax_1, 
                sales_tax_2, 
                mapic_inv_no, 
                remarks, 
                adjusted_qty
            )
            VALUES (
                l_so_dtl_id,
                l_so_id,
                m.item_id,
                m.challan_qty_curr_month,
                sales_supp.get_customer_security_rate(m.customer_type, m.item_id),
                m.challan_qty_curr_month * sales_supp.get_cust_type_wise_item_rate(m.customer_type, m.item_id),
                m.challan_qty_curr_month,
                m.created_by,
                m.creation_date,
                null,
                null,
                sales_supp.get_cust_type_wise_item_rate(m.customer_type, m.item_id),
                m.sales_tax,
                m.commission,
                NULL,
                NULL,
                NULL,
                NULL,
                0,
                0,
                0,
                m.challan_qty_curr_month * sales_supp.get_cust_type_wise_vat1(m.customer_type, m.item_id),
                m.challan_qty_curr_month * sales_supp.get_cust_type_wise_vat2(m.customer_type, m.item_id),
                sales_supp.get_cust_type_wise_vat1(m.customer_type, m.item_id),
                sales_supp.get_cust_type_wise_vat2(m.customer_type, m.item_id),
                NULL,
                'Automated do creation',
                0
            );
            
            UPDATE inv_sales_order_items
            SET delivered_qty = delivered_qty - m.challan_qty_curr_month
            WHERE sales_order_item_id = m.sales_order_item_id;
            
            UPDATE inv_sales_order_items
            SET adjusted_qty = qty - delivered_qty
            WHERE sales_order_item_id = m.sales_order_item_id;
            
            UPDATE inv_sales_orders
            SET order_status = 'CLOSED'
            WHERE sales_order_id = m.sales_order_id;
            
            COMMIT;
 
        END LOOP;
    
        FOR i IN (
                  SELECT so.old_do_id,
                         so.sales_order_id,
                         soi.sales_order_item_id,
                         soi.rate,
                         soi.rate1 security_rate,
                         soi.sales_tax_1,
                         soi.sales_tax_2,
                         soi.item_id
                  FROM inv_sales_orders so,
                       inv_sales_order_items soi
                  WHERE so.sales_order_id = soi.sales_order_id
                  AND so.old_do_id IS NOT NULL
                  AND TRUNC(po_date) BETWEEN TO_DATE('01-'||in_curr_month_year) AND LAST_DAY(TO_DATE('01-'||in_curr_month_year))
                  AND so.company_id = in_company_id
                  AND so.branch_id = in_branch_id
                  ) LOOP
                      
            FOR j IN (SELECT ci.challan_id,
                             ci.challan_item_id,
                             ci.item_id
                      FROM inv_delivery_challans c,
                           inv_delivery_challan_items ci
                      WHERE c.challan_id = ci.challan_id
                      AND c.challan_date BETWEEN TO_DATE('01-'||in_curr_month_year) AND LAST_DAY(TO_DATE('01-'||in_curr_month_year))
                      AND ci.sale_order_id = i.old_do_id
                      AND ci.item_id = i.item_id) LOOP      
                          
                UPDATE inv_delivery_challan_items
                SET sale_order_id = i.sales_order_id,
                    sale_order_item_id = i.sales_order_item_id,
                    rate = i.rate,
                    amount = qty * i.rate,
                    rate1 = i.security_rate,
                    amount1 = qty * i.security_rate,
                    sales_tax_1 = i.sales_tax_1,
                    sales_tax_2 = i.sales_tax_2,
                    vat_amount_1 = qty * i.sales_tax_1,
                    vat_amount_2 = qty * i.sales_tax_2,
                    vat_amount = NVL((qty * i.sales_tax_1),0) + NVL((qty * i.sales_tax_2),0)
                WHERE challan_item_id = j.challan_item_id; 
                    
                FOR k IN (SELECT oi.inv_sales_ogp_items_id,
                                 o.sales_ogp_id,
                                 oi.item_id,
                                 dci.challan_item_id
                          FROM inv_sales_ogp_items oi,
                               inv_sales_ogps o,
                               inv_delivery_challan_items dci
                          WHERE oi.sales_ogp_id = o.sales_ogp_id
                          AND dci.challan_item_id = oi.challan_item_id
                          AND oi.challan_item_id = j.challan_item_id) LOOP
                              
                    UPDATE inv_sales_ogp_items
                    SET sale_order_id=i.sales_order_id,
                        sale_order_item_id=i.sales_order_item_id
                    WHERE inv_sales_ogp_items_id = k.inv_sales_ogp_items_id
                    AND item_id=k.item_id;
                        
                        
                    FOR L IN (SELECT si.sales_invoice_id,
                                     sii.inv_sales_invoice_items_id,
                                     dci.rate,
                                     dci.sales_tax_1,
                                     dci.sales_tax_2,
                                     dci.rate1 security_rate,
                                     dci.challan_item_id,
                                     si.gl_voucher_id,
                                     dci.sale_order_id,
                                     dci.sale_order_item_id,
                                     si.invoice_no,
                                     si.company_id,
                                     si.branch_id,
                                     sii.item_id,
                                     si.suspense_voucher_id
                              FROM inv_sales_invoices si,
                                   inv_sales_invoice_items sii,
                                   inv_delivery_challan_items dci
                              WHERE si.sales_invoice_id = sii.sales_invoice_id 
                              AND si.challan_id = dci.challan_id
                              AND dci.challan_item_id = k.challan_item_id
                              AND si.sales_ogp_id = k.sales_ogp_id
                              AND sii.sale_order_id = i.old_do_id
                              AND sii.item_id = k.item_id ) LOOP
                                  
                        UPDATE inv_sales_invoice_items isii
                        SET isii.sale_order_id = l.sale_order_id,
                            isii.sale_order_item_id = l.sale_order_item_id,
                            isii.rate = L.rate,
                            isii.amount = qty * L.rate,
                            isii.sales_tax_1 = L.sales_tax_1,
                            isii.sales_tax_2 = L.sales_tax_2,
                            isii.vat_amount_1 = qty * L.sales_tax_1,
                            isii.vat_amount_2 = qty * L.sales_tax_2,
                            isii.st_amount = NVL((qty * L.sales_tax_1),0) + NVL((qty * L.sales_tax_2),0),
                            isii.susp_rate = sales_supp.get_suspense_rate(L.item_id)
                        WHERE isii.inv_sales_invoice_items_id = L.inv_sales_invoice_items_id
                        AND isii.sales_invoice_id = L.sales_invoice_id;
                        
                        UPDATE inv_sales_invoices si
                        SET (invoice_amount, sales_tax_amount, total_invoice_amount) = (SELECT SUM(amount),
                                                                                               SUM(st_amount),
                                                                                               SUM(amount) + SUM(st_amount)
                                                                                        FROM inv_sales_invoice_items ii
                                                                                        WHERE si.sales_invoice_id = ii.sales_invoice_id
                                                                                        AND si.sales_invoice_id = L.sales_invoice_id
                                                                                        GROUP BY ii.sales_invoice_id )
                        WHERE si.sales_invoice_id = L.sales_invoice_id;
                        
                        COMMIT;
                        
                        DELETE FROM mapics_sales 
                        WHERE invoice_no = l.invoice_no
                        AND company_id = l.company_id
                        AND branch_id = l.branch_id;
                        
                        COMMIT;
                        
                        FOR n IN (SELECT receiveable_account_id, 
                                         debit, 
                                         credit 
                                  FROM ar_invoice_transfer_v 
                                  WHERE sales_invoice_id = L.sales_invoice_id) LOOP
                                  
                            UPDATE gl_voucher_accounts 
                            SET debit = n.debit,
                                credit = n.credit
                            WHERE account_id = n.receiveable_account_id
                            AND voucher_id = L.gl_voucher_id;
                        
                        END LOOP;
                        
                        FOR o IN (SELECT receiveable_account_id, 
                                         debit, 
                                         credit,
                                         inv_sales_invoice_items_id,
                                         narration
                                  FROM ar_invoice_suspense_trn_v 
                                  WHERE sales_invoice_id = L.sales_invoice_id) LOOP
                                  
                            UPDATE gl_voucher_accounts        --gl_vouchers
                            SET debit = o.debit,
                                credit = o.credit,
                                naration = o.narration
                            WHERE account_id = o.receiveable_account_id
                            AND voucher_id = L.suspense_voucher_id
                            AND sales_invoice_item_id = o.inv_sales_invoice_items_id ;      
                                  
                        END LOOP;

                    END LOOP;
                        
                END LOOP;
                    
            END LOOP;
                
        END LOOP;  
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION get_customer_pkg_qty (
        in_company_id   IN  NUMBER,
        in_branch_id    IN  VARCHAR2,
        in_customer_id  IN  NUMBER,
        in_item_id      IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(qty,0)) - SUM(NVL(adjusted_qty,0))
        FROM inv_delivery_challan_reference
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND customer_id = in_customer_id
        AND item_id =  (SELECT transfer_item_id
                        FROM inv_items
                        WHERE item_id = in_item_id)
        AND status = 'APPROVED';
        
        l_pkg_qty NUMBER := 0;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_pkg_qty;
        CLOSE c1;
        
        RETURN l_pkg_qty;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    PROCEDURE customer_to_customer_transfer (
        in_location_id IN NUMBER,  -- location id from where we want to sell (FG Store ID)
        in_customer_id IN NUMBER,  -- new customer id to whom we want to transfer
        old_customer_id IN NUMBER,  -- old customer id from whom we want to transfer
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS  
/*
    -- First need to create RIGP Entry with old customer id of those qty at distributor to distributor transfer location
    -- Then entry in loan refill tolling receive
    (add record in stock balance table with rate if item is not at that location 33)
    -- Then HOD Approval of that records
    -- Then execute this procedure 
*/
        CURSOR c1
        IS
        SELECT loan_rec_no donum,
               lr.creation_date dodate,
               ar.customer_id customer_id_old,
               in_customer_id customer_id,
               lr.creation_date + 3 do_validity_date,
               lr.creation_date a_date,
               null sof_no,
               null sof_dat,
               lri.item_id item_id_old,
               (select fg_item_id from inv_items where item_id = lri.item_id)item_id,
               lr.location_id,
               to_number(ar.customer_type) customer_type,
               lri.received_qty do_qty,
               0 item_rate,
               0 vat,
               1300 s_rate,
               lr.company_id,
               lr.branch_id
        FROM inv_loans_receive lr,
             inv_loan_receive_items lri,
             ar_customers ar
        WHERE lr.loan_rec_id = lri.loan_rec_id
        AND lr.vendor_id = ar.vendor_code
        AND lr.loan_rec_status = 'APPROVED'
        AND lr.location_id = 33
        AND ar.customer_id = old_customer_id
        and lr.loan_rec_id not in (select NVL(dtd_ref,0) from inv_adjs);
        
        l_prev_donum NUMBER := -9999;
        l_prev_cust NUMBER := -9999;
        l_sale_order_id NUMBER;
        l_sale_order_no VARCHAR2(50);
        l_sale_order_item_id NUMBER;
        l_po_id NUMBER;
        l_po_no VARCHAR2(50);
        a NUMBER := 0;
        
        l_delivery_challan_id NUMBER;
        l_delivery_challan_no NUMBER;
        l_dc_dtl_id NUMBER;
        b NUMBER := 0;
        
        l_prev_inv_no NUMBER := -9999;
        
        l_prev_dc_id NUMBER := -9999;
        l_ogp_id NUMBER;
        l_ogp_dtl_id NUMBER;
        c NUMBER := 0;
        
        l_inv_sales_items_id NUMBER;
        l_sales_invoice_id NUMBER;
        l_sales_invoice_no NUMBER;
        l_prev_ogp_id NUMBER := -9999;
        l_ogp_no NUMBER;
        d NUMBER := 0;
        
        l_prev_cust_id NUMBER := -5555;
        
        l_adj_id NUMBER;
        l_adj_no NUMBER;
        
    BEGIN  
        FOR m IN c1 LOOP
       
            SELECT NVL(MAX(adj_id),0)+1 
            INTO l_adj_id 
            FROM inv_adjs;
                
            SELECT NVL(MAX(adj_no),0)+1 
            INTO l_adj_no 
            FROM inv_adjs 
            WHERE company_id=m.company_id 
            AND branch_id=m.branch_id;
                
            INSERT INTO inv_adjs (
                adj_id, 
                remarks, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date, 
                item_id, 
                locator_id, 
                adj_qty, 
                adj_rate, 
                adj_amount, 
                adj_status, 
                approved_by, 
                approval_date, 
                company_id, 
                branch_id, 
                location_id, 
                adj_no,
                dtd_ref
            )
            VALUES (
                l_adj_id,
                'DTD TRANSFER',
                109,
                m.dodate,
                109,
                SYSDATE,
                m.item_id_old,
                NULL,
                -1 * m.do_qty,
                0,
                0,
                'APPROVED',
                109,
                SYSDATE,
                m.company_id,
                m.branch_id,
                33,
                l_adj_no,
                m.donum
            );
                
            COMMIT;
            
            SELECT NVL(MAX(adj_id),0)+1 
            INTO l_adj_id 
            FROM inv_adjs;
                
            SELECT NVL(MAX(adj_no),0)+1 
            INTO l_adj_no 
            FROM inv_adjs 
            WHERE company_id=m.company_id 
            AND branch_id=m.branch_id;
                
            INSERT INTO inv_adjs (
                adj_id, 
                remarks, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date, 
                item_id, 
                locator_id, 
                adj_qty, 
                adj_rate, 
                adj_amount, 
                adj_status, 
                approved_by, 
                approval_date, 
                company_id, 
                branch_id, 
                location_id, 
                adj_no,
                dtd_ref
            )
            VALUES (
                l_adj_id,
                'DTD TRANSFER',
                109,
                m.dodate,
                109,
                SYSDATE,
                m.item_id,
                NULL,
                m.do_qty,
                0,
                0,
                'APPROVED',
                109,
                SYSDATE,
                m.company_id,
                m.branch_id,
                in_location_id,
                l_adj_no,
                m.donum
            );
                
            COMMIT;
            
            IF a = 0 or l_prev_cust <> m.customer_id THEN
        
                SELECT inv_sales_orders_s.NEXTVAL 
                INTO l_sale_order_id
                FROM dual;
                
                SELECT NVL(MAX(po_id),0)+1 
                INTO l_po_id
                FROM inv_sales_orders 
                WHERE company_id=1 
                AND branch_id='01';
                
                l_po_no := '101'|| l_po_id;
            
                INSERT INTO inv_sales_orders (
                    sales_order_id, 
                    po_no, 
                    po_date, 
                    customer_id, 
                    validity_date, 
                    payment_terms, 
                    created_by, 
                    creation_date, 
                    last_update_by, 
                    last_update_date, 
                    approved_by, 
                    approved_date, 
                    order_status, 
                    po_currency, 
                    proforma_inv_no, 
                    proforma_inv_date, 
                    active, 
                    closed_by, 
                    closed_date, 
                    scn_id, 
                    po_id, 
                    remarks, 
                    mrn_id, 
                    company_id, 
                    branch_id, 
                    location_id, 
                    customer_type, 
                    delivery_address, 
                    sof_no, 
                    sof_date,
                    mapics_do_no,
                    old_customer_id
                )
                VALUES (
                    l_sale_order_id,
                    l_po_no,
                    m.dodate,
                    m.customer_id,
                    m.do_validity_date,
                    'AP',
                    121,
                    m.dodate,
                    121,
                    SYSDATE,
                    121,
                    m.dodate,
                    'CLOSED',
                    'BDT',
                    NULL,
                    NULL,
                    NULL,
                    121,
                    m.dodate,
                    NULL,
                    l_po_id,
                    'DTD'||m.donum,
                    NULL,
                    1,
                    '01',
                    in_location_id,
                    m.customer_type,
                    NULL,
                    m.sof_no,
                    m.sof_dat,
                    m.donum,
                    M.customer_id_old
                );
                
                COMMIT;
                
                a := 1;
            
            END IF;
            
            SELECT inv_sales_order_items_s.NEXTVAL 
            INTO l_sale_order_item_id
            FROM dual;
           
            INSERT INTO inv_sales_order_items (
                sales_order_item_id, 
                sales_order_id, 
                item_id, 
                qty, 
                rate1, 
                amount, 
                delivered_qty, 
                created_by, 
                creation_date, 
                last_update_by, 
                last_update_date, 
                rate, 
                sales_tax, 
                commission, 
                old_qty, 
                closed, 
                closed_by, 
                closed_date, 
                discount, 
                excise_duty,
                mapic_inv_qty
            )
            VALUES (
                l_sale_order_item_id,
                l_sale_order_id,
                m.item_id,
                m.do_qty,
                m.s_rate,
                m.do_qty * m.item_rate,
                m.do_qty,
                121,
                m.dodate,
                121,
                SYSDATE,
                m.item_rate,
                m.vat,
                NULL,
                NULL,
                'Y',
                121,
                m.dodate,
                NULL,
                NULL,
                null
            );

            COMMIT; 
            
            l_prev_donum := m.donum;
            l_prev_cust  := m.customer_id;
       
        END LOOP;
      
      
     
        FOR n IN (
           SELECT 1,         
                  o.po_date ,
                  o.customer_id,
                  o.location_id,
                  o.sales_order_id,
                  oi.sales_order_item_id,
                  oi.item_id,
                  oi.qty ,
                  0,
                  oi.rate1 ,
                  null,
                  o.mapics_do_no
            FROM inv_sales_orders o,
                inv_sales_order_items oi
            WHERE o.sales_order_id = oi.sales_order_id
            AND o.remarks = 'DTD'||o.MAPICS_DO_NO
            AND o.MAPICS_DO_NO NOT IN (SELECT NVL(old_invoice_no,0) FROM INV_DELIVERY_CHALLANS)
            ORDER BY o.customer_id
        ) LOOP
       
            IF l_prev_cust <> n.customer_id OR b = 0 THEN

               SELECT  inv_challan_id_s.NEXTVAL 
               INTO l_delivery_challan_id  
               FROM dual;
               
               SELECT NVL(MAX(challan_no),0)+1 
               INTO l_delivery_challan_no
               FROM inv_delivery_challans 
               WHERE company_id=1
               AND branch_id='01';

               INSERT INTO inv_delivery_challans (
                    challan_id, 
                    challan_no, 
                    challan_date, 
                    customer_id, 
                    created_by, 
                    creation_date, 
                    last_updated_by, 
                    last_update_date, 
                    approved_by, 
                    approved_date, 
                    delivery_status, 
                    remarks, 
                    batch_no, 
                    dc_jit, 
                    export_date, 
                    discharge_port, 
                    gross_weight, 
                    shipment_type, 
                    user_ip, 
                    company_id, 
                    branch_id, 
                    location_id, 
                    gl_voucher_id, 
                    chk_export,
                    old_invoice_no
               )
               VALUES (
                    l_delivery_challan_id,
                    l_delivery_challan_no,
                    n.po_date,
                    n.customer_id,  
                    121,
                    n.po_date,
                    121,
                    SYSDATE,
                    121,
                    n.po_date,
                    'INVOICED',
                    'DTD'||n.mapics_do_no,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    1,
                    '01',
                    n.location_id,
                    NULL,
                    NULL,
                    n.mapics_do_no
               );
               
               b := 1;
               
            END IF;    
       
            SELECT  inv_challan_item_id_s.nextval 
            INTO l_dc_dtl_id 
            FROM dual;
           
            INSERT INTO inv_delivery_challan_items (
                challan_item_id, 
                challan_id, 
                item_id, 
                qty, 
                sale_order_id, 
                sale_order_item_id, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date, 
                rate, 
                amount, 
                sale_rate, 
                sale_amount, 
                packing_information, 
                no_cartons, 
                rate1, 
                amount1, 
                vat_percent, 
                vat_amount, 
                avg_rate, 
                local_sale_rate,
                issue_ref
            )
            VALUES (
                l_dc_dtl_id ,
                l_delivery_challan_id,
                n.item_id,
                n.qty,  
                n.sales_order_id,
                n.sales_order_item_id,
                121,
                n.po_date,
                121,
                SYSDATE,
                0,
                0 ,
                NULL,
                NULL,
                NULL,
                NULL,
                n.rate1,
                n.qty * n.rate1,
                7,
                NULL,
                NULL,
                NULL,
                null
            );
            
            COMMIT;

            l_prev_cust := n.customer_id;
            
        END LOOP;     
     
        FOR p IN (
            SELECT dc.challan_id ,
                   dc.challan_date,
                   dc.location_id,
                   dc.customer_id,
                   dci.item_id,
                   dci.sale_order_item_id,
                   dci.sale_order_id,
                   dci.qty,
                   dci.rate,
                   dci.challan_item_id,
                   dc.old_invoice_no
            FROM inv_delivery_challans dc,
                 inv_delivery_challan_items dci
            WHERE dc.challan_id = dci.challan_id
            AND dc.remarks = 'DTD'||dc.old_invoice_no
            AND dc.OLD_INVOICE_NO NOT IN (SELECT NVL(old_invoice_no,0) FROM INV_SALES_OGPS)
            ORDER BY dc.challan_id
        ) LOOP 
            
            IF l_prev_dc_id <> p.challan_id OR c = 0 THEN
          
                write_dc_reference (
                    challan        => p.challan_id , 
                    in_location_id => p.location_id
               );
           
                SELECT NVL(MAX(sales_ogp_id),0)+1 
                INTO l_ogp_id
                FROM inv_sales_ogps;
                
                SELECT NVL(MAX(sales_ogp_id),0)+1 
                INTO l_ogp_no
                FROM inv_sales_ogps
                WHERE company_id = 1 
                AND branch_id = '01';
            
                INSERT INTO inv_sales_ogps (
                    sales_ogp_id, 
                    customer_id, 
                    vehicle_type, 
                    vehicle_no, 
                    driver_name, 
                    challan_id, 
                    created_by, 
                    creation_date, 
                    last_updated_by, 
                    last_update_date, 
                    trans_comp, 
                    remarks, 
                    out, 
                    out_date, 
                    out_by, 
                    ogp_status, 
                    builty_no, 
                    mode_of_transport, 
                    company_id, 
                    branch_id, 
                    location_id, 
                    driver_phone,
                    old_invoice_no,
                    sale_ogp_no
                )
                VALUES (
                    l_ogp_id,
                    p.customer_id,
                    NULL,
                    NULL,  
                    NULL,
                    p.challan_id,
                    121,
                    p.challan_date,
                    121,
                    SYSDATE,
                    NULL,
                    'DTD'||p.old_invoice_no,
                    'Y',
                    p.challan_date,
                    121,
                    'OUT',
                    NULL,
                    NULL,
                    1,
                    '01',
                    p.location_id,
                    NULL,
                    p.old_invoice_no,
                    l_ogp_no
                );
               
                COMMIT;
                c := 1;
            END IF;
            
            SELECT INV_SALES_OGP_ITEMS_ID_S.NEXTVAL 
            INTO l_ogp_dtl_id
            FROM DUAL;

               
            INSERT INTO inv_sales_ogp_items (
                item_id, 
                qty, 
                sales_ogp_id, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date, 
                sale_order_item_id, 
                challan_item_id, 
                sale_order_id, 
                inv_sales_ogp_items_id
            )
            VALUES (
                p.item_id,
                p.qty,
                l_ogp_id,
                121,  
                p.challan_date,
                121,
                SYSDATE,
                p.sale_order_item_id,
                p.challan_item_id,
                p.sale_order_id,
                l_ogp_dtl_id
            );
            
            l_prev_dc_id := p.challan_id;
       
            COMMIT;
            
        END LOOP;

        FOR r IN (
            SELECT o.sales_ogp_id,
                   o.customer_id,
                   o.challan_id,
                   o.out_date,
                   o.location_id,
                   c.challan_no,
                   oi.item_id,
                   oi.qty,
                   ci.RATE1 rate,
                   ci.sale_order_item_id,
                   ci.sale_order_id,
                   o.old_invoice_no
            FROM inv_sales_ogps o,
                 inv_sales_ogp_items oi,
                 inv_delivery_challans c,
                 inv_delivery_challan_items ci
            WHERE o.sales_ogp_id = oi.sales_ogp_id
            AND o.challan_id = c.challan_id
            AND c.challan_id = ci.challan_id
            AND ci.challan_item_id = oi.challan_item_id
            AND o.remarks = 'DTD'||o.old_invoice_no
            AND o.OLD_INVOICE_NO not in (select nvl(old_invoice_no,0) from inv_sales_invoices)
            ORDER BY o.sales_ogp_id
        ) LOOP 
            
            IF r.sales_ogp_id <> l_prev_ogp_id OR d = 0 THEN
        
                SELECT NVL(MAX(sales_invoice_id),0)+1 
                INTO l_sales_invoice_id 
                FROM inv_sales_invoices;
                
                SELECT NVL(MAX(sales_invoice_id),0)+1 
                INTO l_sales_invoice_no 
                FROM inv_sales_invoices
                WHERE company_id = 1
                AND branch_id = '01';
           
                INSERT INTO inv_sales_invoices (
                    sales_invoice_id, 
                    customer_id, 
                    challan_id, 
                    created_by, 
                    creation_date, 
                    last_updated_by, 
                    last_update_date, 
                    sales_ogp_id, 
                    remarks, 
                    invoice_amount, 
                    sales_tax_amount, 
                    total_invoice_amount, 
                    invoice_adjusted, 
                    invoice_balance, 
                    st_account_id, 
                    receivable_account_id, 
                    invoice_date, 
                    gl_voucher_id, 
                    excise_duty, 
                    invoice_no, 
                    parent_invoice_id, 
                    ed_percent, 
                    jit_inv, 
                    exchange_rate, 
                    currency_inv, 
                    incometax_wh, 
                    bl_date, 
                    add_sales_tax_amnt, 
                    extra_sales_tax_amount, 
                    further_sales_tax_amount, 
                    invoice_status, 
                    incom_tax_amount, 
                    company_id, 
                    branch_id, 
                    location_id,
                    old_invoice_no
                )
                VALUES (
                    l_sales_invoice_id,
                    r.customer_id,
                    r.challan_id,
                    121,
                    r.out_date,    
                    121,
                    SYSDATE,
                    r.sales_ogp_id,
                    'Distributor to Distributor Transfer Invoice',
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    r.out_date,
                    NULL,
                    NULL,
                    l_sales_invoice_no,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    'PREPARED',
                    NULL,
                    1,
                    '01',
                    r.location_id,
                    r.old_invoice_no
                );
               
                COMMIT;
                
                d := 1;
            
            END IF;
                
            SELECT inv_sales_invoice_items_id_s.NEXTVAL 
            INTO l_inv_sales_items_id
            FROM DUAL;
           
            INSERT INTO inv_sales_invoice_items (
                sales_invoice_id, 
                item_id, 
                qty, 
                sale_order_id, 
                sale_order_item_id, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date, 
                rate, 
                amount, 
                sales_tax_percent, 
                excise_duty, 
                debit_qty, 
                debit_amount, 
                account_id, 
                inv_sales_invoice_items_id, 
                extra_sales_tax_percent, 
                further_sales_tax_percent, 
                incom_tax_percent, 
                security_rate, 
                security_amount
            )
            VALUES (
                l_sales_invoice_id,
                r.item_id,
                r.qty,
                r.sale_order_id,
                r.sale_order_item_id,
                121,
                r.out_date,
                121,
                SYSDATE,
                0,
                r.qty * 0,
                7,
                NULL,
                NULL,
                NULL,
                NULL,
                l_inv_sales_items_id,
                NULL,
                NULL,
                NULL,
                r.rate,
                NVL(r.qty,0) * NVL(r.rate,0)
            );
           
            COMMIT;
            
            l_prev_ogp_id := r.sales_ogp_id ;
            
            out_error_code := '0000';
            out_error_text := 'Successfully Transfered.';
        
        END LOOP;
    END;
    
    FUNCTION check_dc_admin (
        in_user_id   IN   NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT dc_admin
        FROM sys_users
        WHERE user_id = in_user_id;
        
        l_chk CHAR(1) := 'N';
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        
        RETURN l_chk;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 'N';
    END;
    
    
    FUNCTION chk_dc_date_bypass (
        in_location_id   IN   NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT dc_date_bypass
        FROM inv_locations
        WHERE location_id = in_location_id;
        
        l_chk CHAR(1) := 'N';
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        
        RETURN l_chk;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 'N';
    END;    
    
    
    PROCEDURE sales_rate_correct_same_month (
        in_month_year    IN   VARCHAR2  
    )
    IS
        CURSOR c1
        IS
        SELECT soi.sales_order_item_id,
               so.customer_type,
               soi.item_id
        FROM inv_sales_orders so,
             inv_sales_order_items soi
        WHERE so.sales_order_id = soi.sales_order_id
        AND TRUNC(so.po_date) BETWEEN TO_DATE('01-'||in_month_year) AND LAST_DAY(TO_DATE('01-'||in_month_year))
        AND so.mapics_do_no IS NULL
        AND (soi.rate <> sales_supp.get_cust_type_wise_item_rate(so.customer_type , soi.item_id )
             OR sales_supp.chk_suspense_rate(soi.sales_order_item_id) <> sales_supp.get_suspense_rate(soi.item_id))
        --AND soi.item_id <> 1        [ commented on 18-02-2024 ]
        AND so.customer_id <> 419
        AND so.order_status <> 'CANCELED';
        
    BEGIN
        FOR n IN c1 LOOP
        
            FOR m IN   (SELECT si.sales_invoice_id,         
                               si.gl_voucher_id,
                               sii.item_id,
                               sii.sale_order_item_id,
                               sii.inv_sales_invoice_items_id,
                               sales_supp.get_cust_type_wise_item_rate(n.customer_type, n.item_id) new_item_rate,
                               sales_supp.get_cust_type_wise_vat1(n.customer_type, n.item_id) new_vat_amount1,
                               sales_supp.get_cust_type_wise_vat2(n.customer_type, n.item_id) new_vat_amount2,
                               sales_supp.get_customer_security_rate(n.customer_type, n.item_id) new_security_rate,
                               sales_supp.get_suspense_rate(n.item_id) susp_rate,
                               si.invoice_no,
                               si.company_id,
                               si.branch_id,
                               si.suspense_voucher_id
                        FROM inv_sales_invoices si,
                             inv_sales_invoice_items sii
                        WHERE si.sales_invoice_id = sii.sales_invoice_id
                        AND sii.sale_order_item_id = n.sales_order_item_id) LOOP

                UPDATE inv_sales_order_items 
                SET rate = m.new_item_rate,
                    amount = qty * m.new_item_rate,
                    sales_tax_1 = m.new_vat_amount1,
                    sales_tax_2 = m.new_vat_amount2,
                    vat_amount_1 = qty * m.new_vat_amount1,
                    vat_amount_2 = qty * m.new_vat_amount2,
                    rate1 = m.new_security_rate
                WHERE sales_order_item_id = m.sale_order_item_id;  

          
                UPDATE inv_delivery_challan_items
                SET rate = m.new_item_rate,
                    amount = qty * m.new_item_rate,
                    sales_tax_1 = m.new_vat_amount1,
                    sales_tax_2 = m.new_vat_amount2,
                    vat_amount_1 = qty * m.new_vat_amount1,
                    vat_amount_2 = qty * m.new_vat_amount2,
                    vat_amount = NVL((qty * m.new_vat_amount1),0) + NVL((qty * m.new_vat_amount2),0)
                WHERE sale_order_item_id = m.sale_order_item_id; 
                
            
                UPDATE inv_sales_invoice_items
                SET rate = m.new_item_rate,
                    amount = qty * m.new_item_rate,
                    sales_tax_1 = m.new_vat_amount1,
                    sales_tax_2 = m.new_vat_amount2,
                    vat_amount_1 = qty * m.new_vat_amount1,
                    vat_amount_2 = qty * m.new_vat_amount2,
                    st_amount = NVL((qty * m.new_vat_amount1),0) + NVL((qty * m.new_vat_amount2),0),
                    susp_rate = m.susp_rate
                WHERE inv_sales_invoice_items_id = m.inv_sales_invoice_items_id;
                
                UPDATE inv_sales_invoices si
                SET (invoice_amount, sales_tax_amount, total_invoice_amount) = (SELECT SUM(amount),
                                                                                       SUM(st_amount),
                                                                                       SUM(amount) + SUM(st_amount)
                                                                                FROM inv_sales_invoice_items ii
                                                                                WHERE si.sales_invoice_id = ii.sales_invoice_id
                                                                                AND si.sales_invoice_id = m.sales_invoice_id
                                                                                GROUP BY ii.sales_invoice_id )
                WHERE si.sales_invoice_id = m.sales_invoice_id;
                
                COMMIT;
                
                DELETE FROM mapics_sales 
                WHERE invoice_no = m.invoice_no
                AND company_id = m.company_id
                AND branch_id = m.branch_id;
                        
                COMMIT;
                
                FOR j IN (SELECT receiveable_account_id, 
                                 debit, 
                                 credit 
                          FROM ar_invoice_transfer_v 
                          WHERE sales_invoice_id = m.sales_invoice_id) LOOP
                    UPDATE gl_voucher_accounts 
                    SET debit = j.debit,
                        credit = j.credit
                    WHERE account_id = j.receiveable_account_id
                    AND voucher_id = m.gl_voucher_id;
                    
                    COMMIT;
                
                END LOOP;
                
                FOR k IN (SELECT receiveable_account_id, 
                                 debit, 
                                 credit,
                                 inv_sales_invoice_items_id,
                                 narration
                          FROM ar_invoice_suspense_trn_v 
                          WHERE sales_invoice_id = m.sales_invoice_id) LOOP
                    UPDATE gl_voucher_accounts 
                    SET debit = k.debit,
                        credit = k.credit,
                        naration = k.narration
                    WHERE account_id = k.receiveable_account_id
                    AND voucher_id = m.suspense_voucher_id
                    AND sales_invoice_item_id = k.inv_sales_invoice_items_id ;
                    
                    COMMIT;
                
                END LOOP;
                
            END LOOP;    
        END LOOP;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;  
    
    FUNCTION cust_credit_limit(
        p_customer_id       IN          NUMBER,
        p_comp              IN          VARCHAR2,
        p_branch            IN          VARCHAR2
    ) RETURN NUMBER
    IS
        l_cr_limit      NUMBER;
        l_op_balance    NUMBER;
        l_credit_limit  NUMBER;
        l_do_amt        NUMBER;
        l_tr_amount     NUMBER;
    BEGIN
        SELECT opening_balance,
        credit_limit 
        INTO l_op_balance
        ,l_credit_limit 
        FROM ar_customers_detail
        WHERE customer_id = p_customer_id 
        AND branch_id = p_branch;

        SELECT NVL(SUM(amount),0) + NVL(SUM(amount1),0) + NVL(SUM(vat_amount),0) 
        INTO l_tr_amount
        FROM inv_delivery_challan_items i,
        inv_delivery_challans c
        WHERE i.challan_id = c.challan_id
        AND c.customer_id = p_customer_id
        AND c.delivery_status NOT IN ('INVOICED','CANCELED','CLOSED');
        
        BEGIN
            SELECT SUM (
                 NVL (qty, 0) * NVL (rate, 0) - (  NVL (delivered_qty, 0) * NVL (rate, 0) + NVL (adjusted_qty, 0) * NVL (rate, 0))
               + NVL (qty, 0) * NVL (sales_tax_1, 0) - (  NVL (delivered_qty, 0) * NVL (sales_tax_1, 0) + NVL (adjusted_qty, 0) * NVL (sales_tax_1, 0))
               + NVL (qty, 0) * NVL (sales_tax_2, 0) - (  NVL (delivered_qty, 0) * NVL (sales_tax_2, 0) + NVL (adjusted_qty, 0) * NVL (sales_tax_2, 0))
               + NVL (qty, 0) * NVL (rate1, 0) - (  NVL (delivered_qty, 0) * NVL (rate1, 0) + NVL (adjusted_qty, 0) * NVL (rate1, 0))) 
            INTO l_do_amt
            FROM inv_sales_orders m, inv_sales_order_items d
            WHERE     m.sales_order_id = d.sales_order_id
           AND customer_id = p_customer_id
           AND m.company_id = p_comp
           AND m.branch_id = p_branch
           AND order_status IN ('CREATED', 'SUBMITTED', 'APPROVED')
           AND NVL (qty, 0) - (NVL (delivered_qty, 0) + NVL (adjusted_qty, 0)) > 0 ;
        EXCEPTION
            WHEN no_data_found THEN
            l_do_amt := 0;
        END;

        l_cr_limit :=NVL(l_op_balance,0) + NVL(l_credit_limit,0)-NVL(l_tr_amount,0) - NVL(l_do_amt,0);
        
        RETURN l_cr_limit;
    
    END cust_credit_limit;
    
    FUNCTION check_do_admin (
        in_user_id   IN   NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT sales_do_admin
        FROM sys_users
        WHERE user_id = in_user_id;
        
        l_chk CHAR(1) := 'N';
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        
        RETURN l_chk;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 'N';
    END;
    
    FUNCTION get_bulk_sales_qty (
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR bulk_qty 
        IS
        SELECT SUM(NVL(qty_kgs,0))
        FROM mapics_sales
        WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
        AND company_id = NVL(in_company_id,company_id)
        AND branch_id = NVL(in_branch_id , branch_id) 
        AND item_code = '10001';
        
        l_qty NUMBER;
    BEGIN
        OPEN bulk_qty;
            FETCH bulk_qty INTO l_qty;
        CLOSE bulk_qty;
        
        RETURN l_qty;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END get_bulk_sales_qty;
    
    
    FUNCTION get_cylinder_sales_qty (
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR cylinder_qty 
        IS
        SELECT SUM(qty_pcs)
        FROM mapics_sales
        WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
        AND company_id = in_company_id
        AND branch_id = in_branch_id
        AND item_code IN ('99901','99902','99903','99904','10011','10012','10013','10014');
        
        l_qty NUMBER;
    BEGIN
        OPEN cylinder_qty;
            FETCH cylinder_qty INTO l_qty;
        CLOSE cylinder_qty;
        
        RETURN l_qty;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END get_cylinder_sales_qty;
    
    
    FUNCTION get_bulk_sales_cfy (
        in_to_date     IN  DATE,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT start_date
        FROM gl_fiscal_year
        WHERE end_date = in_to_date;
        l_start_date DATE;
        l_qty NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_start_date;
        CLOSE c1;
        
        IF in_to_date < '30-JUN-2024' THEN
            RETURN 0;
        ELSE
            SELECT SUM(NVL(qty_kgs,0))
            INTO l_qty
            FROM mapics_sales
            WHERE invoice_date BETWEEN l_start_date AND TRUNC(SYSDATE,'MM')-1
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id , branch_id)
            AND item_code = '10001' ;
            
            RETURN l_qty;
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END get_bulk_sales_cfy;
    
    
    FUNCTION get_cylinder_sales_cfy (
        in_to_date     IN  DATE,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT start_date
        FROM gl_fiscal_year
        WHERE end_date = in_to_date;
        l_start_date DATE;
        l_qty NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_start_date;
        CLOSE c1;
        
        IF in_to_date < '30-JUN-2024' THEN
            RETURN 0;
        ELSE
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE invoice_date BETWEEN l_start_date AND TRUNC(SYSDATE,'MM')-1
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code IN ('99901','99902','99903','99904','10011','10012','10013','10014');
            
            RETURN l_qty;
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ebitda_sales_qty_pcs (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        l_qty NUMBER;
    BEGIN
        IF in_level_id = 101 THEN
            l_qty := 0 ;
        ELSIF in_level_id = 102.1 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='99901';
        ELSIF in_level_id = 102.2 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='10011';
        ELSIF in_level_id = 102.3 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99902';
        ELSIF in_level_id = 102.4 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10012';
        ELSIF in_level_id = 102.5 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99904';
        ELSIF in_level_id = 102.6 THEN
            SELECT SUM(qty_pcs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10014';
        END IF;
            
        RETURN l_qty;

    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ebitda_sales_qty_kgs (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        l_qty NUMBER;
    BEGIN
        IF in_level_id = 101 THEN
            SELECT SUM(NVL(qty_kgs,0))
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id , branch_id)
            AND item_code = '10001' ;
        ELSIF in_level_id = 102.1 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='99901';
        ELSIF in_level_id = 102.2 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='10011';
        ELSIF in_level_id = 102.3 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99902';
        ELSIF in_level_id = 102.4 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10012';
        ELSIF in_level_id = 102.5 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99904';
        ELSIF in_level_id = 102.6 THEN
            SELECT SUM(qty_kgs)
            INTO l_qty
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10014';
        END IF;
            
        RETURN l_qty;

    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_ebitda_sales_amount (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        l_amount NUMBER;
    BEGIN
        IF in_level_id = 101 THEN
            SELECT SUM(NVL(amount,0))
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id , branch_id)
            AND item_code = '10001' ;
        ELSIF in_level_id = 102.1 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='99901';
        ELSIF in_level_id = 102.2 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='10011';
        ELSIF in_level_id = 102.3 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99902';
        ELSIF in_level_id = 102.4 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10012';
        ELSIF in_level_id = 102.5 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99904';
        ELSIF in_level_id = 102.6 THEN
            SELECT SUM(amount)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10014';
        END IF;
            
        RETURN l_amount;

    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ebitda_sales_bdt_pmt (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER
    IS
        l_amount NUMBER;
    BEGIN
        IF in_level_id = 101 THEN
            SELECT SUM(NVL(amount,0)) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id , branch_id)
            AND item_code = '10001' ;
        ELSIF in_level_id = 102.1 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='99901';
        ELSIF in_level_id = 102.2 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code ='10011';
        ELSIF in_level_id = 102.3 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99902';
        ELSIF in_level_id = 102.4 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10012';
        ELSIF in_level_id = 102.5 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '99904';
        ELSIF in_level_id = 102.6 THEN
            SELECT SUM(amount) / ROUND(SUM(NULLIF(qty_kgs,0)) / 1000)
            INTO l_amount
            FROM mapics_sales
            WHERE TO_CHAR(invoice_date, 'MON-RRRR') = in_month_year
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND item_code = '10014';
        END IF;
            
        RETURN l_amount;

    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;

    FUNCTION get_suspense_rate (
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT p.item_rate
        FROM inv_sales_price_d p,
             inv_sales_price_m m
        WHERE P.PRICE_ID = M.PRICE_ID
        AND m.price_status = 'APPROVED'
        AND p.status = 'APPROVED'
        AND p.item_id = in_item_id
        AND m.customer_type = 10;
        
        l_suspense_rate NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_suspense_rate;
        CLOSE c1;
        
        RETURN l_suspense_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION chk_suspense_rate (
        in_sale_order_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT DISTINCT susp_rate
        FROM inv_sales_invoice_items
        WHERE sale_order_item_id = in_sale_order_item_id;
        l_suspense_rate NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_suspense_rate;
        CLOSE c1;
        RETURN l_suspense_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE ins_transport_cost_auto_gas (
        in_rate         IN   NUMBER
    )
    IS
        CURSOR c1
        IS 
        SELECT *
        FROM inv_dist_transport_m
        WHERE location_id = 34
        AND status = 'APPROVED';

        l_trans_mst_id NUMBER;
        l_trans_mst_no NUMBER;
        l_trans_dtl_id NUMBER;
    BEGIN
        FOR i IN c1 LOOP
            SELECT NVL(MAX(trans_cost_id),0)+1 
            INTO l_trans_mst_id
            FROM inv_dist_transport_m;

            SELECT NVL(MAX(trans_cost_no),0)+1 
            INTO l_trans_mst_no
            FROM inv_dist_transport_m
            WHERE company_id= i.company_id
            AND branch_id=i.branch_id;
            
            INSERT INTO inv_dist_transport_m (
                trans_cost_id, 
                trans_cost_no, 
                customer_id, 
                location_id, 
                dist_point_id, 
                company_id, 
                branch_id, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_updated_date, 
                status, 
                approved_by, 
                approved_date, 
                closed_by, 
                closed_date
            )
            VALUES (
                l_trans_mst_id, 
                l_trans_mst_no, 
                i.customer_id, 
                i.location_id, 
                i.dist_point_id, 
                i.company_id, 
                i.branch_id, 
                109, 
                SYSDATE, 
                NULL, 
                NULL, 
                'CREATED', 
                NULL, 
                NULL, 
                NULL, 
                NULL
            );
            
            FOR j IN (SELECT *
                      FROM inv_dist_transport_d
                      WHERE trans_cost_id IN (
                          SELECT trans_cost_id
                          FROM inv_dist_transport_m
                          WHERE location_id = 34
                          AND status = 'APPROVED'
                          AND trans_cost_id = i.trans_cost_id
                     )) LOOP
                SELECT NVL(MAX(trans_item_id),0)+1 
                INTO l_trans_dtl_id
                FROM inv_dist_transport_d;
                
                INSERT INTO inv_dist_transport_d (
                    trans_item_id, 
                    trans_cost_id, 
                    item_id, 
                    rate, 
                    status, 
                    created_by, 
                    creation_date, 
                    updated_by, 
                    updated_date, 
                    approved_by, 
                    approved_date, 
                    closed_by, 
                    closed_date, 
                    cost_type
                )
                VALUES (
                    l_trans_dtl_id, 
                    l_trans_mst_id, 
                    j.item_id, 
                    in_rate, 
                    'CREATED', 
                    109, 
                    SYSDATE, 
                    NULL, 
                    NULL, 
                    NULL, 
                    NULL, 
                    NULL, 
                    NULL, 
                    NULL
                );
                
            END LOOP;
            
        END LOOP;       
        
        COMMIT;
        
        /*
        --> THIS BELOW CODE NEED TO BE EXECUTED 
        UPDATE inv_dist_transport_d
        SET status = 'CLOSED',
            closed_by = 109,
            closed_date = SYSDATE
        WHERE trans_cost_id IN (
          SELECT trans_cost_id
          FROM inv_dist_transport_m
          WHERE location_id = 34
          AND status = 'APPROVED'
        );

        UPDATE inv_dist_transport_m
        SET status = 'CLOSED',
            closed_by = 109,
            closed_date = SYSDATE
        WHERE location_id = 34
        AND status = 'APPROVED';

        UPDATE inv_dist_transport_d
        SET status = 'APPROVED',
            approved_by = 109,
            approved_date = SYSDATE
        WHERE trans_cost_id IN (
          SELECT trans_cost_id
          FROM inv_dist_transport_m
          WHERE location_id = 34
          AND status = 'CREATED'
        );

        UPDATE inv_dist_transport_m
        SET status = 'APPROVED',
            approved_by = 109,
            approved_date = SYSDATE
        WHERE location_id = 34
        AND status = 'CREATED';
        */
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION get_customer_package_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR pkg_qty
        IS
        SELECT SUM(new_balance_qty) balance_qty
        FROM (
            SELECT (SELECT customer_id_old FROM ar_customers WHERE customer_id = a.customer_id) customer_code,
                   (SELECT REGEXP_REPLACE (customer_name, '[0-9]', '') FROM ar_customers WHERE customer_id = a.customer_id) customer_name,
                   c.long_desc item_desc,
                   (SUM (NVL (b.qty, 0))
                  - NVL (
                       (SELECT SUM (recived_qty)
                        FROM inv_delivery_challan_reference
                        WHERE customer_id = a.customer_id
                        AND item_id = c.pack_item_id
                        AND status <> 'CANCELED'
                        AND creation_date <= LAST_DAY(TO_DATE('01-'||in_month_year))),
                       0)
                  - NVL (
                       (SELECT SUM (adjusted_qty)
                        FROM inv_delivery_challan_reference
                        WHERE customer_id = a.customer_id
                        AND item_id = c.pack_item_id
                        AND status <> 'CANCELED'
                        AND creation_date <= LAST_DAY(TO_DATE('01-'||in_month_year))),
                       0)
                    )
                    bal_qty,
                    NVL(rtn.return_qty,0) return_qty,
                    SUM (NVL (b.qty, 0)) - NVL(rtn.return_qty,0) new_balance_qty,
                    a.customer_id,
                    b.item_id,
                    a.company_id
            FROM inv_sales_invoices a, 
                 inv_sales_invoice_items b, 
                 inv_items c,
                 (
                 /*SELECT (SELECT r_customer_id FROM inv_vendors WHERE vendor_id = ilr.vendor_id AND vendor_type = 'CUSTOMER') customer_id,
                        (SELECT item_id FROM inv_items WHERE pack_item_id = ilri.item_id AND segment1 = '91') item_id,
                        SUM(ilri.received_qty) return_qty
                 FROM inv_loans_receive ilr,
                      inv_loan_receive_items ilri
                 WHERE ilr.loan_rec_id = ilri.loan_rec_id   
                 AND TRUNC(ilr.approved_date) <= TRUNC(LAST_DAY(TO_DATE('01-'||in_month_year)))
                 AND ilr.location_id = 33 
                 GROUP BY ilri.item_id,
                          ilr.vendor_id
                 ) */
                 
                 SELECT (SELECT r_customer_id FROM inv_vendors WHERE vendor_id = ilr.vendor_id AND vendor_type = 'CUSTOMER') customer_id,
                        (SELECT item_id FROM inv_items WHERE pack_item_id = ilri.item_id AND segment1 = '91') item_id,
                         SUM(ilri.igp_qty) return_qty
                 FROM inv_rigps ilr,
                      inv_rigp_items ilri
                 WHERE ilr.rigp_id = ilri.rigp_id   
                 AND TRUNC(ilr.creation_date) <= TRUNC(LAST_DAY(TO_DATE('01-'||in_month_year)))
                 AND rigp_type = 'PACKAGE'
                 GROUP BY ilri.item_id,
                          ilr.vendor_id
                          )rtn
            WHERE  a.sales_invoice_id = b.sales_invoice_id
            AND b.item_id = c.item_id
            AND a.customer_id = rtn.customer_id(+)
            AND c.item_id = rtn.item_id(+)
            AND c.segment1 = '91'
            AND a.invoice_status <> 'CANCELED'
            AND a.company_id = NVL(in_company_id,a.company_id)
            AND a.branch_id = NVL(in_branch_id,a.branch_id)
            AND a.customer_id = NVL (in_customer_id, a.customer_id)
            AND TRUNC (a.invoice_date) <= TRUNC (LAST_DAY(TO_DATE('01-'||in_month_year)))
            GROUP BY a.customer_id,
                     b.item_id,
                     c.item_code,
                     c.long_desc,
                     a.company_id,
                     c.pack_item_id,
                     rtn.return_qty
            ORDER BY 1
        );
            
        l_pkg_qty NUMBER;
    BEGIN
        OPEN pkg_qty;
            FETCH pkg_qty INTO l_pkg_qty;
        CLOSE pkg_qty;
        RETURN l_pkg_qty;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_customer_target_refill_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER
    IS
        l_target_qty NUMBER;
        l_pct NUMBER := 4.5;
    BEGIN
        l_target_qty := FLOOR(sales_supp.get_customer_package_qty (
                                    in_company_id   =>  in_company_id,
                                    in_branch_id    =>  in_branch_id,
                                    in_customer_id  =>  in_customer_id,
                                    in_month_year   =>  in_month_year
                                ) /  l_pct);  
        RETURN l_target_qty;             
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_customer_actual_refill_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR refill_qty
        IS
        SELECT SUM (NVL (b.qty, 0)) refill_qty
        FROM inv_sales_invoices a, 
             inv_sales_invoice_items b, 
             inv_items c
        WHERE  a.sales_invoice_id = b.sales_invoice_id
        AND b.item_id = c.item_id
        AND c.segment1 = '92'
        AND a.company_id = in_company_id
        AND a.branch_id = in_branch_id
        AND a.customer_id = in_customer_id
        AND TO_CHAR (a.invoice_date, 'MON-RRRR') = in_month_year
        AND a.invoice_status <> 'CANCELED';
        l_refill_qty NUMBER;
    BEGIN
        OPEN refill_qty;
            FETCH refill_qty INTO l_refill_qty;
        CLOSE refill_qty;
        RETURN l_refill_qty;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_customer_monthly_score (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER
    IS
        l_score NUMBER;
    BEGIN
        l_score := sales_supp.get_customer_actual_refill_qty (
                            in_company_id   =>  in_company_id,
                            in_branch_id    =>  in_branch_id,
                            in_customer_id  =>  in_customer_id,
                            in_month_year   =>  in_month_year
                        ) / 
                        sales_supp.get_customer_target_refill_qty (
                            in_company_id   =>  in_company_id,
                            in_branch_id    =>  in_branch_id,
                            in_customer_id  =>  in_customer_id,
                            in_month_year   =>  in_month_year
                        ) * 100;
        RETURN l_score;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_customer_monthly_category (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN VARCHAR2
    IS
        l_final_pct NUMBER;
        l_category VARCHAR2(100);
    BEGIN
        l_final_pct := sales_supp.get_customer_actual_refill_qty (
                            in_company_id   =>  in_company_id,
                            in_branch_id    =>  in_branch_id,
                            in_customer_id  =>  in_customer_id,
                            in_month_year   =>  in_month_year
                        ) / 
                        sales_supp.get_customer_target_refill_qty (
                            in_company_id   =>  in_company_id,
                            in_branch_id    =>  in_branch_id,
                            in_customer_id  =>  in_customer_id,
                            in_month_year   =>  in_month_year
                        ) * 100;
                        
        IF l_final_pct >= 90 THEN
            l_category := 'Platinum';
        ELSIF l_final_pct >= 75 AND l_final_pct < 90 THEN
            l_category := 'Gold';
        ELSIF l_final_pct >= 50 AND l_final_pct < 75 THEN
            l_category := 'Silver';
        ELSIF l_final_pct >= 25 AND l_final_pct < 50 THEN
            l_category := 'Bronze';
        ELSIF l_final_pct < 25 THEN
            l_category := 'Non Performer';
        END IF;
        RETURN l_category;          
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_customer_category_range (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_start_date   IN   VARCHAR2,
        in_end_date     IN   VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        WITH month_data AS (
            SELECT ADD_MONTHS(to_date(in_start_date, 'DD-MON-RRRR'), LEVEL - 1) AS dt
            FROM DUAL
            CONNECT BY LEVEL <= MONTHS_BETWEEN(to_date(in_end_date, 'DD-MON-RRRR'), to_date(in_start_date, 'DD-MON-RRRR')) + 1
        )
        SELECT TO_CHAR(dt, 'MON-RRRR') AS month_year
        FROM month_data;
        
        CURSOR c2
        IS
        SELECT COUNT(*)
        FROM (
            WITH month_data AS (
                SELECT ADD_MONTHS(to_date(in_start_date, 'DD-MON-RRRR'), LEVEL - 1) AS dt
                FROM DUAL
                CONNECT BY LEVEL <= MONTHS_BETWEEN(to_date(in_end_date, 'DD-MON-RRRR'), to_date(in_start_date, 'DD-MON-RRRR')) + 1
            )
            SELECT TO_CHAR(dt, 'MON-RRRR') AS month_year
            FROM month_data
        );
        l_score NUMBER := 0;
        l_cnt NUMBER;
        l_category VARCHAR2(100);
        l_final_pct NUMBER;
    BEGIN
        OPEN c2;
            FETCH c2 INTO l_cnt;
        CLOSE c2;
        
        FOR m IN c1 LOOP
            l_score := l_score + NVL(sales_supp.get_customer_monthly_score (
                                    in_company_id   =>  in_company_id,
                                    in_branch_id    =>  in_branch_id,
                                    in_customer_id  =>  in_customer_id,
                                    in_month_year   =>  m.month_year
                                 ),0);
        END LOOP;
        
        l_final_pct := l_score / l_cnt;
        
        IF l_final_pct >= 90 THEN
            l_category := 'Platinum';
        ELSIF l_final_pct >= 75 AND l_final_pct < 90 THEN
            l_category := 'Gold';
        ELSIF l_final_pct >= 50 AND l_final_pct < 75 THEN
            l_category := 'Silver';
        ELSIF l_final_pct >= 25 AND l_final_pct < 50 THEN
            l_category := 'Bronze';
        ELSIF l_final_pct < 25 THEN
            l_category := 'Non Performer';
        END IF;
        
        RETURN l_category;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE ins_customer_cat_period (
        in_fiscal_year  IN    NUMBER,
        in_sector       IN    NUMBER
    )
    IS
        pid NUMBER;
        i NUMBER;
    BEGIN
        SELECT NVL(MAX(period_id),0)+1
        INTO pid
        FROM ar_customer_cat_period_define;
        
        i := in_fiscal_year;
        
        IF in_sector = 1 THEN
            INSERT INTO ar_customer_cat_period_define (
                period_id, 
                start_date, 
                end_date, 
                sector_no, 
                fiscal_year, 
                period_type, 
                month_1, 
                month_2, 
                month_3, 
                month_4, 
                month_5, 
                month_6, 
                month_7, 
                month_8, 
                month_9, 
                month_10, 
                month_11, 
                month_12, 
                company_id, 
                branch_id, 
                is_active, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_updated_date  
            )
            VALUES (
                pid,
                TO_DATE('01-07-'||i , 'DD-MM-RRRR'),
                TO_DATE('30-09-'||i , 'DD-MM-RRRR'),
                1,
                i+1,
                'Quarterly',
                'JUL-'||i,
                'AUG-'||i,
                'SEP-'||i,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                1,
                '01',
                'Y',
                109,
                SYSDATE,
                NULL,
                NULL  
            );
        ELSIF in_sector = 2 THEN
            INSERT INTO ar_customer_cat_period_define (
                period_id, 
                start_date, 
                end_date, 
                sector_no, 
                fiscal_year, 
                period_type, 
                month_1, 
                month_2, 
                month_3, 
                month_4, 
                month_5, 
                month_6, 
                month_7, 
                month_8, 
                month_9, 
                month_10, 
                month_11, 
                month_12, 
                company_id, 
                branch_id, 
                is_active, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_updated_date 
            )
            VALUES (
                pid,
                TO_DATE('01-10-'||i , 'DD-MM-RRRR'),
                TO_DATE('31-12-'||i , 'DD-MM-RRRR'), 
                2,
                i+1,
                'Quarterly',
                'OCT-'||i,
                'NOV-'||i,
                'DEC-'||i,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                1,
                '01',
                'Y',
                109,
                SYSDATE,
                NULL,
                NULL   
            );
        ELSIF in_sector = 3 THEN
            INSERT INTO ar_customer_cat_period_define (
                period_id, 
                start_date, 
                end_date, 
                sector_no, 
                fiscal_year, 
                period_type, 
                month_1, 
                month_2, 
                month_3, 
                month_4, 
                month_5, 
                month_6, 
                month_7, 
                month_8, 
                month_9, 
                month_10, 
                month_11, 
                month_12, 
                company_id, 
                branch_id, 
                is_active, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_updated_date
            )
            VALUES (
                pid,
                TO_DATE('01-01-'||(i+1) , 'DD-MM-RRRR'),
                TO_DATE('31-03-'||(i+1) , 'DD-MM-RRRR'),
                3,
                i+1,
                'Quarterly',
                'JAN-'||(i+1),
                'FEB-'||(i+1),
                'MAR-'||(i+1),
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                1,
                '01',
                'Y',
                109,
                SYSDATE,
                NULL,
                NULL    
            );
        ELSIF in_sector = 4 THEN
            INSERT INTO ar_customer_cat_period_define (
                period_id, 
                start_date, 
                end_date, 
                sector_no, 
                fiscal_year, 
                period_type, 
                month_1, 
                month_2, 
                month_3, 
                month_4, 
                month_5, 
                month_6, 
                month_7, 
                month_8, 
                month_9, 
                month_10, 
                month_11, 
                month_12, 
                company_id, 
                branch_id, 
                is_active, 
                created_by, 
                creation_date, 
                last_updated_by, 
                last_updated_date 
            )
            VALUES (
                pid,
                TO_DATE('01-04-'||(i+1) , 'DD-MM-RRRR'),
                TO_DATE('30-06-'||(i+1) , 'DD-MM-RRRR'),
                4,
                i+1,
                'Quarterly',
                'APR-'||(i+1),
                'MAY-'||(i+1),
                'JUN-'||(i+1),
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                1,
                '01',
                'Y',
                109,
                SYSDATE,
                NULL,
                NULL  
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_customer_cat_detail (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_period_id    IN   NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT customer_id
        FROM ar_customers 
        WHERE customer_type IN ('1','2','3');
        
        CURSOR c2
        IS
        SELECT start_date + level - 1 AS category_date
        FROM (
            SELECT start_date, end_date
            FROM ar_customer_cat_period_define
            WHERE period_id = in_period_id
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND is_active = 'Y'
        ) date_range
        CONNECT BY level <= (TRUNC(end_date) - TRUNC(start_date) + 1);
        
        l_dtl_id NUMBER;
        l_category VARCHAR2(50);
        l_start_date DATE;
        l_end_date DATE;
        l_current_sector_no NUMBER;
        l_current_fiscal_year NUMBER;
        l_next_sector_no NUMBER;
        l_next_fiscal_year NUMBER;
    BEGIN
        FOR i IN c1 LOOP
            
            SELECT start_date, 
                   end_date,
                   sector_no,
                   fiscal_year
            INTO l_start_date,
                 l_end_date,
                 l_current_sector_no,
                 l_current_fiscal_year
            FROM ar_customer_cat_period_define
            WHERE period_id = in_period_id
            AND company_id = in_company_id
            AND branch_id = in_branch_id
            AND is_active = 'Y';
            
            l_category := get_customer_category_range (
                              in_company_id   => in_company_id,
                              in_branch_id    => in_branch_id,
                              in_customer_id  => i.customer_id,
                              in_start_date   => l_start_date,
                              in_end_date     => l_end_date
                           );
        
            FOR j IN c2 LOOP
            
                SELECT NVL(MAX(dtl_id),0)+1
                INTO l_dtl_id
                FROM ar_customer_cat_detail;
                
                INSERT INTO ar_customer_cat_detail (
                    dtl_id, 
                    period_id, 
                    customer_id, 
                    category_date, 
                    customer_category, 
                    is_active, 
                    created_by, 
                    creation_date, 
                    last_updated_by, 
                    last_updated_date
                )
                VALUES (
                    l_dtl_id,
                    in_period_id,
                    i.customer_id,
                    j.category_date,
                    l_category,
                    'Y',
                    109,
                    SYSDATE,
                    NULL,
                    NULL
                );
                
            END LOOP;
            
        END LOOP;
        
        COMMIT;
        
        IF l_current_sector_no <> 4 THEN
            l_next_sector_no := l_current_sector_no + 1;
            l_next_fiscal_year := l_current_fiscal_year;
        ELSE
            l_next_sector_no := 1;
            l_next_fiscal_year := l_current_fiscal_year + 1;
        END IF;
        
        ins_customer_cat_period (
            in_fiscal_year  => l_next_fiscal_year-1,
            in_sector       => l_next_sector_no
        );
        
        UPDATE ar_customer_cat_period_define
        SET is_active = 'N'
        WHERE period_id = in_period_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE update_challan_reference (
        in_customer_id  IN   NUMBER,
        in_item_id      IN   NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT customer_id,
               transfer_item_id,
               ROUND(adjustement) rem_qty
        FROM ref_prob_customer
        WHERE adjustement > 0
        AND customer_id = NVL(in_customer_id,customer_id)
        AND transfer_item_id = NVL(in_item_id,transfer_item_id);
        
        CURSOR c2
        IS
        SELECT customer_id,
               transfer_item_id,
               ROUND(adjustement) * -1 rem_qty
        FROM ref_prob_customer
        WHERE adjustement < 0
        AND customer_id = NVL(in_customer_id,customer_id)
        AND transfer_item_id = NVL(in_item_id,transfer_item_id);
        
        l_upd_qty NUMBER := 0;
        l_rem_qty NUMBER := 0;
    BEGIN
        FOR i IN c1 LOOP
            l_rem_qty := i.rem_qty;
            FOR j IN (SELECT reference_id,
                             customer_id,
                             item_id,
                             qty,
                             NVL(recived_qty,0) recived_qty,
                             NVL(adjusted_qty,0) adjusted_qty
                      FROM inv_delivery_challan_reference
                      WHERE customer_id = i.customer_id
                      AND item_id = i.transfer_item_id
                      AND status <> 'CANCELED'
                      ORDER BY reference_id DESC) 
            LOOP
                IF l_upd_qty < i.rem_qty THEN
                    IF j.recived_qty < j.qty THEN
                        IF j.qty - j.recived_qty < i.rem_qty THEN
                            IF l_rem_qty >  (j.qty - j.recived_qty) THEN
                                UPDATE inv_delivery_challan_reference
                                SET recived_qty = NVL(recived_qty,0) + (j.qty - j.recived_qty),
                                    is_updated = 'Y'
                                WHERE item_id = j.item_id
                                AND customer_id = j.customer_id
                                AND reference_id = j.reference_id;
                                l_upd_qty :=  l_upd_qty + (j.qty - j.recived_qty);
                                l_rem_qty :=  l_rem_qty - (j.qty - j.recived_qty);
                            ELSE
                                UPDATE inv_delivery_challan_reference
                                SET recived_qty = NVL(recived_qty,0) + l_rem_qty,
                                    is_updated = 'Y'
                                WHERE item_id = j.item_id
                                AND customer_id = j.customer_id
                                AND reference_id = j.reference_id;
                                l_upd_qty := l_upd_qty + (j.qty - j.recived_qty);
                                l_rem_qty :=  l_rem_qty - (j.qty - j.recived_qty);
                            END IF;
                        ELSE
                            UPDATE inv_delivery_challan_reference
                            SET recived_qty = NVL(recived_qty,0) + l_rem_qty, --i.rem_qty,
                                is_updated = 'Y'
                            WHERE item_id = j.item_id
                            AND customer_id = j.customer_id
                            AND reference_id = j.reference_id;
                            l_upd_qty := l_upd_qty + l_rem_qty; -- i.rem_qty
                        END IF;
                    END IF;
                END IF;
            END LOOP;
            l_upd_qty := 0;
            l_rem_qty := 0;
        END LOOP;
     
       
        FOR i IN c2 LOOP
            l_rem_qty := i.rem_qty;
            FOR j IN (SELECT reference_id,
                             customer_id,
                             item_id,
                             qty,
                             NVL(recived_qty,0) recived_qty,
                             NVL(adjusted_qty,0) adjusted_qty
                      FROM inv_delivery_challan_reference
                      WHERE customer_id = i.customer_id
                      AND item_id = i.transfer_item_id
                      AND status <> 'CANCELED'
                      AND recived_qty IS NOT NULL
                      ORDER BY qty ASC) 
            LOOP
                IF l_upd_qty < i.rem_qty THEN
                    --IF j.recived_qty < j.qty THEN
                        IF j.recived_qty < i.rem_qty THEN
                            IF l_rem_qty >  (j.recived_qty) THEN
                                UPDATE inv_delivery_challan_reference
                                SET recived_qty = NVL(recived_qty,0) - (j.recived_qty),
                                    is_updated = 'Y'
                                WHERE item_id = j.item_id
                                AND customer_id = j.customer_id
                                AND reference_id = j.reference_id;
                                l_upd_qty := l_upd_qty + (j.recived_qty);
                                l_rem_qty :=  l_rem_qty - (j.recived_qty);
                            ELSE
                                UPDATE inv_delivery_challan_reference
                                SET recived_qty = NVL(recived_qty,0) - l_rem_qty,
                                    is_updated = 'Y'
                                WHERE item_id = j.item_id
                                AND customer_id = j.customer_id
                                AND reference_id = j.reference_id;
                                l_upd_qty := l_upd_qty + (j.recived_qty);
                                l_rem_qty :=  l_rem_qty - (j.recived_qty);
                            END IF;
                        ELSE
                            UPDATE inv_delivery_challan_reference
                            SET recived_qty = NVL(recived_qty,0) - l_rem_qty,
                                is_updated = 'Y'
                            WHERE item_id = j.item_id
                            AND customer_id = j.customer_id
                            AND reference_id = j.reference_id;
                            l_upd_qty := l_upd_qty + l_rem_qty;
                        END IF;
                   -- END IF;
                END IF;
            END LOOP;
            l_upd_qty := 0;
            l_rem_qty := 0;
        END LOOP;
        
        
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
END sales_supp;
/
