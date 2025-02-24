CREATE OR REPLACE PACKAGE BODY inv_supp
IS  
    FUNCTION get_current_stock (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(qty)
        FROM inv_stock_ledger
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        
        l_current_stock NUMBER := 0;    
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_current_stock;
        CLOSE c1;
        RETURN l_current_stock;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_current_rate (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT ROUND((SUM(amount) / NULLIF(SUM(qty),0)),4) rate
        FROM inv_stock_ledger
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        
        l_current_rate NUMBER := 0;    
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_current_rate;
        CLOSE c1;
        RETURN l_current_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE upd_stock_balance (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_qty IN NUMBER,
        in_amount IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT COUNT(*)
        FROM inv_stock_balance
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        l_cnt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_cnt;
        CLOSE c1;
        
        IF l_cnt > 0 THEN
            IF in_qty >= 0 THEN
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_avg_rate = (NVL(cur_amount,0) + in_amount) / (NVL(cur_stock,0) + in_qty),
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            ELSE
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            END IF;
        ELSE
            INSERT INTO inv_stock_balance (
                company_id, 
                branch_id, 
                location_id, 
                item_id, 
                cur_stock, 
                cur_avg_rate, 
                cur_amount, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date
             )
             VALUES (
                in_company_id,
                in_branch_id,
                in_location_id,
                in_item_id,
                in_qty,
                in_amount / NULLIF(in_qty,0),
                in_amount,
                in_user_id,
                SYSDATE,
                NULL,
                NULL
             );
        END IF;

        COMMIT;
        
        --inv_supp.sync_stock_balance;

    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    PROCEDURE upd_stock_balance_trg (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_qty IN NUMBER,
        in_amount IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT COUNT(*)
        FROM inv_stock_balance
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        l_cnt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_cnt;
        CLOSE c1;
        
        IF l_cnt > 0 THEN
            IF in_qty >= 0 THEN
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_avg_rate = (NVL(cur_amount,0) + in_amount) / (NVL(cur_stock,0) + in_qty),
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            ELSE
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            END IF;
        ELSE
            INSERT INTO inv_stock_balance (
                company_id, 
                branch_id, 
                location_id, 
                item_id, 
                cur_stock, 
                cur_avg_rate, 
                cur_amount, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date
             )
             VALUES (
                in_company_id,
                in_branch_id,
                in_location_id,
                in_item_id,
                in_qty,
                in_amount / NULLIF(in_qty,0),
                in_amount,
                in_user_id,
                SYSDATE,
                NULL,
                NULL
             );
        END IF;
        --COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR (-20001, SQLERRM);
    END;
    
    
    PROCEDURE merge_stock_balance (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_qty IN NUMBER,
        in_amount IN NUMBER,
        in_user_id IN NUMBER,
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT COUNT(*)
        FROM inv_stock_balance
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        l_cnt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_cnt;
        CLOSE c1;
        
        IF l_cnt > 0 THEN
            IF in_qty >= 0 THEN
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_avg_rate = (NVL(cur_amount,0) + in_amount) / (NVL(cur_stock,0) + in_qty),
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            ELSE
                UPDATE inv_stock_balance 
                SET cur_stock = NVL(cur_stock,0) + in_qty,
                    cur_amount = NVL(cur_amount,0) + in_amount,
                    last_updated_by = in_user_id,
                    last_updated_date = SYSDATE
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND location_id = in_location_id 
                AND item_id = in_item_id;
            END IF;
        ELSE
            INSERT INTO inv_stock_balance (
                company_id, 
                branch_id, 
                location_id, 
                item_id, 
                cur_stock, 
                cur_avg_rate, 
                cur_amount, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date
             )
             VALUES (
                in_company_id,
                in_branch_id,
                in_location_id,
                in_item_id,
                in_qty,
                in_amount / NULLIF(in_qty,0),
                in_amount,
                in_user_id,
                SYSDATE,
                NULL,
                NULL
             );
        END IF;
        
        COMMIT;   
        
        --inv_supp.sync_stock_balance;
    EXCEPTION
        WHEN OTHERS THEN
        --inv_supp.sync_stock_balance;
        out_error_code := SQLCODE;
        out_error_code := SQLERRM;
    END;
    
    PROCEDURE ins_stock_balance (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
    BEGIN
        INSERT INTO inv_stock_balance (
            company_id, 
            branch_id, 
            location_id, 
            item_id, 
            cur_stock, 
            cur_avg_rate, 
            cur_amount, 
            created_by, 
            creation_date,
            last_updated_by, 
            last_updated_date
        )
        VALUES (
            in_company_id,
            in_branch_id,
            in_location_id,
            in_item_id,
            0,
            0,
            0,
            in_user_id,
            SYSDATE,
            NULL,
            NULL
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE pop_stock_balance (
        in_company_id IN NUMBER,
        in_item_id IN NUMBER,
        in_user_id IN NUMBER,
        in_item_main_category IN VARCHAR2
    )
    IS
        CURSOR bran
        IS
        SELECT branch_id
        FROM sys_branches
        WHERE company_no = in_company_id
        AND active = 'Y';
        
        CURSOR loc
        IS
        SELECT location_id
        FROM inv_locations
        WHERE is_active = 'Y';
        --AND INSTR(','||item_main_category||',' ,  in_item_main_category) > 0 ;
   
        l_cnt NUMBER := 0;

    BEGIN   
    
        FOR i IN bran LOOP
        
            FOR j IN loc LOOP
                
                BEGIN
                    SELECT COUNT(*)
                    INTO l_cnt 
                    FROM inv_stock_balance
                    WHERE company_id = in_company_id
                    AND branch_id = i.branch_id
                    AND location_id = j.location_id
                    AND item_id = in_item_id;
                EXCEPTION
                    WHEN OTHERS THEN
                    l_cnt := 0;
                END;
                
                IF l_cnt = 0 THEN
                
                    ins_stock_balance (
                        in_company_id  => in_company_id,
                        in_branch_id   => i.branch_id,
                        in_location_id => j.location_id,
                        in_item_id     => in_item_id,
                        in_user_id     => in_user_id
                    );
                    
                END IF;
                
            END LOOP;
            
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    PROCEDURE pop_stock_balance_loc (
        in_company_id IN NUMBER,
        in_location_id IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
        CURSOR bran
        IS
        SELECT branch_id
        FROM sys_branches
        WHERE company_no = in_company_id
        AND active = 'Y';
        
        CURSOR itm
        IS
        SELECT item_id
        FROM inv_items
        WHERE is_active = 'Y';
   
        l_cnt NUMBER := 0;

    BEGIN   
    
        FOR i IN bran LOOP
        
            FOR j IN itm LOOP
                
                BEGIN
                    SELECT COUNT(*)
                    INTO l_cnt 
                    FROM inv_stock_balance
                    WHERE company_id = in_company_id
                    AND branch_id = i.branch_id
                    AND location_id = in_location_id
                    AND item_id = j.item_id;
                EXCEPTION
                    WHEN OTHERS THEN
                    l_cnt := 0;
                END;
                
                IF l_cnt = 0 THEN
                
                    ins_stock_balance (
                        in_company_id  => in_company_id,
                        in_branch_id   => i.branch_id,
                        in_location_id => in_location_id,
                        in_item_id     => j.item_id,
                        in_user_id     => in_user_id
                    );
                    
                END IF;
                
            END LOOP;
            
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION get_curr_stock_no_calc (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT cur_stock
        FROM inv_stock_balance
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        l_qty NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_qty;
        CLOSE c1;
        RETURN l_qty;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION get_curr_rate_no_calc (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT cur_avg_rate
        FROM inv_stock_balance
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND location_id = in_location_id
        AND item_id = in_item_id;
        l_avg_rate NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_avg_rate;
        CLOSE c1;
        RETURN l_avg_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
        -- This function is for getting transfer location
           if it is issued into the production floor.
           Actually it is for checking whether it is production issue or not.
           If production issue then RM stock will decrease and WIP stock will increase.  RM (-) and WIP(+)
           After production entry WIP stock will decrease and FG stock will increase.    WIP(-) and FG (+)
    */
    
    
    FUNCTION get_transfer_location (
        in_location_id IN NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT NVL(transfer_location_id,0)
        FROM inv_locations
        WHERE location_id = in_location_id;
        
        l_transfer_location_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_transfer_location_id;
        CLOSE c1;
        RETURN l_transfer_location_id;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE upd_wip_store (
        in_issue_id IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
        CURSOR c1 
        IS
        SELECT im.item_id,
               ROUND (ism.issue_rate, 4) rate,
               ism.issue_qty qty,
               isi.sin_id,
               isi.company_id,
               isi.branch_id,
               im.location_id
        FROM inv_sin_mirs ism, 
             inv_mirs im,
             inv_sins isi
        WHERE ism.mir_id = im.mir_id 
        AND ism.sin_id = isi.sin_id
        AND isi.sin_id = in_issue_id;
    BEGIN
        FOR m IN c1 LOOP
            inv_supp.upd_stock_balance (
                in_company_id  => m.company_id,
                in_branch_id   => m.branch_id,
                in_location_id => inv_supp.get_transfer_location(m.location_id),
                in_item_id     => m.item_id,
                in_qty         => m.qty,
                in_amount      => m.qty * m.rate,
                in_user_id     => in_user_id
            );
        END LOOP;
                
        --inv_supp.sync_stock_balance;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
        -- This procedure is created for auto insertion on Indent and CS during creation of PI.
    */
    
    PROCEDURE ins_indent_cs_from_pi (
        in_pi_id IN NUMBER,
        in_user_id IN NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT pim.vendor_id,
               pim.currency,
               pim.company_id,
               pim.branch_id,
               pid.location_id,
               '01' purchase_group_id,   -- hard coded , purchase group as 'Production import'
               4 dept_id,                -- hard coded, dept = commercial
               pid.item_id,
               pid.qty,
               ii.uom,
               pid.rate,
               pim.exch_rate,
               pim.freight,
               pim.packing_cost,
               pim.tooling_cost,
               pim.other_cost
        FROM performa_inv_master pim,
             perform_inv_detail pid,
             inv_items ii
        WHERE pim.p_inv_m_id = pid.p_inv_m_id
        AND pid.item_id = ii.item_id
        AND pim.p_inv_m_id = in_pi_id;
        l_indent_id NUMBER;
        l_indent_no NUMBER;
        l_location_name VARCHAR2(100);
        l_cs_id NUMBER;
        l_cs_no NUMBER;
        l_cs_item_id NUMBER;
        l_cs_item_vendor_id NUMBER;
        loop_counter NUMBER := 0;
    BEGIN
        FOR m IN c1 LOOP
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_id
            FROM inv_indents;
            
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_no
            FROM inv_indents
            WHERE company_id = m.company_id
            AND branch_id = m.branch_id;
            
            SELECT location_name
            INTO l_location_name
            FROM inv_locations
            WHERE location_id = m.location_id;
            
            INSERT INTO inv_indents (
                indent_id,
                indent_no,
                company_id,
                branch_id,
                location_id,
                location_name,
                org_id,
                purchase_group_id,
                with_sample,
                indent_qty,
                indent_status,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                urgent,
                imports,
                cep_type,
                emergency,
                hod_app_by,
                hod_approval_date,
                approved_by,
                approved_date,
                remarks
            )
            VALUES (
                l_indent_id,
                l_indent_no,
                m.company_id,
                m.branch_id,
                m.location_id,
                l_location_name,
                m.dept_id,
                m.purchase_group_id,
                'N',
                m.qty,
                'CLOSED',
                in_user_id,
                SYSDATE,
                in_user_id,
                SYSDATE,
                'N',
                'Y',
                'R',
                'N',
                109,
                SYSDATE,
                109,
                SYSDATE,
                'INDENT CREATED FOR PI'
            );
            COMMIT;
            
            IF loop_counter = 0 THEN
                SELECT inv_cs_s.NEXTVAL
                INTO l_cs_id
                FROM dual;
                
                SELECT NVL(MAX(cs_no),0)+1
                INTO l_cs_no
                FROM inv_cs
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                INSERT INTO inv_cs (
                    cs_id, 
                    company_id , 
                    branch_id , 
                    buyer_id, 
                    remarks, 
                    created_by,
                    creation_date,
                    last_updated_by, 
                    last_update_date, 
                    cs_status, 
                    cs_validity_date,
                    type,
                    cs_no
                )
                VALUES (
                    l_cs_id,
                    m.company_id,
                    m.branch_id,
                    NULL,
                    'CS CREATED FOR PI',
                    in_user_id,
                    SYSDATE,
                    in_user_id,
                    SYSDATE,
                    'CLOSED',
                    NULL,
                    'IMPORTS',
                    l_cs_no
                );
                COMMIT;
            END IF;
            loop_counter := loop_counter + 1;
            l_cs_item_id := inv_cs_items_s.nextval ; 
            INSERT INTO inv_cs_items (
                cs_item_id,
                cs_id,
                indent_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                location_id,
                location_name,
                purchase_group_id,
                indent_no
            )
            VALUES (
                l_cs_item_id,
                l_cs_id,
                l_indent_id,
                'CS ITEM FOR PI',
                in_user_id,
                SYSDATE,
                in_user_id,
                SYSDATE,
                m.location_id,
                l_location_name,
                m.purchase_group_id,
                l_indent_no
            );
            COMMIT;
            
            l_cs_item_vendor_id := inv_cs_items_venders_s.NEXTVAL;
            
            INSERT INTO inv_cs_items_venders (
                cs_items_vender_id,
                cs_item_id,
                indent_id,
                vender_id,
                rate,
                approved_qty,
                approved,
                payment_terms,
                po_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                delivery_terms,
                performa_invoice,
                currency,
                exch_rate,
                freight,
                other_cost,
                tooling_cost,
                packing_cost
            )
            VALUES (
                l_cs_item_vendor_id,
                l_cs_item_id,
                l_indent_id,
                m.vendor_id,
                m.rate,
                m.qty,
                'Y',
                'CRED30', -- NEED TO CHECK,
                NULL,
                'RECORD CREATED FROM PI',
                in_user_id,
                SYSDATE,
                in_user_id,
                SYSDATE,
                'VENDOR SITE',
                'Y',
                m.currency,
                m.exch_rate,
                m.freight,
                m.other_cost,
                m.tooling_cost,
                m.packing_cost
            );
            COMMIT;
        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN 
        NULL;
    END;
    
    /*
    -- This function is for checking that the item is wip item or not
    */
    
    FUNCTION check_wip_item (
        in_item_id IN NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT wip_item
        FROM inv_items
        WHERE item_id = in_item_id;
        l_wip_item VARCHAR2(20);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_wip_item;
        CLOSE c1;
        RETURN l_wip_item;
    EXCEPTION
        WHEN OTHERS THEN 
        RETURN 'N';
    END;
    
    
    PROCEDURE sync_stock_balance
    IS
        CURSOR c1
        IS
        SELECT DISTINCT item_id,
                        location_id,
                        company_id,
                        branch_id
        FROM (
              SELECT item_id,
                     location_id,
                     company_id,
                     branch_id,
                     cur_stock
              FROM inv_stock_balance b
              WHERE cur_stock <> 0
              MINUS
              SELECT item_id,
                     location_id,
                     company_id,
                     branch_id,
                     SUM (qty)
              FROM inv_stock_ledger
              GROUP BY item_id,
                       location_id,
                       company_id,
                       branch_id
         );
    BEGIN
       /*  
        UPDATE inv_stock_balance b
        SET (b.cur_stock , b.cur_avg_rate , b.cur_amount) = (SELECT NVL(SUM(qty),0) qty,
                                                                    SUM(NVL(AMOUNT,0)) / NULLIF(NVL(SUM(qty),0),0)  rate,
                                                                    NVL(SUM(amount),0) amount
                                                             FROM inv_stock_ledger m
                                                             WHERE b.company_id = m.company_id
                                                             AND b.branch_id = m.branch_id
                                                             AND b.location_id = m.location_id
                                                             AND b.item_id = m.item_id)
        WHERE 1 = 1 ;

        COMMIT;
        */
               
        MERGE INTO inv_stock_balance b
        USING inv_stock_ledger_sum s
        ON (
                b.item_id = s.item_id
            AND b.company_id = s.company_id
            AND b.branch_id = s.branch_id
            AND b.location_id = NVL(s.location_id,0)
        )
        WHEN MATCHED THEN
        UPDATE SET b.cur_stock = s.qty,
                   b.cur_avg_rate = s.rate,
                   b.cur_amount = s.amount
        WHERE b.item_id = s.item_id
        AND b.company_id = s.company_id
        AND b.branch_id = s.branch_id
        AND b.location_id = s.location_id
        WHEN NOT MATCHED THEN
        INSERT  (
            company_id, 
            branch_id, 
            location_id,
            item_id,
            cur_stock,
            cur_avg_rate,
            cur_amount,
            creation_date
        )
        VALUES (
            s.company_id, 
            s.branch_id,
            NVL(s.location_id,0),
            s.item_id,
            s.qty,
            s.rate,
            s.amount,
            SYSDATE
        );
            
        FOR m IN c1 LOOP
            UPDATE inv_stock_balance
            SET cur_stock = 0,
                cur_amount = 0
            WHERE item_id = m.item_id
            AND location_id = m.location_id
            AND company_id = m.company_id
            AND branch_id = m.branch_id;
        END LOOP;
            
        COMMIT;
        
        
    EXCEPTION 
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    PROCEDURE sync_stock_balance_msg (
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT DISTINCT item_id,
                        location_id,
                        company_id,
                        branch_id
        FROM (
              SELECT item_id,
                     location_id,
                     company_id,
                     branch_id,
                     cur_stock
              FROM inv_stock_balance b
              WHERE cur_stock <> 0
              MINUS
              SELECT item_id,
                     location_id,
                     company_id,
                     branch_id,
                     SUM (qty)
              FROM inv_stock_ledger
              GROUP BY item_id,
                       location_id,
                       company_id,
                       branch_id
         );
    BEGIN
        MERGE INTO inv_stock_balance b
        USING inv_stock_ledger_sum s
        ON (
                b.item_id = s.item_id
            AND b.company_id = s.company_id
            AND b.branch_id = s.branch_id
            AND b.location_id = NVL(s.location_id,0)
        )
        WHEN MATCHED THEN
        UPDATE SET b.cur_stock = s.qty,
                   b.cur_avg_rate = s.rate,
                   b.cur_amount = s.amount
        WHERE b.item_id = s.item_id
        AND b.company_id = s.company_id
        AND b.branch_id = s.branch_id
        AND b.location_id = s.location_id
        WHEN NOT MATCHED THEN
        INSERT  (
            company_id, 
            branch_id, 
            location_id,
            item_id,
            cur_stock,
            cur_avg_rate,
            cur_amount,
            creation_date
        )
        VALUES (
            s.company_id, 
            s.branch_id,
            NVL(s.location_id,0),
            s.item_id,
            s.qty,
            s.rate,
            s.amount,
            SYSDATE
        );
            
        FOR m IN c1 LOOP
            UPDATE inv_stock_balance
            SET cur_stock = 0,
                cur_amount = 0
            WHERE item_id = m.item_id
            AND location_id = m.location_id
            AND company_id = m.company_id
            AND branch_id = m.branch_id;
        END LOOP;

        COMMIT;
    EXCEPTION 
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
  
    /*
    -- This procedure is for updating sale order status to 'CLOSED' when all items are delivered
    */
    
    PROCEDURE close_sale_order (
        in_challan_id IN NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT sales_order_id,
               SUM(NVL(qty,0)) so_qty , 
               SUM(NVL(delivered_qty,0)) del_qty
        FROM inv_sales_order_items
        WHERE sales_order_id IN ( SELECT DISTINCT sale_order_id
                                  FROM inv_delivery_challan_items
                                  WHERE challan_id = in_challan_id )
        GROUP BY sales_order_id;
    BEGIN
        FOR m IN c1 LOOP
            IF m.so_qty = m.del_qty THEN
                UPDATE inv_sales_orders s
                SET s.order_status = 'CLOSED'
                WHERE s.sales_order_id = m.sales_order_id;
                
                COMMIT;
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
   
    
    FUNCTION get_rm_store_type_id RETURN NUMBER
    IS
    BEGIN
        RETURN 2;
    END;
    
    FUNCTION get_wip_store_type_id RETURN NUMBER
    IS
    BEGIN
        RETURN 3;
    END;
    
    FUNCTION get_damage_store_type_id RETURN NUMBER
    IS
    BEGIN
        RETURN 6;
    END;
    
    FUNCTION get_scrap_store_type_id RETURN NUMBER
    IS
    BEGIN
        RETURN 7;
    END;
    
    FUNCTION get_repair_store_type_id RETURN NUMBER
    IS
    BEGIN
        RETURN 8;
    END;
    
    FUNCTION get_repair_store_id RETURN NUMBER
    IS
    BEGIN
        RETURN 25;
    END;
    
    FUNCTION get_damage_store_id RETURN NUMBER
    IS
    BEGIN
        RETURN 23;
    END;
    
    FUNCTION get_location_group_id RETURN VARCHAR2
    IS
    BEGIN
        RETURN ',2,';
    END;
    
    FUNCTION get_transfer_item_id (
        in_item_id  IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT transfer_item_id
        FROM inv_items
        WHERE item_id = in_item_id;
        
        l_transfer_item_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_transfer_item_id;
        CLOSE c1;
        
        RETURN l_transfer_item_id;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
        -- This function is for calculating average rate where rate is null
    */
    
    FUNCTION rate_calculation (
        in_company_id IN NUMBER,
        in_branch_id  IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER
    IS
    BEGIN
        NULL;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
        -- This Procedure is for updating challan reference table using FIFO method
    */
    
    
    PROCEDURE upd_challan_ref (
        in_loan_rec_id IN NUMBER,
        in_rigp_id IN NUMBER,
        in_vendor_id IN NUMBER,
        in_calling_time IN VARCHAR2,
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT item_id, 
               inv_supp.get_transfer_item_id(item_id) trn_item_id,
               received_qty qty
        FROM inv_loan_receive_items
        WHERE loan_rec_id = in_loan_rec_id;
        
        CURSOR c2
        IS
        SELECT cr.reference_id,
               cr.challan_item_id,
               cr.challan_id,
               cr.item_id,
               cr.qty,
               cr.recived_qty,
               cr.qty - NVL(cr.recived_qty,0) - NVL(cr.adjusted_qty,0) balance,
               cr.adjusted_qty,
               cr.sale_order_id,
               cr.sale_order_item_id
        FROM inv_delivery_challan_reference cr
        WHERE  cr.vendor_no = in_vendor_id
        AND cr.item_id IN (SELECT transfer_item_id 
                           FROM inv_items 
                           WHERE item_id IN (SELECT item_id 
                                             FROM inv_loan_receive_items 
                                             WHERE loan_rec_id = in_loan_rec_id))
        AND cr.qty - NVL(cr.recived_qty,0) > 0
        AND cr.status = 'APPROVED'
        ORDER BY cr.reference_id, cr.item_id;
        
        CURSOR c3
        IS
        SELECT cr.item_id,
               SUM(cr.qty - NVL(cr.recived_qty,0) - NVL(cr.adjusted_qty,0)) balance
        FROM inv_delivery_challan_reference cr
        WHERE  cr.vendor_no = in_vendor_id
        AND cr.item_id IN (SELECT transfer_item_id 
                           FROM inv_items 
                           WHERE item_id IN (SELECT item_id 
                                             FROM inv_loan_receive_items 
                                             WHERE loan_rec_id = in_loan_rec_id))
        AND cr.qty - NVL(cr.recived_qty,0) > 0
        AND cr.status = 'APPROVED'
        GROUP BY cr.item_id;
     
        
        l_temp_qty NUMBER := 0;
        l_check NUMBER := 0 ;
    BEGIN
        FOR i IN c1 LOOP
            FOR j IN c3 LOOP
                IF i.trn_item_id = j.item_id THEN
                    IF i.qty > j.balance THEN
                        l_check := 1;
                    END IF;
                END IF;
            END LOOP;
        END LOOP;
        
        IF l_check = 1 THEN
            out_error_text := 'Insufficient stock balance !!';
            dbms_output.put_line(out_error_text);
            RETURN;
        END IF;
    
        FOR m IN c1 LOOP
            l_temp_qty := m.qty; 
            FOR n IN c2 LOOP
                IF m.trn_item_id = n.item_id THEN
                    dbms_output.put_line(m.trn_item_id);
                    dbms_output.put_line(n.item_id);
                    IF  n.balance > l_temp_qty THEN   
                        UPDATE inv_delivery_challan_reference
                        SET adjusted_qty = NVL(adjusted_qty,0) + l_temp_qty
                        WHERE reference_id = n.reference_id;
                        
                        IF l_temp_qty <> 0 THEN
                        
                            IF in_calling_time = 'HOD_APP' THEN
                                INSERT INTO inv_delivery_challan_ref_dtl (
                                    reference_id, challan_item_id, 
                                    challan_id, item_id, 
                                    qty, recived_qty, 
                                    balance, pkg_rcv_qty, 
                                    adjusted_qty, sale_order_id, sale_order_item_id
                                )
                                VALUES (
                                    n.reference_id, n.challan_item_id, 
                                    n.challan_id, n.item_id, 
                                    n.qty, n.recived_qty, 
                                    n.balance, null,
                                    NVL(n.adjusted_qty,0) + l_temp_qty, n.sale_order_id, n.sale_order_item_id
                                );
                            END IF;
                        
                        END IF;
                        
                        l_temp_qty := 0;
                        dbms_output.put_line( ' 1:  ITEM ID - '|| n.item_id ||' loan rcv qty - '|| m.qty || ' balance qty - '|| n.balance || ' temp qty -  '|| l_temp_qty);
                        
                    ELSE
                    
                        UPDATE inv_delivery_challan_reference
                        SET adjusted_qty = NVL(adjusted_qty,0) + n.balance
                        WHERE reference_id = n.reference_id;
                        
                        IF in_calling_time = 'HOD_APP' THEN
                            INSERT INTO inv_delivery_challan_ref_dtl (
                                reference_id, challan_item_id, 
                                challan_id, item_id, 
                                qty, recived_qty, 
                                balance, pkg_rcv_qty, 
                                adjusted_qty, sale_order_id, sale_order_item_id
                            )
                            VALUES (
                                n.reference_id, n.challan_item_id, 
                                n.challan_id, n.item_id, 
                                n.qty, n.recived_qty, 
                                n.balance, null,
                                NVL(n.adjusted_qty,0) + n.balance, n.sale_order_id, n.sale_order_item_id
                            );
                        END IF;
                        
                        l_temp_qty := l_temp_qty - n.balance;
                        dbms_output.put_line( ' 2: ITEM ID - '|| n.item_id ||' loan rcv qty - '|| m.qty || ' balance qty - '|| n.balance || ' temp qty -  '|| l_temp_qty);
                        
                    END IF;
                END IF;
            END LOOP;
            
        END LOOP;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            out_error_code := SQLCODE;
            out_error_text := SQLERRM;
    END;
    
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
    
    PROCEDURE upd_customer_request (
        in_loan_rec_id  IN  NUMBER,
        out_error_code  OUT VARCHAR2,
        out_error_text  OUT VARCHAR2  
    )
    IS
        CURSOR c1
        IS
        SELECT ri.received_buffer_qty,
               r.vendor_id,
               ri.item_id
        FROM inv_loan_receive_items ri,
             inv_loans_receive r
        WHERE ri.loan_rec_id = in_loan_rec_id
        AND r.loan_rec_id = ri.loan_rec_id ;
        
        l_diff NUMBER;
        l_request_id NUMBER;
        
    BEGIN
        FOR m IN c1 LOOP
            IF NVL(m.received_buffer_qty,0) > 0 THEN
                UPDATE inv_customer_request_d
                SET received_qty = NVL(received_qty,0)+ m.received_buffer_qty
                WHERE item_id = m.item_id
                AND request_id IN (SELECT request_id
                                  FROM inv_customer_request_m
                                  WHERE vendor_id = m.vendor_id
                                  AND request_status = 'APPROVED'
                                  AND request_type = 'BUFFER' );
                                  
                COMMIT;
                
                
                SELECT requested_qty - received_qty, 
                       request_id
                INTO l_diff, 
                     l_request_id
                FROM inv_customer_request_d
                WHERE request_id IN (SELECT request_id
                                    FROM inv_customer_request_m
                                    WHERE vendor_id = m.vendor_id
                                    AND request_status = 'APPROVED'
                                    AND request_type = 'BUFFER')
                AND item_id = m.item_id;
                
                IF l_diff = 0 THEN
                    UPDATE inv_customer_request_m
                    SET request_status = 'CLOSED'
                    WHERE request_status = 'APPROVED'
                    AND request_type = 'BUFFER'
                    AND vendor_id = m.vendor_id
                    AND request_id = l_request_id;
                END IF;
            END IF;  
                   
        END LOOP;
        
        COMMIT;

    EXCEPTION 
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
        
    PROCEDURE handle_faulty_quantity (
        in_loan_rec_id  IN  NUMBER,
        out_error_code  OUT VARCHAR2,
        out_error_text  OUT VARCHAR2  
    )
    IS
        CURSOR c1
        IS
        SELECT ri.our_fault_qty,
               ri.customer_fault_qty,
               ri.leakage_qty,
               r.vendor_id,
               ri.item_id,
               r.creation_date,
               r.location_id,
               r.company_id,
               r.branch_id,
               r.created_by,
               r.loan_rec_no
        FROM inv_loan_receive_items ri,
             inv_loans_receive r
        WHERE ri.loan_rec_id = in_loan_rec_id
        AND r.loan_rec_id = ri.loan_rec_id ;
        
        l_cnt NUMBER;     
        
        l_scrap_transfer_id NUMBER;
        l_scrap_transfer_no NUMBER;
        l_to_scrap_location NUMBER;
        
        l_customer_req_mst_id NUMBER;
        l_customer_req_no NUMBER;
        l_customer_req_dtl_id NUMBER;
        
        l_customer_id NUMBER;
        
        l_our_cust_id NUMBER := 501;
        l_our_vendor_id NUMBER := 822;
        
        l_opening_qty NUMBER := 0;
        l_issued_qty NUMBER := 0;
        
    BEGIN
        FOR m IN c1 LOOP
            
            IF  NVL(m.our_fault_qty,0) > 0 THEN
                
                SELECT NVL(MAX(transfer_id),0)+1
                INTO l_scrap_transfer_id
                FROM inv_stock_transfer_scrap;

                SELECT NVL(MAX(transfer_no),0)+1
                INTO l_scrap_transfer_no
                FROM inv_stock_transfer_scrap
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                SELECT location_id
                INTO l_to_scrap_location
                FROM inv_locations
                WHERE location_type_id = inv_supp.get_damage_store_type_id;
            
                INSERT INTO inv_stock_transfer_scrap (
                    transfer_id, 
                    transfer_no, 
                    transfer_date, 
                    from_location_id, 
                    to_location_id, 
                    item_id, 
                    qty, 
                    rate, 
                    amount, 
                    remarks, 
                    trn_app_by, 
                    trn_app_date, 
                    transfer_status, 
                    vendor_id, 
                    transfer_type, 
                    company_id, 
                    branch_id, 
                    created_by, 
                    created_date, 
                    last_updated_by, 
                    last_updated_date, 
                    stock_during_transaction, 
                    is_repair_done, 
                    ref_transfer_no, 
                    ref_transfer_id, 
                    transfer_item_id, 
                    transfer_item_rate, 
                    faulty_type,
                    entry_type
                )
                VALUES (
                    l_scrap_transfer_id, 
                    l_scrap_transfer_no, 
                    m.creation_date, 
                    m.location_id,  
                    l_to_scrap_location,  
                    m.item_id,  
                    m.our_fault_qty, 
                    0, 
                    0,  
                    'DAMAGE TRANSFER DUE TO OUR FAULT - '|| m.loan_rec_no,  
                    m.created_by, 
                    SYSDATE, 
                    'PREPARED', 
                    m.vendor_id, 
                    'DAMAGE',  
                    m.company_id,
                    m.branch_id,
                    m.created_by, 
                    SYSDATE,  
                    NULL, 
                    NULL, 
                    NULL,  
                    NULL,
                    NULL, 
                    NULL,  
                    NULL,
                    NULL, 
                    'O',
                    'A'
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => m.location_id,
                    in_item_id      => m.item_id,
                    in_qty          => -1 * nvl(m.our_fault_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => l_to_scrap_location,
                    in_item_id      => m.item_id,
                    in_qty          => nvl(m.our_fault_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );

            END IF;
            
            IF  NVL(m.customer_fault_qty,0) > 0 THEN
                
                SELECT NVL(MAX(transfer_id),0)+1
                INTO l_scrap_transfer_id
                FROM inv_stock_transfer_scrap;

                SELECT NVL(MAX(transfer_no),0)+1
                INTO l_scrap_transfer_no
                FROM inv_stock_transfer_scrap
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                SELECT location_id
                INTO l_to_scrap_location
                FROM inv_locations
                WHERE location_type_id = inv_supp.get_damage_store_type_id;
            
                INSERT INTO inv_stock_transfer_scrap (
                    transfer_id, 
                    transfer_no, 
                    transfer_date, 
                    from_location_id, 
                    to_location_id, 
                    item_id, 
                    qty, 
                    rate, 
                    amount, 
                    remarks, 
                    trn_app_by, 
                    trn_app_date, 
                    transfer_status, 
                    vendor_id, 
                    transfer_type, 
                    company_id, 
                    branch_id, 
                    created_by, 
                    created_date, 
                    last_updated_by, 
                    last_updated_date, 
                    stock_during_transaction, 
                    is_repair_done, 
                    ref_transfer_no, 
                    ref_transfer_id, 
                    transfer_item_id, 
                    transfer_item_rate, 
                    faulty_type,
                    entry_type
                )
                VALUES (
                    l_scrap_transfer_id, 
                    l_scrap_transfer_no, 
                    m.creation_date, 
                    m.location_id,  
                    l_to_scrap_location,  
                    m.item_id,  
                    m.customer_fault_qty, 
                    0, 
                    0,  
                    'DAMAGE TRANSFER DUE TO CUSTOMER FAULT - '|| m.loan_rec_no,  
                    m.created_by, 
                    SYSDATE,  
                    'PREPARED', 
                    m.vendor_id, 
                    'DAMAGE',  
                    m.company_id,
                    m.branch_id,
                    m.created_by, 
                    SYSDATE,  
                    NULL, 
                    NULL, 
                    NULL,  
                    NULL,
                    NULL, 
                    NULL,  
                    NULL,
                    NULL,  
                    'C',
                    'A'
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => m.location_id,
                    in_item_id      => m.item_id,
                    in_qty          => -1 * nvl(m.customer_fault_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => l_to_scrap_location,
                    in_item_id      => m.item_id,
                    in_qty          => nvl(m.customer_fault_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );
            END IF;
            
            
            IF  NVL(m.leakage_qty,0) > 0 THEN
                
                SELECT NVL(MAX(transfer_id),0)+1
                INTO l_scrap_transfer_id
                FROM inv_stock_transfer_scrap;

                SELECT NVL(MAX(transfer_no),0)+1
                INTO l_scrap_transfer_no
                FROM inv_stock_transfer_scrap
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                SELECT location_id
                INTO l_to_scrap_location
                FROM inv_locations
                WHERE location_type_id = inv_supp.get_damage_store_type_id;
            
                INSERT INTO inv_stock_transfer_scrap (
                    transfer_id, 
                    transfer_no, 
                    transfer_date, 
                    from_location_id, 
                    to_location_id, 
                    item_id, 
                    qty, 
                    rate, 
                    amount, 
                    remarks, 
                    trn_app_by, 
                    trn_app_date, 
                    transfer_status, 
                    vendor_id, 
                    transfer_type, 
                    company_id, 
                    branch_id, 
                    created_by, 
                    created_date, 
                    last_updated_by, 
                    last_updated_date, 
                    stock_during_transaction, 
                    is_repair_done, 
                    ref_transfer_no, 
                    ref_transfer_id, 
                    transfer_item_id, 
                    transfer_item_rate, 
                    faulty_type,
                    entry_type
                )
                VALUES (
                    l_scrap_transfer_id, 
                    l_scrap_transfer_no, 
                    m.creation_date, 
                    m.location_id,  
                    l_to_scrap_location,  
                    m.item_id,  
                    m.leakage_qty, 
                    0, 
                    0,  
                    'DAMAGE TRANSFER DUE TO LEAKAGE FAULT - '|| m.loan_rec_no,  
                    m.created_by, 
                    SYSDATE,  
                    'PREPARED', 
                    m.vendor_id, 
                    'DAMAGE',  
                    m.company_id,
                    m.branch_id,
                    m.created_by, 
                    SYSDATE,  
                    NULL, 
                    NULL, 
                    NULL,  
                    NULL,
                    NULL, 
                    NULL,  
                    NULL,
                    NULL,  
                    'L',
                    'A'
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => m.location_id,
                    in_item_id      => m.item_id,
                    in_qty          => -1 * nvl(m.leakage_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );
                
                inv_supp.upd_stock_balance (
                    in_company_id   => m.company_id,
                    in_branch_id    => m.branch_id,
                    in_location_id  => l_to_scrap_location,
                    in_item_id      => m.item_id,
                    in_qty          => nvl(m.leakage_qty,0),
                    in_amount       => 0,
                    in_user_id      => m.created_by
                );
            END IF;
            
        END LOOP;
      
        COMMIT;
        
    EXCEPTION 
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;    
    
    PROCEDURE close_replacement_request (
        in_request_id   IN  NUMBER,
        out_error_code  OUT NUMBER,
        out_error_text  OUT NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT m.to_cust_id,
               d.item_id,
               m.created_by
        FROM inv_customer_request_m m,
             inv_customer_request_d d
        WHERE m.request_id = d.request_id
        AND m.request_id = in_request_id;
        
        l_customer_id NUMBER;
        l_item_id NUMBER;
        l_cnt NUMBER;
        l_opening_qty NUMBER := 0;
        l_issued_qty NUMBER := 0;
        l_user_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_customer_id , l_item_id , l_user_id; 
        CLOSE c1;
        
        SELECT COUNT(*)
        INTO l_cnt 
        FROM inv_customer_request_m m,
             inv_customer_request_d d
        WHERE m.request_id = d.request_id
        AND m.to_cust_id = l_customer_id
        AND m.request_status ='APPROVED'
        AND m.request_type = 'REPLACEMENT'
        AND d.item_id = l_item_id;
        
        IF l_cnt > 0 THEN
            SELECT NVL(rd.opening_qty,0) + NVL(rd.requested_qty,0) op_qty , NVL(rd.issued_qty,0) issued_qty
            INTO l_opening_qty, l_issued_qty
            FROM inv_customer_request_m rm,
                 inv_customer_request_d rd
            WHERE rm.request_id = rd.request_id
            AND rm.request_status ='APPROVED'
            AND rm.request_type = 'REPLACEMENT'
            AND rm.to_cust_id = l_customer_id
            AND rd.item_id = l_item_id;
            
            UPDATE inv_customer_request_d
            SET opening_qty = l_opening_qty,
                issued_qty = l_issued_qty
            WHERE request_id = in_request_id;

            
            UPDATE inv_customer_request_m
            SET request_status = 'CLOSED',
                closed_by = l_user_id,
                closed_date = SYSDATE
            WHERE request_status ='APPROVED'
            AND to_cust_id = l_customer_id
            AND request_type = 'REPLACEMENT'
            AND request_id = (SELECT m.request_id
                              FROM inv_customer_request_m m,
                                   inv_customer_request_d d
                              WHERE m.request_id = d.request_id
                              AND m.to_cust_id = l_customer_id
                              AND m.request_status ='APPROVED'
                              AND m.request_type = 'REPLACEMENT'
                              AND d.item_id = l_item_id );

            COMMIT;
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;  
    
    FUNCTION get_customer_stock_balance (
        in_customer_id    IN  NUMBER,
        in_item_id        IN  NUMBER,
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_transfer_type  IN  VARCHAR2
    ) RETURN NUMBER
    IS
        l_in_refill_rcv_qty NUMBER;
        l_out_dc_qty NUMBER;
        l_in_auto_replace_qty NUMBER;
        l_stock_qty NUMBER;
        
        l_damage_qty NUMBER;
        l_damage_to_scrap_qty NUMBER;
        l_damage_to_repair_qty NUMBER;
        
        l_repair_done NUMBER;
        l_repair_failed NUMBER;
    BEGIN
    
        IF in_transfer_type = 'DAMAGE' THEN    
    
            BEGIN
                SELECT NVL(SUM(d.received_qty),0) 
                INTO l_in_refill_rcv_qty 
                FROM inv_loans_receive m,
                     inv_loan_receive_items d
                WHERE m.loan_rec_id = d.loan_rec_id
                AND m.vendor_id = (SELECT vendor_code 
                                   FROM ar_customers 
                                   WHERE customer_id = in_customer_id)
                AND d.item_id = in_item_id
                AND m.company_id = in_company_id
                AND m.branch_id = in_branch_id
                AND m.location_id = (SELECT location_id 
                                     FROM inv_locations 
                                     WHERE location_type_id=2 
                                     AND location_group_id = (SELECT location_group_id 
                                                              FROM inv_locations 
                                                              WHERE location_id = in_location_id));
            EXCEPTION
                WHEN OTHERS THEN
                l_in_refill_rcv_qty := 0;
            END;
                
            BEGIN                                          
                SELECT NVL(requested_qty,0)
                INTO l_in_auto_replace_qty
                FROM inv_customer_request_m m,
                     inv_customer_request_d d
                WHERE m.request_id = d.request_id 
                AND m.to_cust_id = in_customer_id
                AND m.entry_type = 'A'
                AND m.request_type = 'REPLACEMENT'
                AND m.request_status = 'APPROVED'
                AND M.COMPANY_ID = in_company_id
                AND M.BRANCH_ID = in_branch_id
                AND m.location_id = in_location_id
                AND d.item_id = in_item_id;  
            EXCEPTION
                WHEN OTHERS THEN
                l_in_auto_replace_qty := 0;
            END;                                               
                                                          
            BEGIN                                         
                SELECT NVL(SUM(d.qty),0) 
                INTO l_out_dc_qty
                FROM inv_delivery_challans m,
                     inv_delivery_challan_items d
                WHERE m.challan_id = d.challan_id
                AND NVL(m.delivery_status,'STATUS') <> 'CANCELED'
                AND m.customer_id = in_customer_id
                AND m.company_id = in_company_id
                AND m.branch_id = in_branch_id
                AND m.location_id = (SELECT location_id FROM inv_locations WHERE rm_loc_id = in_location_id)
                AND d.item_id = (SELECT fg_item_id FROM inv_items WHERE item_id=in_item_id);
            EXCEPTION
                WHEN OTHERS THEN
                l_out_dc_qty := 0;
            END;
            
            l_stock_qty := NVL(l_in_refill_rcv_qty,0) + NVL(l_in_auto_replace_qty,0) - NVL(l_out_dc_qty,0);
            
        ELSIF in_transfer_type IN ('SCRAP','REPAIR') THEN           --  DAMAGE TO SCRAP/REPAIR
            
            BEGIN
                SELECT SUM(NVL(qty,0)) 
                INTO l_damage_qty
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND to_location_id = inv_supp.get_damage_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'DAMAGE'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_damage_qty := 0;
            END;
            
            BEGIN
                SELECT SUM(NVL(qty,0)) 
                INTO l_damage_to_scrap_qty
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND from_location_id = inv_supp.get_damage_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'SCRAP'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_damage_to_scrap_qty := 0;
            END;
            
            BEGIN
                SELECT SUM(NVL(qty,0)) 
                INTO l_damage_to_repair_qty
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND from_location_id = inv_supp.get_damage_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'REPAIR'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_damage_to_repair_qty := 0;
            END;
            
            l_stock_qty := NVL(l_damage_qty,0) - NVL(l_damage_to_scrap_qty,0) - NVL(l_damage_to_repair_qty,0);
            
        ELSIF in_transfer_type IN ('REPAIR-DONE', 'REPAIR-FAILED') THEN           --  REPAIR DONE (REPAIR TO RM)  /  REPAIR FAILED (REPAIR TO SCRAP)
        
            BEGIN
                SELECT SUM(NVL(qty,0)) 
                INTO l_damage_to_repair_qty
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND to_location_id = inv_supp.get_repair_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'REPAIR'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_damage_to_repair_qty := 0;
            END;
            
            BEGIN
                SELECT SUM(NVL(qty,0))                                    
                INTO l_repair_done
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND from_location_id = inv_supp.get_repair_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'REPAIR-DONE'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_repair_done := 0;
            END;
            
            BEGIN
                SELECT SUM(NVL(qty,0))                                    
                INTO l_repair_failed
                FROM inv_stock_transfer_scrap
                WHERE company_id = in_company_id
                AND branch_id = in_branch_id
                AND from_location_id = inv_supp.get_repair_store_id
                AND vendor_id = (SELECT vendor_code 
                                 FROM ar_customers 
                                 WHERE customer_id = in_customer_id)
                AND transfer_type = 'REPAIR-FAILED'
                AND transfer_status = 'APPROVED'
                AND item_id = in_item_id;
            EXCEPTION
                WHEN OTHERS THEN
                l_repair_failed := 0;
            END;
            
            l_stock_qty := NVL(l_damage_to_repair_qty,0) - NVL(l_repair_done,0) - NVL(l_repair_failed,0);
            
        END IF;
                                                      
        RETURN l_stock_qty;
        
    EXCEPTION
        WHEN OTHERS THEN 
        RETURN 0;
    END;
    
    
    FUNCTION get_customer_scrap_stock (
        in_customer_id    IN  NUMBER,
        in_item_id        IN  NUMBER,
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(qty)                                    
        FROM inv_stock_transfer_scrap
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND to_location_id = 24
        AND vendor_id = (SELECT vendor_code 
                         FROM ar_customers 
                         WHERE customer_id = in_customer_id)
        AND item_id = in_item_id
        AND transfer_type IN ('SCRAP','REPAIR-FAILED')
        AND transfer_status <> 'CANCELED';
        
        CURSOR c2
        IS
        SELECT requested_qty
        FROM inv_customer_request_m m,
             inv_customer_request_d d
        WHERE m.request_id = d.request_id 
        AND m.to_cust_id = in_customer_id
        AND m.request_type = 'REPLACEMENT'
        AND m.sub_request_type = 'BUFFER'
        AND m.request_status = 'APPROVED'
        AND m.company_id = in_company_id
        AND m.branch_id = in_branch_id
        AND m.location_id = in_location_id
        AND d.item_id = in_item_id;
        
        CURSOR c3
        IS
        SELECT SUM(NVL(qty,0)) ttl_cust_fault
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'DAMAGE'
        AND s.faulty_type = 'C'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.from_location_id = in_location_id
        AND s.item_id = in_item_id
        AND s.vendor_id = (SELECT vendor_code 
                           FROM ar_customers 
                           WHERE customer_id = in_customer_id);
        
        l_customer_scrap_qty NUMBER := 0;
        
        l_scrap_replace_qty NUMBER := 0;
        
        l_customer_fault NUMBER := 0;
        
        l_diff NUMBER := 0;
        
        l_result NUMBER := 0;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_customer_scrap_qty;
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_scrap_replace_qty;
        CLOSE c2;
        
        OPEN c3;
            FETCH c3 INTO l_customer_fault;
        CLOSE c3;
        
        IF l_customer_scrap_qty > l_customer_fault THEN
            l_diff := NVL(l_customer_scrap_qty,0) - NVL(l_customer_fault,0) ;
        ELSE
            l_diff := 0;
        END IF;
            
        l_result := NVL(l_customer_scrap_qty,0) + NVL(l_diff,0) - NVL(l_scrap_replace_qty,0);
        
        RETURN l_result;
        
    EXCEPTION
        WHEN OTHERS THEN 
        RETURN 0;
    END;
    
    
    PROCEDURE ins_customer_request_hist (
        in_request_mst_id IN  NUMBER,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2
    )
    IS
    BEGIN
        INSERT INTO inv_customer_request_m_hist (
            request_id, 
            to_cust_id, 
            remarks, 
            created_by, 
            creation_date, 
            last_update_by, 
            last_update_date, 
            approved_by, 
            approved_date, 
            request_status, 
            canceled_by, 
            canceled_date, 
            company_id, 
            branch_id, 
            location_id, 
            request_no, 
            from_cust_id, 
            closed_by, 
            closed_date, 
            request_date, 
            from_vendor_id, 
            vendor_id, 
            request_type, 
            entry_type, 
            sub_request_type
        )
        SELECT request_id, 
                to_cust_id, 
                remarks, 
                created_by, 
                creation_date, 
                last_update_by, 
                last_update_date, 
                approved_by, 
                approved_date, 
                request_status, 
                canceled_by, 
                canceled_date, 
                company_id, 
                branch_id, 
                location_id, 
                request_no, 
                from_cust_id, 
                closed_by, 
                closed_date, 
                request_date, 
                from_vendor_id, 
                vendor_id, 
                request_type, 
                entry_type, 
                sub_request_type
        FROM inv_customer_request_m
        WHERE request_id = in_request_mst_id;
        
        INSERT INTO inv_customer_request_d_hist (
            request_id, 
            item_id, 
            opening_qty, 
            requested_qty, 
            received_qty, 
            created_by, 
            creation_date, 
            last_updated_by, 
            last_updated_date, 
            request_item_id, 
            issued_qty, 
            item_status, 
            closed_by, 
            closed_date, 
            old_request_id, 
            new_request_id
        )
        SELECT request_id, 
            item_id, 
            opening_qty, 
            requested_qty, 
            received_qty, 
            created_by, 
            creation_date, 
            last_updated_by, 
            last_updated_date, 
            request_item_id, 
            issued_qty, 
            item_status, 
            closed_by, 
            closed_date, 
            old_request_id, 
            new_request_id
        FROM inv_customer_request_d
        WHERE request_id = in_request_mst_id;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    FUNCTION get_ttl_buffer_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER
    IS 
        CURSOR c1
        IS
        SELECT SUM (NVL(qty,0)) pkg_to_refill
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'PACKAGE-REFILL'
        AND s.transfer_item_id = in_item_id
        AND s.company_id = in_company_id
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id;
        
        CURSOR c2
        IS
        SELECT SUM (NVL(qty,0)) refill_to_pkg
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REFILL-PACKAGE'
        AND s.item_id = in_item_id
        AND s.company_id = in_company_id
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id ;
        
        CURSOR c3 
        IS
        SELECT (NVL (SUM (requested_qty),0)) - (NVL (SUM (received_qty),0)) ttl_issued_buffer
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND a.request_status <> 'CLOSED'
        AND a.request_type = 'BUFFER'
        AND a.company_id = in_company_id
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
     
        CURSOR c4
        IS
        SELECT (NVL (SUM (requested_qty),0)) scrap_iss_frm_buffer
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND  a.request_type = 'REPLACEMENT'
        AND a.sub_request_type = 'BUFFER'
        AND a.request_status <> 'CANCELED'
        AND a.company_id = in_company_id
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
        
        CURSOR c5
        IS
        SELECT SUM(NVL(qty,0)) ttl_repair_done
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REPAIR-DONE'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        CURSOR c6
        IS
        SELECT SUM(NVL(qty,0)) ttl_our_fault
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'DAMAGE'
        AND s.faulty_type = 'O'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.from_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        l_pkg_to_refill NUMBER;
        l_refill_to_pkg NUMBER;
        l_issued_buffer NUMBER;
        l_scrap_iss_frm_buffer NUMBER;
        l_repair_done NUMBER;
        l_our_fault_qty NUMBER;
        l_diff NUMBER := 0;
        l_result NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_pkg_to_refill;
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_refill_to_pkg;
        CLOSE c2;
        
        OPEN c3;
            FETCH c3 INTO l_issued_buffer;
        CLOSE c3;
        
        OPEN c4;
            FETCH c4 INTO l_scrap_iss_frm_buffer;
        CLOSE c4;
        
        OPEN c5;
            FETCH c5 INTO l_repair_done;
        CLOSE c5;
        
        OPEN c6;
            FETCH c6 INTO l_our_fault_qty;
        CLOSE c6;
        
        IF NVL(l_repair_done,0) > NVL(l_our_fault_qty,0) THEN
            --l_diff := NVL(l_repair_done,0) - NVL(l_our_fault_qty,0);
            l_diff := 0;
        ELSE
            l_diff := 0;
        END IF;
        
        l_result := (NVL(l_pkg_to_refill,0) + NVL(l_diff,0))
                    - (NVL(l_refill_to_pkg,0) + NVL(l_issued_buffer,0) + NVL(l_scrap_iss_frm_buffer,0) );
        
        RETURN l_result;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ttl_replace_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT NVL(SUM(qty),0) ttl_repair_done
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REPAIR-DONE'
        AND s.transfer_status <> 'CANCELED'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        CURSOR c2
        IS
        SELECT NVL(SUM (requested_qty),0) replaced_qty
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND a.request_status <> 'CLOSED'
        AND a.request_type = 'REPLACEMENT'
        AND a.sub_request_type = 'REPAIRED'
        AND a.company_id = in_company_id 
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
        
        l_ttl_repair_done NUMBER;
        l_replaced_qty NUMBER;
        l_result NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_ttl_repair_done; 
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_replaced_qty; 
        CLOSE c2;
        
        l_result := NVL(l_ttl_repair_done,0) - NVL(l_replaced_qty,0);
        
        RETURN l_result;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ttl_repair_leakage_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT NVL(SUM(qty),0) ttl_repair_done
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REPAIR-DONE'
        AND s.transfer_status <> 'CANCELED'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        CURSOR c2
        IS
        SELECT NVL(SUM (requested_qty),0) replaced_qty
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND a.request_status <> 'CLOSED'
        AND a.request_type = 'LEAKAGE'
        AND a.sub_request_type = 'REPAIRED'
        AND a.company_id = in_company_id 
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
        
        l_ttl_repair_done NUMBER;
        l_replaced_qty NUMBER;
        l_result NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_ttl_repair_done; 
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_replaced_qty; 
        CLOSE c2;
        
        l_result := NVL(l_ttl_repair_done,0) - NVL(l_replaced_qty,0);
        
        RETURN l_result;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_ttl_buffer_leakage_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER
    IS 
        CURSOR c1
        IS
        SELECT SUM (NVL(qty,0)) pkg_to_refill
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'PACKAGE-REFILL'
        AND s.transfer_item_id = in_item_id
        AND s.company_id = in_company_id
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id;
        
        CURSOR c2
        IS
        SELECT SUM (NVL(qty,0)) refill_to_pkg
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REFILL-PACKAGE'
        AND s.item_id = in_item_id
        AND s.company_id = in_company_id
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id ;
        
        CURSOR c3 
        IS
        SELECT (NVL (SUM (requested_qty),0)) - (NVL (SUM (received_qty),0)) ttl_issued_buffer
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND a.request_status <> 'CLOSED'
        AND a.request_type = 'BUFFER'
        AND a.company_id = in_company_id
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
     
        CURSOR c4
        IS
        SELECT (NVL (SUM (requested_qty),0)) scrap_iss_frm_buffer
        FROM inv_customer_request_m a, 
             inv_customer_request_d b
        WHERE a.request_id = b.request_id
        AND  a.request_type = 'LEAKAGE'
        AND a.sub_request_type = 'BUFFER'
        AND a.request_status <> 'CANCELED'
        AND a.company_id = in_company_id
        AND a.branch_id = in_branch_id
        AND a.location_id = in_location_id
        AND b.item_id = in_item_id;
        
        CURSOR c5
        IS
        SELECT SUM(NVL(qty,0)) ttl_repair_done
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'REPAIR-DONE'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.to_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        CURSOR c6
        IS
        SELECT SUM(NVL(qty,0)) ttl_our_fault
        FROM inv_stock_transfer_scrap s
        WHERE  s.transfer_status = 'APPROVED'
        AND s.transfer_type = 'DAMAGE'
        AND s.faulty_type = 'O'
        AND s.company_id = in_company_id 
        AND s.branch_id = in_branch_id
        AND s.from_location_id = in_location_id
        AND s.item_id = in_item_id;
        
        l_pkg_to_refill NUMBER;
        l_refill_to_pkg NUMBER;
        l_issued_buffer NUMBER;
        l_scrap_iss_frm_buffer NUMBER;
        l_repair_done NUMBER;
        l_our_fault_qty NUMBER;
        l_diff NUMBER := 0;
        l_result NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_pkg_to_refill;
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_refill_to_pkg;
        CLOSE c2;
        
        OPEN c3;
            FETCH c3 INTO l_issued_buffer;
        CLOSE c3;
        
        OPEN c4;
            FETCH c4 INTO l_scrap_iss_frm_buffer;
        CLOSE c4;
        
        OPEN c5;
            FETCH c5 INTO l_repair_done;
        CLOSE c5;
        
        OPEN c6;
            FETCH c6 INTO l_our_fault_qty;
        CLOSE c6;
        
        IF NVL(l_repair_done,0) > NVL(l_our_fault_qty,0) THEN
            --l_diff := NVL(l_repair_done,0) - NVL(l_our_fault_qty,0);
            l_diff := 0;
        ELSE
            l_diff := 0;
        END IF;
        
        l_result := (NVL(l_pkg_to_refill,0) + NVL(l_diff,0))
                    - (NVL(l_refill_to_pkg,0) + NVL(l_issued_buffer,0) + NVL(l_scrap_iss_frm_buffer,0) );
        
        RETURN l_result;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE close_leakage_request (
        in_request_id   IN  NUMBER,
        out_error_code  OUT NUMBER,
        out_error_text  OUT NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT m.to_cust_id,
               d.item_id,
               m.created_by
        FROM inv_customer_request_m m,
             inv_customer_request_d d
        WHERE m.request_id = d.request_id
        AND m.request_id = in_request_id;
        
        l_customer_id NUMBER;
        l_item_id NUMBER;
        l_cnt NUMBER;
        l_opening_qty NUMBER := 0;
        l_issued_qty NUMBER := 0;
        l_user_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_customer_id , l_item_id , l_user_id; 
        CLOSE c1;
        
        SELECT COUNT(*)
        INTO l_cnt 
        FROM inv_customer_request_m m,
             inv_customer_request_d d
        WHERE m.request_id = d.request_id
        AND m.to_cust_id = l_customer_id
        AND m.request_status ='APPROVED'
        AND m.request_type = 'LEAKAGE'
        AND d.item_id = l_item_id;
        
        IF l_cnt > 0 THEN
            SELECT NVL(rd.opening_qty,0) + NVL(rd.requested_qty,0) op_qty , NVL(rd.issued_qty,0) issued_qty
            INTO l_opening_qty, l_issued_qty
            FROM inv_customer_request_m rm,
                 inv_customer_request_d rd
            WHERE rm.request_id = rd.request_id
            AND rm.request_status ='APPROVED'
            AND rm.request_type = 'LEAKAGE'
            AND rm.to_cust_id = l_customer_id
            AND rd.item_id = l_item_id;
            
            UPDATE inv_customer_request_d
            SET opening_qty = l_opening_qty,
                issued_qty = l_issued_qty
            WHERE request_id = in_request_id;

            
            UPDATE inv_customer_request_m
            SET request_status = 'CLOSED',
                closed_by = l_user_id,
                closed_date = SYSDATE
            WHERE request_status ='APPROVED'
            AND to_cust_id = l_customer_id
            AND request_type = 'LEAKAGE'
            AND request_id = (SELECT m.request_id
                              FROM inv_customer_request_m m,
                                   inv_customer_request_d d
                              WHERE m.request_id = d.request_id
                              AND m.to_cust_id = l_customer_id
                              AND m.request_status ='APPROVED'
                              AND m.request_type = 'LEAKAGE'
                              AND d.item_id = l_item_id );

            COMMIT;
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;  
    
    PROCEDURE ins_irn_for_scn (
        in_igp_id         IN  NUMBER,
        in_user_id        IN  NUMBER,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2  
    )
    IS
        CURSOR igp_data
        IS
        SELECT igpi.po_id,
               po.po_no,
               igp.igp_id,
               igp.igp_no,
               ind.indent_id,
               ind.indent_no,
               ind.org_id,
               po.PO_TYPE,
               igpi.received_qty,
               igp.vendor_id,
               po.currency,
               igp.company_id,
               igp.branch_id,
               igp.location_id,
               igpi.propane_ratio,
               igpi.propane_rate,
               igpi.butane_ratio,
               igpi.butane_rate,
               igpi.premiun_rate,
               igpi.ttl_per
        FROM inv_igps igp,
             inv_igp_items igpi,
             inv_indents ind,
             inv_pos po
        WHERE igp.igp_id = igpi.igp_id
        AND igpi.indent_id = ind.indent_id
        AND igpi.po_id = po.po_id
        AND igp.igp_id = in_igp_id
        ORDER BY org_id, igpi.po_id;
        
        po_id number(8);
        org_id number(8);
        iirn_id number(8);
        iirn_item_id number(8);
        curr varchar2(10);
        p_type char(1);
        po_no varchar2(50);
        indent_no varchar2(50);
        igp_no varchar2(50);
        iirn_no varchar2(50);

    BEGIN
        po_id :=  0;
        org_id := 0;
        
        FOR itm IN igp_data LOOP
            
            IF NOT (po_id = itm.po_id AND org_id = itm.org_id) THEN
                po_id := itm.po_id;
                org_id := itm.org_id;     
                curr := itm.currency;
                p_type := itm.po_type;
                po_no := itm.po_no;
                indent_no := itm.indent_no;
                igp_no := itm.igp_no;
                
                SELECT NVL(MAX(irn_id),0)+1 
                INTO iirn_id 
                FROM inv_irns;
                
                SELECT NVL(MAX(irn_no),0)+1 
                INTO iirn_no
                FROM inv_irns
                WHERE company_id = itm.company_id
                AND branch_id = itm.branch_id;

                INSERT INTO inv_irns (
                    irn_id,
                    irn_no,
                    vendor_id,
                    po_id,
                    po_no,
                    org_id,
                    igp_id,
                    igp_no,
                    irn_status,
                    created_by,
                    creation_date,
                    last_updated_by,
                    last_update_date,
                    imports,
                    is_done,
                    company_id, 
                    branch_id, 
                    location_id,
                    irn_type
                )
                VALUES (
                    iirn_id,
                    iirn_no,
                    itm.vendor_id,
                    itm.po_id,
                    itm.po_no,
                    itm.org_id,
                    itm.igp_id,
                    itm.igp_no,
                    'PREPARED',
                    in_user_id,
                    SYSDATE,
                    in_user_id,
                    SYSDATE,
                    DECODE(p_type,'I','Y','N'),
                    'N',
                    itm.company_id,
                    itm.branch_id,
                    itm.location_id,
                    'S'
                );
            END IF;
            
            SELECT inv_irn_item_s.nextval 
            INTO iirn_item_id 
            FROM dual;
            
            INSERT INTO inv_irn_items (
                irn_item_id,
                irn_id,
                indent_id,
                indent_no,
                igp_qty,
                received_qty,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                propane_ratio,
                propane_rate,
                butane_ratio,
                butane_rate,
                premiun_rate,
                ttl_per
            )
            VALUES (
                iirn_item_id,
                iirn_id,
                itm.indent_id,
                itm.indent_no,
                itm.received_qty,
                itm.received_qty,
                in_user_id,
                SYSDATE,
                in_user_id,
                SYSDATE,
                itm.propane_ratio,
                itm.propane_rate,
                itm.butane_ratio,
                itm.butane_rate,
                itm.premiun_rate,
                itm.ttl_per
            );

            UPDATE inv_indents
            SET indent_status='IRN_CREATED'
            WHERE indent_id=itm.indent_id;
        END LOOP;
        
        UPDATE inv_igps 
        SET igp_status ='IRN_CREATED' 
        WHERE igp_id = in_igp_id;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    PROCEDURE create_grn_for_scn (
        irnid             IN  inv_irns.irn_id%type,
        user_id           IN  NUMBER,
        company_id        IN  NUMBER, 
        branch_id         IN  VARCHAR2,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2 
    )
    IS
        grnid NUMBER(8);
        grnno VARCHAR2(50);
        poid NUMBER(8);
        po_no VARCHAR2(50);
        irn_no NUMBER;
        bill_no VARCHAR2(50);
        location_id NUMBER;
        ind_qty NUMBER(12,3);
        grn_qty NUMBER(12,3);
        v_unbilled_acc_id NUMBER(8);
        v_exise_duty NUMBER(12,8);
        p_mir_id NUMBER;
        v_destractive_qty  NUMBER;
        v_segment1 VARCHAR2(5);
        msg_h VARCHAR2(4000);
        msg_t VARCHAR2(4000);
        msg   VARCHAR2(4000);
        p_message VARCHAR2(4000);
        p_subject VARCHAR2(4000);
        p_check  NUMBER;
        v_item_code VARCHAR2(20);
        v_item_desc VARCHAR2(500);
        v_part VARCHAR2(100);
        v_igp_id NUMBER;
        v_igp_date DATE;
        v_new_exise_duty NUMBER(12,4);
        v_old_exise_duty NUMBER(12,4);
        p_company_id NUMBER;
        p_branch_id VARCHAR2(10);

        CURSOR grn_item_data 
        IS 
        SELECT igi.indent_id,
               igi.item_id,
               igi.grn_id,
               igi.irn_item_id,
               igil.item_locator_id,
               qty,
               igi.rate,
               round(received_qty*igi.rate,0) val,
               igi.creation_date
        FROM inv_grn_items igi,
             inv_grn_item_locators igil
        WHERE igi.grn_item_id = igil.grn_item_id
        AND igi.irn_id = irnid;
        
        CURSOR grn_item_data2 
        IS 
        SELECT irn_item_id,
               accepted_qty
        FROM inv_irn_items
        WHERE irn_id = irnid
        AND accepted_qty > 0; 

        rec_item grn_item_data%ROWTYPE;
        l_cnt NUMBER;
    BEGIN
        
        SELECT COUNT(*)
        INTO l_cnt
        FROM (
            SELECT irn_item_id,
                   accepted_qty
            FROM inv_irn_items
            WHERE irn_id = irnid
            AND accepted_qty > 0
        );
        
        p_company_id := company_id;
        p_branch_id := branch_id;
        
        IF l_cnt > 0 THEN
        
            DELETE FROM inv_grn_locators_tmp 
            WHERE irn_id = irnid;
            
            BEGIN        
                INSERT INTO inv_grn_locators_tmp 
                SELECT inv_irn_items.irn_id,
                       inv_irn_items.irn_item_id,
                       inv_item_locators.item_locator_id,
                       0,
                       p_company_id,
                       p_branch_id
                FROM inv_irn_items,inv_item_locators ,
                     inv_indents , 
                     inv_irns 
                WHERE inv_indents.item_id=  inv_item_locators.item_id 
                AND  inv_irn_items.indent_id =  inv_indents.indent_id
                AND  inv_irn_items.irn_id = inv_irns.irn_id
                AND  inv_irn_items.irn_id = irnid;    
                
                IF SQL%NOTFOUND THEN
                    out_error_code := SQLCODE;
                    out_error_text := SQLERRM;
                END IF;
            END;
            
            FOR irn_loc IN grn_item_data2 LOOP
                UPDATE inv_grn_locators_tmp iglt
                SET qty = irn_loc.accepted_qty 
                WHERE irn_item_id = irn_loc.irn_item_id
                and locator_id = (SELECT MAX(locator_id) 
                                  FROM  inv_grn_locators_tmp 
                                  WHERE iglt.irn_id = irn_id
                                  AND iglt.irn_item_id = irn_item_id);
                                                                                   
            END LOOP;
        
                    
            SELECT NVL(MAX(grn_id),0)+1 
            INTO grnid 
            FROM inv_grns;
        
            SELECT NVL(MAX(grn_no),0)+1
            INTO grnno
            FROM inv_grns
            WHERE company_id = company_id
            AND branch_id = branch_id ;
            
            SELECT po_id,
                   po_no,
                   irn_no,
                   location_id,
                   bill_no_scn
            INTO poid,
                 po_no,
                 irn_no,
                 location_id,
                 bill_no
            FROM inv_irns 
            WHERE irn_id = irnid;
        
            SELECT value 
            INTO v_unbilled_acc_id
            FROM sys_parms 
            WHERE parameter_id = 12;

            INSERT INTO inv_grns (
                grn_id,
                grn_no,
                irn_id,
                irn_no,
                po_id,
                po_no,
                grn_status,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                gl_unbilled_account_id,
                company_id,
                branch_id,
                location_id,
                bill_no,
                grn_type
            )
            VALUES ( 
                grnid,
                grnno,
                irnid,
                irn_no,
                poid,
                po_no,
                'CLOSED',
                user_id,
                 SYSDATE,
                user_id,
                SYSDATE,
                v_unbilled_acc_id,
                company_id,
                branch_id, 
                location_id,
                bill_no,
                'S'
            );

            
            INSERT INTO inv_grn_items (
                grn_item_id,
                grn_id,
                irn_item_id,
                irn_id,
                indent_id,
                indent_no,
                item_id,
                received_qty,
                rate,
                value,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                gl_asset_account_id,
                panelty_amount,
                grn_exise_duty
            )  
            SELECT inv_grn_items_s.NEXTVAL,
                   grnid,
                   irn_item_id,
                   inv_irn_items.irn_id,
                   inv_irn_items.indent_id,
                   inv_irn_items.indent_no,
                   inv_indents.item_id,
                   NVL(accepted_qty,0),
                   DECODE(inv_irns.imports,'N',inv_po_items.rate,inv_irn_items.pkr_rate),
                   DECODE(inv_irns.imports,'N',(nvl(accepted_qty,0)*inv_po_items.rate),pkr_value),                            
                   user_id,
                   SYSDATE,
                   user_id,
                   SYSDATE, 
                   inv_items.gl_asset_acc_id, 
                   inv_irn_items.panelty_amount,
                   0
            FROM inv_irn_items,
                 inv_indents,
                 inv_po_items,
                 inv_irns, 
                 inv_items
            WHERE inv_irn_items.indent_id = inv_indents.indent_id
            AND inv_irns.irn_id=inv_irn_items.irn_id
            AND inv_po_items.indent_id = inv_irn_items.indent_id 
            AND inv_po_items.PO_id = poid 
            AND inv_irn_items.irn_id =  irnid
            AND inv_indents.item_id = inv_items.item_id
            AND NVL(accepted_qty,0) <> 0;

             
            INSERT INTO inv_grn_item_locators 
            SELECT inv_grn_item_locators_s.NEXTVAL,
                   grn_id,
                   grn_item_id,
                   inv_grn_locators_tmp.locator_id,
                   qty,
                   company_id, 
                   branch_id
            FROM inv_grn_locators_tmp,
                 inv_grn_items
            WHERE inv_grn_items.irn_item_id = inv_grn_locators_tmp.irn_item_id
            AND inv_grn_items.grn_id = grnid  
            AND inv_grn_locators_tmp.qty > 0;
            
            UPDATE inv_irns 
            SET irn_status = 'CLOSED'
            WHERE irn_id = irnid;

            OPEN grn_item_data;
            LOOP
                FETCH grn_item_data INTO rec_item;
                EXIT WHEN grn_item_data%NOTFOUND;

                SELECT indent_qty 
                INTO ind_qty
                FROM inv_indents 
                WHERE indent_id = rec_item.indent_id;
                              
                SELECT NVL(SUM(received_qty),0) 
                INTO grn_qty
                FROM inv_grn_items 
                WHERE indent_id = rec_item.indent_id;
                                          
                IF grn_qty >= ind_qty THEN
                    UPDATE inv_indents                 
                    SET indent_status='CLOSED'
                    WHERE indent_id = rec_item.indent_id;
                END IF;

                UPDATE inv_item_locators 
                SET qty = NVL(qty,0)+ rec_item.qty
                WHERE item_locator_id = rec_item.item_locator_id;    
              
            END LOOP;

            CLOSE grn_item_data;
            inv_supp.prc_po_close(poid);
            COMMIT;
            
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    PROCEDURE prc_po_close (
        p_po_id inv_pos.po_id%type
    )
    IS
        CURSOR c1 
        IS
        SELECT NVL(SUM(ship_qty),0)-NVL(SUM(received_qty),0) bal
        FROM inv_po_item_shipments
        WHERE po_id=p_po_id
        GROUP BY po_id;
    BEGIN
        FOR i IN c1 LOOP
            IF i.bal<=0 THEN
                UPDATE inv_pos
                SET po_status='CLOSED'
                WHERE po_id=p_po_id;
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_inv_igp_checked (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_vendor_id      IN  NUMBER,
        in_user_id        IN  NUMBER
    )
    IS
    BEGIN
        DELETE FROM inv_igp_checked 
        WHERE user_id = in_user_id;
        COMMIT;

        INSERT INTO inv_igp_checked (
            po_id, 
            indent_id, 
            po_item_shipment_id, 
            received_qty, 
            po_qty, 
            po_received_qty, 
            po_ship_date, 
            company_id, 
            branch_id, 
            location_id, 
            po_no, 
            indent_no, 
            user_id, 
            propane_ratio, 
            propane_rate, 
            butane_ratio, 
            butane_rate, 
            premiun_rate, 
            ttl_per
        )            
        SELECT po.po_id,
               po_items.indent_id,
               shipment.po_item_shipment_id,
               0 received_qty,
               shipment.ship_qty,
               shipment.received_qty,
               shipment.ship_date,
               company_id, 
               branch_id,
               po_items.location_id, 
               po.po_no, 
               po_items.indent_no, 
               in_user_id,
               propane_ratio,
               propane_rate,
               butane_ratio,
               butane_rate,
               premiun_rate,
               ttl_per
        FROM inv_pos po,
             inv_po_items po_items,
             inv_po_item_shipments shipment
        WHERE po.po_id = po_items.po_id
        AND po_items.po_item_id = shipment.po_item_id
        AND po.vendor_id = in_vendor_id
        AND po.company_id = in_company_id
        AND po.branch_id = in_branch_id
        AND po_items.location_id = in_location_id
        AND po.po_status ='APPROVED' 
        AND po.pur_order_type = 'P'
        AND shipment.ship_qty > shipment.received_qty ;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_inv_igp_checked_s (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_vendor_id      IN  NUMBER,
        in_user_id        IN  NUMBER
    )
    IS
    BEGIN
        DELETE FROM inv_igp_checked 
        WHERE user_id = in_user_id;
        COMMIT;

        INSERT INTO inv_igp_checked (
            po_id, 
            indent_id, 
            po_item_shipment_id, 
            received_qty, 
            po_qty, 
            po_received_qty, 
            po_ship_date, 
            company_id, 
            branch_id, 
            location_id, 
            po_no, 
            indent_no, 
            user_id, 
            propane_ratio, 
            propane_rate, 
            butane_ratio, 
            butane_rate, 
            premiun_rate, 
            ttl_per
        )            
        SELECT po.po_id,
               po_items.indent_id,
               shipment.po_item_shipment_id,
               0 received_qty,
               shipment.ship_qty,
               shipment.received_qty,
               shipment.ship_date,
               company_id, 
               branch_id,
               po_items.location_id, 
               po.po_no, 
               po_items.indent_no, 
               in_user_id,
               propane_ratio,
               propane_rate,
               butane_ratio,
               butane_rate,
               premiun_rate,
               ttl_per
        FROM inv_pos po,
             inv_po_items po_items,
             inv_po_item_shipments shipment
        WHERE po.po_id = po_items.po_id
        AND po_items.po_item_id = shipment.po_item_id
        AND po.vendor_id = in_vendor_id
        AND po.company_id = in_company_id
        AND po.branch_id = in_branch_id
        AND po_items.location_id = in_location_id
        AND po.po_status ='APPROVED' 
        AND po.pur_order_type = 'S'
        AND shipment.ship_qty > shipment.received_qty ;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_indent_cs_from_pi (
        in_pi_id IN NUMBER,
        in_user_id IN NUMBER,
        out_error_code OUT VARCHAR2,
        out_error_msg OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT pim.vendor_id,
               pim.currency,
               pim.company_id,
               pim.branch_id,
               pid.location_id,
               '01' purchase_group_id,   -- hard coded , purchase group as 'Production import'
               4 dept_id,                -- hard coded, dept = commercial
               pid.item_id,
               pid.qty,
               ii.uom,
               pid.rate,
               pim.exch_rate,
               pim.freight,
               pim.packing_cost,
               pim.tooling_cost,
               pim.other_cost,
               pim.cost_terms,
               pim.mode_of_payment,
               pim.p_inv_m_id pi_id,
               pim.invoice_date
        FROM performa_inv_master pim,
             perform_inv_detail pid,
             inv_items ii
        WHERE pim.p_inv_m_id = pid.p_inv_m_id
        AND pid.item_id = ii.item_id
        AND pim.p_inv_status = 'CREATED'
        AND pim.p_inv_m_id = in_pi_id;
        l_indent_id NUMBER;
        l_indent_no NUMBER;
        l_location_name VARCHAR2(100);
        l_cs_id NUMBER;
        l_cs_no NUMBER;
        l_cs_item_id NUMBER;
        l_cs_item_vendor_id NUMBER;
        loop_counter NUMBER := 0;
    BEGIN
        FOR m IN c1 LOOP
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_id
            FROM inv_indents;
            
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_no
            FROM inv_indents
            WHERE company_id = m.company_id
            AND branch_id = m.branch_id;
            
            SELECT location_name
            INTO l_location_name
            FROM inv_locations
            WHERE location_id = m.location_id;
            
            INSERT INTO inv_indents (
                indent_id,
                indent_no,
                company_id,
                branch_id,
                location_id,
                location_name,
                org_id,
                purchase_group_id,
                item_id,
                with_sample,
                indent_qty,
                indent_status,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                urgent,
                imports,
                cep_type,
                emergency,
                hod_app_by,
                hod_approval_date,
                approved_by,
                approved_date,
                remarks,
                pi_id
            )
            VALUES (
                l_indent_id,
                l_indent_no,
                m.company_id,
                m.branch_id,
                m.location_id,
                l_location_name,
                m.dept_id,
                m.purchase_group_id,
                m.item_id,
                'N',
                m.qty,
                'PO_CREATED',
                in_user_id,
                m.invoice_date,
                in_user_id,
                m.invoice_date,
                'N',
                'Y',
                'R',
                'N',
                in_user_id,
                m.invoice_date,
                in_user_id,
                m.invoice_date,
                'INDENT CREATED FOR PI',
                m.pi_id
            );
            COMMIT;
            
            IF loop_counter = 0 THEN
                SELECT inv_cs_s.NEXTVAL
                INTO l_cs_id
                FROM dual;
                
                SELECT NVL(MAX(cs_no),0)+1
                INTO l_cs_no
                FROM inv_cs
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                INSERT INTO inv_cs (
                    cs_id, 
                    company_id , 
                    branch_id , 
                    buyer_id, 
                    remarks, 
                    created_by,
                    creation_date,
                    last_updated_by, 
                    last_update_date, 
                    cs_status, 
                    cs_validity_date,
                    type,
                    cs_no,
                    pi_id,
                    hod_app_by,
                    hod_app_date,
                    checked_by,
                    checked_date,
                    prepared_by,
                    prepared_date,
                    pre_app_by,
                    pre_app_date,
                    approved_by,
                    approved_date
                )
                VALUES (
                    l_cs_id,
                    m.company_id,
                    m.branch_id,
                    NULL,
                    'CS CREATED FOR PI',
                    in_user_id,
                    m.invoice_date,
                    in_user_id,
                    m.invoice_date,
                    'CLOSED',
                    NULL,
                    'IMPORTS',
                    l_cs_no,
                    m.pi_id,
                    in_user_id,
                    m.invoice_date,
                    in_user_id,
                    m.invoice_date,
                    in_user_id,
                    m.invoice_date,
                    in_user_id,
                    m.invoice_date,
                    in_user_id,
                    m.invoice_date
                );
                COMMIT;
            END IF;
            loop_counter := loop_counter + 1;
            l_cs_item_id := inv_cs_items_s.nextval ; 
            INSERT INTO inv_cs_items (
                cs_item_id,
                cs_id,
                indent_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                location_id,
                location_name,
                purchase_group_id,
                indent_no
            )
            VALUES (
                l_cs_item_id,
                l_cs_id,
                l_indent_id,
                'CS ITEM FOR PI',
                in_user_id,
                m.invoice_date,
                in_user_id,
                m.invoice_date,
                m.location_id,
                l_location_name,
                m.purchase_group_id,
                l_indent_no
            );
            COMMIT;
            
            l_cs_item_vendor_id := inv_cs_items_venders_s.NEXTVAL;
            
            INSERT INTO inv_cs_items_venders (
                cs_items_vender_id,
                cs_item_id,
                indent_id,
                vender_id,
                rate,
                approved_qty,
                amount,
                approved,
                payment_terms,
                po_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                delivery_terms,
                performa_invoice,
                currency,
                exch_rate,
                freight,
                other_cost,
                tooling_cost,
                packing_cost
            )
            VALUES (
                l_cs_item_vendor_id,
                l_cs_item_id,
                l_indent_id,
                m.vendor_id,
                m.rate,
                m.qty,
                m.rate * m.qty,
                'Y',
                m.mode_of_payment,
                NULL,
                'RECORD CREATED FROM PI',
                in_user_id,
                m.invoice_date,
                in_user_id,
                m.invoice_date,
                m.cost_terms,
                'Y',
                m.currency,
                m.exch_rate,
                m.freight,
                m.other_cost,
                m.tooling_cost,
                m.packing_cost
            );
            COMMIT;
        END LOOP;

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN 
        out_error_code := SQLCODE;
        out_error_msg :=  SQLERRM;
    END;
    
    PROCEDURE ins_indent_cs_from_po (
        in_po_id IN NUMBER,
        in_user_id IN NUMBER,
        out_error_code OUT VARCHAR2,
        out_error_msg OUT VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT m.vendor_id,
               m.currency,
               m.company_id,
               m.branch_id,
               d.location_id,
               '01' purchase_group_id,   -- hard coded , purchase group as 'Production import'
               1 dept_id,                -- hard coded, dept = commercial
               d.item_id,
               d.qty,
               ii.uom,
               d.rate,
               0 exch_rate,
               0 freight,
               0 packing_cost,
               0 tooling_cost,
               0 other_cost,
               m.payment_terms,
               null mode_of_payment,
               m.po_id po_id,
               m.creation_date po_date,
               d.po_item_id,
               m.term_id,
               m.pur_order_type,
               m.app_name
        FROM inv_pos m,
             inv_po_items d,
             inv_items ii
        WHERE m.po_id = d.po_id
        AND d.item_id = ii.item_id
        AND m.po_id = in_po_id;
        l_indent_id NUMBER;
        l_indent_no NUMBER;
        l_location_name VARCHAR2(100);
        l_cs_id NUMBER;
        l_cs_no NUMBER;
        l_cs_item_id NUMBER;
        l_cs_item_vendor_id NUMBER;
        loop_counter NUMBER := 0;
        
    BEGIN
        FOR m IN c1 LOOP
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_id
            FROM inv_indents;
            
            SELECT NVL(MAX(indent_id),0)+1
            INTO l_indent_no
            FROM inv_indents
            WHERE company_id = m.company_id
            AND branch_id = m.branch_id;
            
            SELECT location_name
            INTO l_location_name
            FROM inv_locations
            WHERE location_id = m.location_id;
            
            INSERT INTO inv_indents (
                indent_id,
                indent_no,
                company_id,
                branch_id,
                location_id,
                location_name,
                org_id,
                purchase_group_id,
                item_id,
                with_sample,
                indent_qty,
                indent_status,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                urgent,
                imports,
                cep_type,
                emergency,
                hod_app_by,
                hod_approval_date,
                approved_by,
                approved_date,
                remarks,
                pi_id,
                indent_type,
                indent_sub_type,
                indent_service_type,
                app_name
            )
            VALUES (
                l_indent_id,
                l_indent_no,
                m.company_id,
                m.branch_id,
                m.location_id,
                l_location_name,
                m.dept_id,
                m.purchase_group_id,
                m.item_id,
                'N',
                m.qty,
                'PO_CREATED',
                in_user_id,
                m.po_date,
                in_user_id,
                m.po_date,
                'N',
                'N',
                'R',
                'N',
                in_user_id,
                m.po_date,
                in_user_id,
                m.po_date,
                'INDENT CREATED FOR PO',
                m.po_id,
                m.pur_order_type,
                DECODE(m.pur_order_type,'P','04','08'),
                DECODE(m.pur_order_type,'P',NULL,'34'),
                m.app_name
            );
            
            UPDATE inv_po_items
            SET indent_id = l_indent_id,
                indent_no = l_indent_no
            WHERE po_item_id = m.po_item_id;
            
            COMMIT;
            
            IF loop_counter = 0 THEN
                SELECT inv_cs_s.NEXTVAL
                INTO l_cs_id
                FROM dual;
                
                SELECT NVL(MAX(cs_no),0)+1
                INTO l_cs_no
                FROM inv_cs
                WHERE company_id = m.company_id
                AND branch_id = m.branch_id;
                
                INSERT INTO inv_cs (
                    cs_id, 
                    company_id , 
                    branch_id , 
                    buyer_id, 
                    remarks, 
                    created_by,
                    creation_date,
                    last_updated_by, 
                    last_update_date, 
                    cs_status, 
                    type,
                    cs_no,
                    pi_id,
                    hod_app_by,
                    hod_app_date,
                    checked_by,
                    checked_date,
                    prepared_by,
                    prepared_date,
                    pre_app_by,
                    pre_app_date,
                    approved_by,
                    approved_date,
                    term_id,
                    cs_type,
                    cs_validity_date,
                    app_name
                )
                VALUES (
                    l_cs_id,
                    m.company_id,
                    m.branch_id,
                    in_user_id,
                    'CS CREATED FOR PO',
                    in_user_id,
                    m.po_date,
                    in_user_id,
                    m.po_date,
                    'CLOSED',
                    'LOCAL',
                    l_cs_no,
                    m.po_id,
                    in_user_id,
                    m.po_date,
                    in_user_id,
                    m.po_date,
                    in_user_id,
                    m.po_date,
                    in_user_id,
                    m.po_date,
                    in_user_id,
                    m.po_date,
                    m.term_id,
                    m.pur_order_type,
                    m.po_date + 30,
                    m.app_name
                );
                
                
            END IF;
            loop_counter := loop_counter + 1;
            l_cs_item_id := inv_cs_items_s.nextval ; 
            INSERT INTO inv_cs_items (
                cs_item_id,
                cs_id,
                indent_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                location_id,
                location_name,
                purchase_group_id,
                indent_no
            )
            VALUES (
                l_cs_item_id,
                l_cs_id,
                l_indent_id,
                'CS ITEM FOR PO',
                in_user_id,
                m.po_date,
                in_user_id,
                m.po_date,
                m.location_id,
                l_location_name,
                m.purchase_group_id,
                l_indent_no
            );
            
            UPDATE inv_po_items
            SET cs_id      = l_cs_id,
                cs_no      = l_cs_no,
                cs_item_id = l_cs_item_id
            WHERE po_item_id = m.po_item_id;
                
            COMMIT;
            
            COMMIT;
            
            l_cs_item_vendor_id := inv_cs_items_venders_s.NEXTVAL;
            
            INSERT INTO inv_cs_items_venders (
                cs_items_vender_id,
                cs_item_id,
                indent_id,
                vender_id,
                rate,
                approved_qty,
                amount,
                approved,
                payment_terms,
                po_id,
                remarks,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                delivery_terms,
                performa_invoice,
                currency,
                exch_rate,
                freight,
                other_cost,
                tooling_cost,
                packing_cost
            )
            VALUES (
                l_cs_item_vendor_id,
                l_cs_item_id,
                l_indent_id,
                m.vendor_id,
                m.rate,
                m.qty,
                m.rate * m.qty,
                'Y',
                m.mode_of_payment,
                NULL,
                'RECORD CREATED FROM PO',
                in_user_id,
                m.po_date,
                in_user_id,
                m.po_date,
                m.payment_terms,
                'N',
                m.currency,
                m.exch_rate,
                m.freight,
                m.other_cost,
                m.tooling_cost,
                m.packing_cost
            );
            COMMIT;
        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN 
        out_error_code := SQLCODE;
        out_error_msg :=  SQLERRM;
    END;
    
    PROCEDURE ins_irn_grn_from_igp (
        in_igp_id IN NUMBER
    )
    IS
        CURSOR c1
        IS
        SELECT igpi.po_id,
               po.po_no,
               igp.igp_id,
               igp.igp_no,
               ind.indent_id,
               ind.indent_no,
               ind.org_id,
               po.po_type,
               igpi.received_qty,
               igp.vendor_id,
               po.currency,
               igp.company_id, 
               igp.branch_id, 
               igp.location_id , 
               igp.creation_date igp_date,
               igp.builty_no AS bill_no,
               igp.igp_type
        FROM inv_igps igp,
             inv_igp_items igpi,
             inv_indents ind,
             inv_pos po
        WHERE igp.igp_id = igpi.igp_id
        AND igpi.indent_id = ind.indent_id
        AND igpi.po_id=po.po_id
        AND igp.igp_id = in_igp_id
        ORDER BY igp.igp_id;
        
        l_igp_id NUMBER;
        l_igp_no NUMBER;
        l_prev_grn_no VARCHAR2(50) := 'kk';
        a number := 1;
        b number := 1;
        
        po_id NUMBER := 0;
        org_id NUMBER := 0;
        curr VARCHAR2(50);
        p_type VARCHAR2(50);
        po_no VARCHAR2(50);
        indent_no NUMBER;
        igp_no NUMBER;
        iirn_id NUMBER;
        iirn_no NUMBER;
        iirn_item_id NUMBER;
        
        l_prev_igp_id NUMBER := 0 ;
        
    BEGIN
        FOR itm IN c1 LOOP
            IF itm.igp_id <> l_prev_igp_id OR b = 1 THEN    
                po_id := itm.po_id;
                org_id := itm.org_id;     
                curr := itm.currency;
                p_type := itm.po_type;
                po_no := itm.po_no;
                indent_no := itm.indent_no;
                igp_no := itm.igp_no;
                            
                SELECT NVL(MAX(IRN_ID),0)+1 
                INTO iirn_id 
                FROM inv_irns;
                            
                SELECT NVL(MAX(irn_no),0)+1 
                INTO iirn_no
                FROM INV_IRNS
                WHERE company_id = 1
                AND branch_id = '01';
                            
                            
                INSERT INTO inv_irns (
                    irn_id,
                    irn_no,
                    vendor_id,
                    po_id,
                    po_no,
                    org_id,
                    igp_id,
                    igp_no,
                    irn_status,
                    created_by,
                    creation_date,
                    last_updated_by,
                    last_update_date,
                    imports,
                    is_done,
                    company_id,
                    branch_id, 
                    location_id,
                    irn_type,
                    approved_by,
                    approved_date,
                    bill_no,
                    bill_no_scn
                )
                VALUES (
                    iirn_id,
                    iirn_no,
                    itm.vendor_id,
                    itm.po_id,
                    itm.po_no,
                    itm.org_id,
                    itm.igp_id,
                    itm.igp_no,
                    'CREATED',
                    121,
                    itm.igp_date,
                    121,
                    SYSDATE,
                    DECODE(p_type,'I','Y','N'),
                    'N',
                    itm.company_id,
                    itm.branch_id, 
                    itm.location_id,
                    itm.igp_type,
                    121,
                    sysdate,
                    DECODE(itm.igp_type,'P',itm.bill_no,NULL),
                    DECODE(itm.igp_type,'S',itm.bill_no,NULL)                
                );
                         
                UPDATE inv_igps 
                SET igp_status ='IRN_CREATED' 
                WHERE igp_id = itm.igp_id;
                         
                b := 2;
            END IF;
        
                    
            SELECT inv_irn_item_s.NEXTVAL 
            INTO iirn_item_id 
            FROM dual;
                        
            INSERT into inv_irn_items (
                irn_item_id,
                irn_id,
                indent_id,
                indent_no,
                igp_qty,
                received_qty,
                accepted_qty,
                created_by,
                creation_date,
                last_updated_by,
                last_update_date,
                inspector_id
            )
            VALUES (
                iirn_item_id,
                iirn_id,
                itm.indent_id,
                itm.indent_no,
                itm.received_qty,
                itm.received_qty,
                itm.received_qty,
                121,
                itm.igp_date,
                121,
                SYSDATE,
                1
            );
            
            UPDATE inv_indents
            SET indent_status='IRN_CREATED'
            WHERE indent_id=itm.indent_id;
                
            l_prev_igp_id := itm.igp_id; 
            
        END LOOP;
            
        COMMIT;

        FOR j IN ( SELECT * 
                   FROM inv_irns 
                   WHERE IMPORTS = 'N' 
                   AND irn_id    = iirn_id
                   --AND TRUNC(last_update_date) = TRUNC(SYSDATE) ORDER BY irn_id 
                 ) LOOP
            DECLARE
                grnid number(8);
                grnno varchar2(50);
                poid number(8);
                ind_qty number(12,3);
                grn_qty number(12,3);
                v_unbilled_acc_id number(8);
                v_exise_duty number(12,8);
                p_mir_id number;
                v_destractive_qty  number;
                v_segment1 varchar2(5);
                msg_h varchar2(4000);
                msg_t varchar2(4000);
                msg   varchar2(4000);
                p_message varchar2(4000);
                p_subject varchar2(4000);
                p_check  number;
                v_item_code varchar2(20);
                v_item_desc varchar2(500);
                v_part varchar2(100);
                v_igp_id number;
                v_igp_date date;
                v_new_exise_duty number(12,4);
                v_old_exise_duty number(12,4);
                
                CURSOR grn_item_data IS 
                SELECT igi.indent_id,
                       igi.item_id,
                       igi.grn_id,
                       igi.irn_item_id,
                       igil.item_locator_id,
                       qty,
                       igi.rate,
                       ROUND(received_qty*igi.rate,0) val,
                       igi.creation_date
                FROM inv_grn_items igi,
                     inv_grn_item_locators igil
                WHERE igi.grn_item_id = igil.grn_item_id
                AND igi.irn_id = j.irn_id;

                rec_item grn_item_data%ROWTYPE;
                
            BEGIN
                        
                SELECT NVL(MAX(grn_id),0)+1 
                INTO grnid 
                FROM inv_grns;
                
                SELECT NVL(MAX(grn_no),0)+1
                INTO grnno
                FROM INV_GRNS
                WHERE company_id = 1
                AND branch_id = '01';
                    
                SELECT po_id 
                INTO poid 
                FROM inv_irns 
                WHERE irn_id = j.irn_id;
                
                SELECT value 
                INTO v_unbilled_acc_id
                FROM sys_parms 
                WHERE parameter_id = 12;
                
                
                BEGIN
                    INSERT INTO inv_grns (
                        grn_id,
                        grn_no,
                        irn_id,
                        irn_no,
                        po_id,
                        po_no,
                        grn_status,
                        created_by,
                        creation_date,
                        last_updated_by,
                        last_update_date,
                        gl_unbilled_account_id,
                        company_id,
                        branch_id,
                        location_id,
                        grn_type,
                        bill_no,
                        pk_id_view
                    )
                    VALUES (
                        grnid,
                        grnno, 
                        j.irn_id,
                        j.irn_no,
                        j.po_id,
                        j.po_no,
                        'CLOSED',
                        121,
                        j.creation_date,
                        121,
                        SYSDATE,
                        v_unbilled_acc_id,
                        1,
                        '01', 
                        j.location_id,
                        j.irn_type,
                        j.bill_no,
                        pk_id_view_s.nextval
                    );
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END ;
                    
                BEGIN
                     INSERT INTO inv_grn_items (
                         grn_item_id,
                         grn_id,
                         irn_item_id,
                         irn_id,
                         indent_id,
                         indent_no,
                         item_id,
                         received_qty,
                         rate,
                         value,
                         created_by,
                         creation_date,
                         last_updated_by,
                         last_update_date, 
                         gl_asset_account_id,
                         panelty_amount,
                         grn_exise_duty
                     )  
                     SELECT inv_grn_items_s.NEXTVAL,
                            grnid,
                            irn_item_id,
                            inv_irn_items.irn_id,
                            inv_irn_items.indent_id,
                            inv_irn_items.indent_no,
                            inv_indents.item_id,
                            NVL(accepted_qty,0),
                            DECODE(inv_irns.imports,'N',inv_po_items.rate,inv_irn_items.pkr_rate),
                            DECODE(inv_irns.imports,'N',(NVL(accepted_qty,0)*inv_po_items.rate),pkr_value),                            
                            121,
                            j.creation_date,
                            121,
                            SYSDATE, 
                            inv_items.gl_asset_acc_id, 
                            inv_irn_items.panelty_amount,
                            0
                     FROM inv_irn_items,
                          inv_indents,
                          inv_po_items ,
                          inv_irns, 
                          inv_items
                     WHERE  inv_irn_items.indent_id = inv_indents.indent_id
                     AND inv_irns.irn_id=inv_irn_items.irn_id
                     AND inv_po_items.indent_id = inv_irn_items.indent_id 
                     AND inv_po_items.PO_id = poid 
                     AND inv_irn_items.irn_id =  j.irn_id
                     AND inv_indents.item_id = inv_items.item_id
                     AND nvl(accepted_qty,0)<>0;
                     
                EXCEPTION WHEN OTHERS THEN
                     NULL;
                END ;
               
                DECLARE
                    CURSOR grn_item_data IS 
                    SELECT irn_item_id,accepted_qty
                    FROM inv_irn_items
                    WHERE irn_id = iirn_id
                    AND accepted_qty > 0;
                BEGIN
                    DELETE FROM inv_grn_locators_tmp  
                    WHERE irn_id = iirn_id;
                        
                    BEGIN        
                        INSERT INTO inv_grn_locators_tmp 
                        SELECT iii.irn_id,iii.irn_item_id,iil.item_locator_id,0,ii.company_id,ii.branch_id
                        FROM inv_irn_items iii
                            , inv_item_locators iil
                            , inv_indents ii
                            , inv_irns ir
                        WHERE ii.item_id = iil.item_id 
                        AND  iii.indent_id        = ii.indent_id
                        AND  iii.irn_id           = ir.irn_id
                        AND  iii.irn_id           = iirn_id  ;    
                    END;
                    FOR Irn_loc IN grn_item_data LOOP
                        UPDATE inv_grn_locators_tmp iglt
                        SET  qty = irn_loc.accepted_qty 
                        WHERE irn_item_id = irn_loc.irn_item_id
                        AND locator_id    = (   SELECT MAX(locator_id) 
                                                FROM inv_grn_locators_tmp 
                                                WHERE iglt.irn_id = irn_id
                                                AND iglt.irn_item_id = irn_item_id
                                            );
                    END LOOP;
                END ;  
                   
                BEGIN
                    INSERT INTO inv_grn_item_locators 
                    SELECT inv_grn_item_locators_s.nextval,
                        grn_id,
                        grn_item_id,
                        inv_grn_locators_tmp.locator_id,
                        qty,company_id, 
                        branch_id
                    FROM inv_grn_locators_tmp,
                        inv_grn_items
                    WHERE inv_grn_items.irn_item_id = inv_grn_locators_tmp.irn_item_id
                    AND inv_grn_items.grn_id = grnid  
                    AND inv_grn_locators_tmp.qty >0;
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END ;                    
                    
                BEGIN
                    UPDATE  inv_irns 
                    SET irn_status = 'CLOSED'
                    WHERE irn_id = j.irn_id;  
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END ;                    
                
             
                OPEN grn_item_data;
                LOOP
                    FETCH grn_item_data INTO rec_item;
                    EXIT WHEN grn_item_data%NOTFOUND;

                    BEGIN
                        SELECT indent_qty 
                        INTO ind_qty
                        FROM inv_indents 
                        WHERE indent_id = rec_item.indent_id;
                    EXCEPTION WHEN OTHERS THEN
                        NULL;
                    END ;
                                
                    BEGIN            
                        SELECT NVL(SUM(received_qty),0) 
                        INTO grn_qty
                        FROM inv_grn_items 
                        WHERE indent_id = rec_item.indent_id;
                    EXCEPTION WHEN OTHERS THEN
                        NULL;
                    END ;
                                
                    BEGIN                                        
                        IF grn_qty >= ind_qty THEN
                            UPDATE     inv_indents                 
                            SET    indent_status='CLOSED'
                            WHERE indent_id = rec_item.indent_id;
                        END IF;
                    EXCEPTION WHEN OTHERS THEN
                        NULL;
                    END ;                                            
                    BEGIN
                        UPDATE  inv_item_locators 
                        SET qty = nvl(qty,0)+ rec_item.qty
                        WHERE item_locator_id = rec_item.item_locator_id;    
                                        
                    EXCEPTION WHEN OTHERS THEN
                        NULL;
                    END ;                                 
                END LOOP;
                
                CLOSE GRN_ITEM_DATA;
                  
                DECLARE
                    CURSOR C1 IS (
                    SELECT nvl(sum(ship_qty),0)-nvl(sum(received_qty),0) bal
                    FROM inv_po_item_shipments
                    WHERE po_id= j.po_id
                    GROUP BY po_id);
                BEGIN
                    FOR i IN c1 LOOP
                        IF I.BAL<=0 THEN
                            UPDATE inv_pos
                            SET po_status='CLOSED'
                            WHERE po_id= j.po_id;                                 
                        END IF;
                    END LOOP;
                END;
            END;
        END LOOP;
        
        COMMIT;
    END;
    
END inv_supp;
/
