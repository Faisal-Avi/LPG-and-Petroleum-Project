CREATE OR REPLACE PACKAGE BODY LPG_TEST.acc_supp
IS
    /*
    -- This function is for getting the advance cheque values in receipt but not yet approved
    */        

    FUNCTION get_adv_chk_draft_value (
        in_invoice_id    IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(d.receipt_amount,0)) 
        FROM ar_receipts m,
             ar_receipt_invoices d
        WHERE m.receipt_id = d.receipt_id
        AND d.invoice_id = in_invoice_id
        AND d.cheque_no IS NOT NULL
        AND m.receipt_status = 'PREPARED';
        
        l_draft_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_draft_amount;
        CLOSE c1;
        RETURN NVL(l_draft_amount,0);
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;

    /*
    -- This function is for checking either the payment term is advance cheque type or not
    */

    FUNCTION check_adv_payment_type (
        in_payment_term  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT NVL(segment3, 'N') ptt
        FROM data_values
        WHERE value_set_id = 8
        AND value_set_value = in_payment_term;
        l_payment_term_type VARCHAR2(10);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_payment_term_type ;
        CLOSE c1;
        RETURN l_payment_term_type;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 'N';
    END;
    
    /*
    -- This function is for getting total advance cheque amount for a invoice
    */

    FUNCTION get_invoice_avd_chk_amt (
        in_invoice_id    IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(ac.balance_amount)
        FROM ar_advance_cheque ac
        WHERE ac.sale_order_id IN (
                                    SELECT sales_order_id
                                    FROM inv_sales_orders so
                                    WHERE so.sales_order_id IN (SELECT DISTINCT sii.sale_order_id
                                                                FROM inv_sales_invoice_items sii
                                                                WHERE sii.sales_invoice_id = in_invoice_id)
                                    AND check_adv_payment_type(so.payment_terms) = 'Y');
        l_total_cheque_amount NUMBER := 0;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_total_cheque_amount;
        CLOSE c1;
        
        RETURN l_total_cheque_amount;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;

    /*
    -- This procedure is created for update advance cheque receipt amount
    */
    
    PROCEDURE upd_ar_adv_cheque (
        in_invoice_id    IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        CURSOR so_dc_ck
        IS
        SELECT DISTINCT so.sales_order_id,
               dc.challan_id,
               ri.cheque_no,
               ri.receipt_amount
        FROM inv_sales_orders so,
             inv_delivery_challans dc,
             inv_delivery_challan_items dci,
             inv_sales_invoices si,
             ar_receipts ar,
             ar_receipt_invoices ri
        WHERE so.sales_order_id = dci.sale_order_id
        AND dc.challan_id = dci.challan_id
        AND dci.challan_id = si.challan_id
        AND si.sales_invoice_id = ri.invoice_id
        AND ar.receipt_id = ri.receipt_id
        AND si.sales_invoice_id = in_invoice_id
        AND so.payment_terms = 'AP';
    BEGIN
        FOR i IN so_dc_ck LOOP
            upd_ar_adv_cheque (
                in_cheque_no     => i.cheque_no,
                in_amount        => i.receipt_amount
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN 
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    PROCEDURE upd_ar_adv_cheque (
        in_cheque_no     IN     VARCHAR2,
        in_amount        IN     NUMBER
    )
    IS
    BEGIN
        UPDATE ar_advance_cheque
        SET receipt_amount = NVL(receipt_amount,0) + in_amount,
            balance_amount = NVL(balance_amount,0) - in_amount
        WHERE cheque_no = in_cheque_no;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
    -- This function is for checking that if a Delivery challan related sale order 
       payment term is Advanced cheque type or not. Checking Segment 3 = 'Y'
    */
    
    FUNCTION check_advance_cheque (
        in_dc_id         IN     NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT sale_order_id
        FROM inv_delivery_challan_items
        WHERE challan_id = in_dc_id;
        
        l_cnt NUMBER := 0;
        l_adv_cheque_type VARCHAR2(50);
        l_cnt_not_entered_data NUMBER := 0;
        
    BEGIN
        FOR m IN c1 LOOP
            SELECT NVL(segment3,'N')
            INTO l_adv_cheque_type
            FROM data_values
            WHERE value_set_id = 8
            AND value_set_value = (SELECT payment_terms
                                   FROM inv_sales_orders
                                   WHERE sales_order_id = m.sale_order_id);
            
            IF l_adv_cheque_type = 'Y' THEN
                SELECT COUNT(*)
                INTO l_cnt
                FROM ar_advance_cheque
                WHERE sale_order_id = m.sale_order_id
                AND delivery_challan_id = in_dc_id;
                
                IF l_cnt = 0 THEN
                    l_cnt_not_entered_data := l_cnt_not_entered_data + 1;
                END IF;
            END IF;
            
            l_cnt := 0;

        END LOOP;
        
        IF l_cnt_not_entered_data > 0 THEN
            RETURN 'STOP';
        ELSE
            RETURN 'OK';
        END IF;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN 'STOP';
    END;
    
    /*
    -- This voucher is generated for the expense part in costing during GRN
    */
    
    
    PROCEDURE inv_grn_expense_voucher (
        in_grn_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        branch             VARCHAR2(2) := in_branch_id ;
        company            NUMBER := in_company_id;
        v_voucher_id       NUMBER;
        v_voucher_no       NUMBER;
        acc_date           DATE := SYSDATE;
    BEGIN
        SELECT TRUNC(creation_date)
        INTO acc_date 
        FROM inv_grns 
        WHERE grn_id = in_grn_id;
        
        SELECT gl_voucher_id_s.NEXTVAL  
        INTO v_voucher_id    
        FROM dual;

        v_voucher_no:= get_voucher_no (acc_date, 'JV', company, branch);
        ---******************** This section is for only raw material costing
 
        INSERT INTO gl_vouchers (
            voucher_id, 
            voucher_type, 
            voucher_no, 
            voucher_date,
            description, 
            created_by, 
            creation_date,
            last_updated_by, 
            last_updated_date, 
            status,
            approved_by, 
            approval_date, 
            posted_by, 
            posting_date, 
            module,
            module_doc, 
            module_doc_id, 
            company_id, 
            branch_id
        )
        VALUES (
            v_voucher_id, 
            'JV', 
            v_voucher_no, 
            acc_date,
            'ENTRY against GRN ID ' || in_grn_id, 
            in_user_id, 
            SYSDATE,
            in_user_id, 
            SYSDATE, 
            'PREPARED',
            NULL, 
            NULL, 
            NULL, 
            NULL, 
            'AP',
            'GRN', 
            in_grn_id, 
            company, 
            branch
        );
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id,
            sub_account_code_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL,
               v_voucher_id, 
               v.account_id, 
               v.dr, 
               v.cr,
               v.naration, 
               in_user_id, 
               SYSDATE, 
               in_user_id, 
               SYSDATE, 
               v.grn_id,
               sub_account_code
        FROM ap_grn_expense_transfer_v v
        WHERE v.grn_id = in_grn_id;

        UPDATE inv_grns 
        SET expense_voucher_id = v_voucher_id
        WHERE grn_id = in_grn_id;
        
        COMMIT;
    END;

    /*
    -- This procedure is created for auto generation of voucher during grn ----  AP
    */
    
    PROCEDURE inv_grn_voucher (
        g_id             IN     NUMBER,
        user_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        branch             VARCHAR2(2) := in_branch_id ;
        company            NUMBER := in_company_id;
        v_voucher_id       NUMBER;
        v_voucher_no       NUMBER;
        acc_date           DATE         := SYSDATE;
    BEGIN
        SELECT TRUNC(creation_date) 
        INTO acc_date 
        FROM inv_grns 
        WHERE grn_id = g_id;
        
        SELECT gl_voucher_id_s.NEXTVAL  
        INTO v_voucher_id    
        FROM dual;

        v_voucher_no:= get_voucher_no (acc_date, 'JVP', company, branch);
        
        ---******************** This section is for only raw material costing
 
        INSERT INTO gl_vouchers (
            voucher_id, 
            voucher_type, 
            voucher_no, 
            voucher_date,
            description, 
            created_by, 
            creation_date,
            last_updated_by, 
            last_updated_date, 
            status,
            approved_by, 
            approval_date, 
            posted_by, 
            posting_date, 
            module,
            module_doc, 
            module_doc_id, 
            company_id, 
            branch_id
        )
        VALUES (
            v_voucher_id, 
            'JVP', 
            v_voucher_no, 
            acc_date,
            'ENTRY against GRN ID ' || g_id, 
            user_id, 
            SYSDATE,
            user_id, 
            SYSDATE, 
            'PREPARED',
            NULL, 
            NULL, 
            NULL, 
            NULL, 
            'AP',
            'GRN', 
            g_id, 
            company, 
            branch
        );
               
   
   
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id,
            sub_account_code_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL,
               v_voucher_id, 
               v.account_id, 
               v.dr, 
               v.cr,
               v.naration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE, 
               v.grn_id,
               sub_account_code
        FROM inv_grn_transfer_v v
        WHERE v.grn_id = g_id;

        UPDATE inv_grns 
        SET voucher_id = v_voucher_id
        WHERE grn_id = g_id;
        
        COMMIT;
        
        --**************************** --> This section is for others expenses during grn
        
        acc_supp.inv_grn_expense_voucher (
            in_grn_id        => g_id,
            in_user_id       => user_id,
            in_company_id    => in_company_id,
            in_branch_id     => in_branch_id
        );

    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    /*
    -- During Invoice Matching (Expense Part)   --   AP
    */
    
    PROCEDURE ap_invoice_expense_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        company    NUMBER  :=  in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        v_id       NUMBER;
        v_no       NUMBER;
        chk        NUMBER;
        acc_date   DATE;
        remarks    VARCHAR2(300);
    BEGIN
        SELECT TRUNC(invoice_date), 
               i.invoice_amount
        INTO acc_date, 
             chk
        FROM ap_invoices i    
        WHERE invoice_id = inv_id;
       
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL    
            INTO v_id      
            FROM dual;
            
            v_no := get_voucher_no(acc_date,'JVP',company,branch);
            
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                posted_by, 
                posting_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id
            )
            SELECT v_id, 
                   'JVP',
                   v_no,
                   acc_date, 
                   'Entry Aginst Invoice ID '|| si.invoice_id , 
                   si.created_by,
                   si.creation_date, 
                   si.last_updated_by, 
                   si.last_update_date,
                  'PREPARED',
                  NULL, 
                  NULL, 
                  NULL, 
                  NULL,
                  'AP', 
                  'INVOICE', 
                  si.invoice_id, 
                  company, 
                  branch
            FROM ap_invoices si, 
                 inv_vendors c
            WHERE si.vendor_id = c.vendor_id 
            AND si.invoice_id = inv_id;
        ELSE
            v_id:=gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, account_id, 
               dr,
               cr, 
               naration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE,
               invoice_id
        FROM ap_inv_expense_transfer_v
        WHERE invoice_id = inv_id;
        
        UPDATE ap_invoices
        SET gl_voucher_expense_id = v_id
        WHERE invoice_id = inv_id;
        
        COMMIT;
    END;
    
    /*
    -- Auto voucher generation during invoice Matching  --   AP
    */
    
    PROCEDURE ap_invoice_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER  :=  in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        v_id       NUMBER;
        v_no       NUMBER;
        chk        NUMBER;
        acc_date   DATE;
        remarks    VARCHAR2(300);
        l_cnt      NUMBER;
    BEGIN
        SELECT TRUNC(accounting_date), 
               i.invoice_amount,
               remarks
        INTO acc_date, 
             chk,
             remarks
        FROM ap_invoices i    
        WHERE invoice_id = inv_id;
        
        SELECT COUNT(*)
        INTO l_cnt 
        FROM ap_invoice_transfer_goods_v
        WHERE invoice_id = inv_id;
        
        IF l_cnt > 0  THEN
        
            IF gl_v_id IS NULL THEN
                SELECT gl_voucher_id_s.NEXTVAL    
                INTO v_id      
                FROM dual;
                
                v_no := get_voucher_no(acc_date,'JVP',company,branch);
                
                INSERT INTO gl_vouchers (
                    voucher_id, 
                    voucher_type, 
                    voucher_no, 
                    voucher_date,
                    description, 
                    created_by, 
                    creation_date,
                    last_updated_by, 
                    last_updated_date, 
                    status,
                    approved_by, 
                    approval_date, 
                    cheked_by, 
                    checked_date, 
                    module,
                    module_doc, 
                    module_doc_id, 
                    company_id, 
                    branch_id,
                    pay_to_id,
                    paid_to,
                    paid_to_type
                )
                SELECT v_id, 
                       'JVP',
                       v_no,
                       acc_date, 
                       remarks || ' Entry Aginst Booking Goods # '|| si.ap_invoice_no, 
                       si.created_by,
                       si.creation_date, 
                       si.last_updated_by, 
                       si.last_update_date,
                      'APPROVED',
                      si.TRANSFER_ID,
                      si.TRANSFER_DATE,
                      si.CREATED_BY,
                      si.CREATION_DATE,
                      'AP', 
                      'INVOICE-GOODS', 
                      si.invoice_id, 
                      company, 
                      branch,
                      si.vendor_id,
                      '01',
                      '05'
                FROM ap_invoices si, 
                     inv_vendors c
                WHERE si.vendor_id = c.vendor_id 
                AND si.invoice_id = inv_id;
            ELSE
                v_id:=gl_v_id;
            END IF;

            INSERT INTO gl_voucher_accounts (
                voucher_account_id, 
                voucher_id, 
                account_id, 
                debit, 
                credit,
                naration, 
                created_by, 
                creation_date, 
                last_updated_by,
                last_update_date, 
                reference_id
            )
            SELECT gl_voucher_account_id_s.NEXTVAL, 
                   v_id, 
                   account_id, 
                   debit,
                   credit, 
                   naration, 
                   user_id, 
                   SYSDATE, 
                   user_id, 
                   SYSDATE,
                   invoice_id
            FROM ap_invoice_transfer_goods_v
            WHERE invoice_id = inv_id;
            
            
            UPDATE ap_invoices
            SET gl_voucher_id = v_id
            WHERE invoice_id = inv_id;
            
            COMMIT;
        
        ELSE
            out_error_code := 'NO DATA';
            out_error_text := 'NO DATA IN VIEW';
        END IF;
        
        --****************** For the expense part
        /*
        acc_supp.ap_invoice_expense_transfer (
            inv_id           => inv_id,
            user_id          => user_id,
            gl_v_id          => gl_v_id,
            in_company_id    => in_company_id,
            in_branch_id     => in_branch_id
        );
        
        COMMIT;
        */
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END ;
    
    /*
    -- during Payment            AP
    */
    
    
    FUNCTION gl_add_voucher (
        x_voucher_type          VARCHAR2,
        x_voucher_date          DATE,
        x_description           VARCHAR2,
        x_created_by            NUMBER,
        x_creation_date         DATE,
        x_approved_by           NUMBER,
        x_status                VARCHAR2,
        x_company_id            NUMBER,
        x_branch_id             VARCHAR2,
        x_module                VARCHAR2,
        x_module_doc            VARCHAR2,
        x_module_doc_id         NUMBER,
        x_reference_no          VARCHAR2,
        x_reference_date        DATE,
        x_paid_amount           NUMBER
    ) RETURN NUMBER
    IS
        xx_voucher_id NUMBER;
        xx_voucher_no NUMBER;
    BEGIN
        SELECT gl_voucher_id_s.NEXTVAL
        INTO xx_voucher_id
        FROM dual;
        
        xx_voucher_no := get_voucher_no (x_voucher_date,x_voucher_type,x_company_id,x_branch_id) ;
        
        INSERT INTO gl_vouchers (
            voucher_id,
            voucher_no,
            voucher_type,
            voucher_date,
            description,
            created_by,
            creation_date,
            status,
            approved_by,
            approval_date,
            company_id,
            branch_id,
            module,
            module_doc,
            module_doc_id,
            reference_no,
            ref_date,
            paid_amount
        )
        VALUES (
            xx_voucher_id,
            xx_voucher_no,
            x_voucher_type,
            TRUNC(x_voucher_date),
            x_description,
            x_created_by,
            x_creation_date,
            x_status,
            x_approved_by,
            NULL,
            x_company_id,
            x_branch_id,
            x_module,
            x_module_doc,
            x_module_doc_id,
            x_reference_no,
            x_reference_date,
            x_paid_amount
        );
        RETURN xx_voucher_id;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- Auto voucher generation during Payment              AP
    */
    
    PROCEDURE ap_payment_transfer (
        pay_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company       NUMBER := in_company_id;
        branch        VARCHAR2(20) := in_branch_id;
        v_id          NUMBER;
        v_no          NUMBER;
        acc_date      DATE;
        description   VARCHAR(250);
        pay_mode      VARCHAR(250);
        ref_no        VARCHAR(250);
        ref_date      DATE;
        pay_amount    NUMBER;
        created_by    NUMBER;
        creation_date DATE;
    BEGIN
        SELECT payment_date,
               paid_amount, 
               'Entry Aginst Payment ID '|| pay_id,
               DECODE (payment_mode, 'CASH', 'CPV', 'BPV'),
               doc_no,
               payment_date,
               created_by,
               TRUNC(creation_date),
               company_id,
               branch_id
        INTO acc_date,
             pay_amount, 
             description,
             pay_mode,
             ref_no,
             ref_date,
             created_by,
             creation_date, 
             company,
             branch
        FROM ap_payments
        WHERE payment_id = pay_id;

        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL    
            INTO v_id      
            FROM dual;
                
            v_no := get_voucher_no(acc_date,pay_mode,company,branch);
                
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                pay_to_id,
                paid_to,
                paid_to_type,
                cheque_number,
                reference_no
            )
            SELECT v_id, 
                   pay_mode,
                   v_no,
                   acc_date, 
                   'Entry Aginst Vendor Name. '|| c.vendor_name , 
                   si.created_by,
                   si.creation_date, 
                   si.last_updated_by, 
                   si.last_update_date,
                  'APPROVED',
                  NULL, 
                  NULL, 
                  'AP', 
                  'PAYMENT', 
                  si.payment_id, 
                  company, 
                  branch,
                  si.vendor_id,
                  '01',
                  '01',
                  ref_no,
                  ref_no
            FROM ap_payments si, 
                 inv_vendors c
            WHERE si.vendor_id = c.vendor_id 
            AND si.payment_id = pay_id;
        ELSE
            v_id:=gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               account_id, 
               debit, 
               credit,
               naration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE, 
               payment_id
        FROM ap_payment_transfer_v
        WHERE payment_id = pay_id
        AND branch_id = in_branch_id;
        
        UPDATE ap_payments
        SET gl_voucher_id = v_id
        WHERE payment_id = pay_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END; 
    
    
    /*
    -- This Consumption voucher will be generated during Delivery Challan  AP
    */
    
    PROCEDURE ap_delivery_challan_transfer (
        in_dc_id         IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER       := in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
    BEGIN
        SELECT gl_voucher_id_s.NEXTVAL
        INTO v_id
        FROM dual;

        SELECT TRUNC(challan_date) 
        INTO acc_date
        FROM inv_delivery_challans
        WHERE challan_id = in_dc_id;


        v_no:=get_voucher_no(acc_date,'JVP',company,branch);
            
        INSERT INTO gl_vouchers (
            voucher_id, 
            voucher_type, 
            voucher_no, 
            voucher_date,
            description, 
            created_by, 
            creation_date,
            last_updated_by, 
            last_updated_date, 
            status,
            approved_by, 
            approval_date, 
            posted_by, 
            posting_date, 
            module,
            module_doc, 
            module_doc_id, 
            company_id, 
            branch_id
        )
        SELECT v_id, 
               'JVP', 
               v_no,
               acc_date, 
               'Entry Against DC# '|| dc.challan_id , 
               dc.created_by,
               dc.creation_date, 
               dc.last_updated_by, 
               dc.last_update_date,
               'PREPARED', 
               NULL, 
               NULL, 
               NULL, 
               NULL,
               'AR', 
               'DELIVERY_CHALLAN', 
               dc.challan_id, 
               company, 
               branch
        FROM inv_delivery_challans dc
        WHERE dc.challan_id = in_dc_id;
        
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               account_id, 
               debit, 
               credit,
               narration, 
               in_user_id, 
               SYSDATE, 
               in_user_id, 
               SYSDATE, 
               challan_id
        FROM ap_delivery_challan_transfer
        WHERE challan_id = in_dc_id
        AND branch_id = in_branch_id;
        
        
        UPDATE inv_delivery_challans
        SET gl_voucher_id = v_id
        WHERE challan_id = in_dc_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END; 
    
    
    /*
     -- This voucher will be generated When sale invoice Save.  AR
    */
    
    -- voucher type --  JVR
    -- module -- AR
    -- receipt type -- 07
    -- receipt from -- 01
    -- receipt from id -- cust id
    
    PROCEDURE ar_invoice_transfer (
        in_inv_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        l_cnt1     NUMBER;
        l_out_error_code VARCHAR2(50);
        l_out_error_text VARCHAR2(200);
        l_cnt2     NUMBER;
        l_cnt3     NUMBER;
        l_ogp_id   NUMBER;
    BEGIN
        IF in_gl_v_id IS NULL THEN
            
            SELECT gl_voucher_id_s.NEXTVAL
            INTO v_id
            FROM dual;

            SELECT TRUNC(invoice_date),
                   sales_ogp_id
            INTO acc_date,
                 l_ogp_id
            FROM inv_sales_invoices
            WHERE sales_invoice_id = in_inv_id;


            v_no:=get_voucher_no(acc_date,'JVR',company,branch);
            
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                posted_by, 
                posting_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id, 
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'JVR',
                   v_no,
                   acc_date, 
                   'Entry Against Sale Invoice# '|| si.sales_invoice_id, 
                   si.created_by,
                   si.creation_date, 
                   si.last_updated_by, 
                   SYSDATE,
                   'APPROVED', 
                   234, 
                   SYSDATE, 
                   NULL, 
                   NULL,
                   'AR', 
                   'SALE_INVOICE', 
                   si.sales_invoice_id, 
                   company, 
                   branch, 
                   si.invoice_no, 
                   '07', 
                   si.customer_id , 
                   '01', 
                   234, 
                   si.invoice_date
            FROM inv_sales_invoices si, 
                 ar_customers c
            WHERE si.customer_id = c.customer_id 
            AND si.sales_invoice_id = in_inv_id;
        ELSE
            v_id:= in_gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit, 
               credit,
               naration, 
               in_user_id, 
               SYSDATE, 
               in_user_id, 
               SYSDATE, 
               sales_invoice_id
        FROM ar_invoice_transfer_v
        WHERE sales_invoice_id = in_inv_id
        AND branch_id = branch;
       
     
        UPDATE inv_sales_invoices 
        SET gl_voucher_id = v_id 
        WHERE sales_invoice_id = in_inv_id;
        
        UPDATE inv_sales_ogps
        SET out = 'Y',
            out_date = SYSDATE,
            out_by = in_user_id,
            ogp_status = 'OUT'
        WHERE sales_ogp_id = l_ogp_id;
        
        SELECT COUNT(*)
        INTO l_cnt1
        FROM ar_invoice_security_trn_v
        WHERE sales_invoice_id = in_inv_id;
        
        
        IF l_cnt1 > 0 THEN
            acc_supp.ar_invoice_security_deposite (
                in_inv_id        => in_inv_id,
                in_user_id       => in_user_id,
                in_gl_v_id       => null,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_out_error_code,
                out_error_text   => l_out_error_text
            );
        END IF;
        
        
        SELECT COUNT(*)
        INTO l_cnt2
        FROM ar_invoice_suspense_trn_v
        WHERE sales_invoice_id = in_inv_id;
        
        
        IF l_cnt2 > 0 THEN
            acc_supp.ap_suspense_vr_transfer (
                inv_id           => in_inv_id,
                user_id          => in_user_id,
                gl_v_id          => null,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_out_error_code,
                out_error_text   => l_out_error_text
            );
        END IF;
        
        
        SELECT COUNT(*)
        INTO l_cnt3
        FROM ar_invoice_lpg_transcost_v
        WHERE sales_invoice_id = in_inv_id;
        
        
        IF l_cnt3 > 0 THEN
            acc_supp.ap_lpg_transport_transfer (
                inv_id           => in_inv_id,
                user_id          => in_user_id,
                gl_v_id          => null,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_out_error_code,
                out_error_text   => l_out_error_text
            );
        END IF;
        
        COMMIT;
    
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    /*
    --  voucher will be generated when invoice amount has a security deposite part
    */
    
    PROCEDURE ar_invoice_security_deposite (
        in_inv_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    ) IS
        company    NUMBER := in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
    BEGIN
        IF in_gl_v_id IS NULL THEN
            
            SELECT gl_voucher_id_s.NEXTVAL
            INTO v_id
            FROM dual;

            SELECT TRUNC(invoice_date) 
            INTO acc_date
            FROM inv_sales_invoices
            WHERE sales_invoice_id = in_inv_id;


            v_no:=get_voucher_no(acc_date,'JVR',company,branch);
            
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                posted_by, 
                posting_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id, 
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date
            )
            SELECT v_id, 
                   'JVR',
                   v_no,
                   acc_date, 
                   'Entry Against Sale Invoice# '|| si.sales_invoice_id, 
                   si.created_by,
                   si.creation_date, 
                   si.last_updated_by, 
                   SYSDATE,
                   'APPROVED', 
                   NULL, 
                   NULL, 
                   NULL, 
                   NULL,
                   'AR', 
                   'SECURITY_DEPOSITE', 
                   si.sales_invoice_id, 
                   company, 
                   branch , 
                   si.invoice_no, 
                   '07', 
                   si.customer_id , 
                   '01', 
                   234, 
                   si.invoice_date
            FROM inv_sales_invoices si, 
                 ar_customers c
            WHERE si.customer_id = c.customer_id 
            AND si.sales_invoice_id = in_inv_id;
        ELSE
            v_id:= in_gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit, 
               credit,
               narration, 
               in_user_id, 
               SYSDATE, 
               in_user_id, 
               SYSDATE, 
               sales_invoice_id
        FROM ar_invoice_security_trn_v
        WHERE sales_invoice_id = in_inv_id
        AND branch_id = branch;
        
        UPDATE inv_sales_invoices 
        SET gl_security_voucher_id = v_id 
        WHERE sales_invoice_id = in_inv_id;

        COMMIT;
    
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    /*
    -- Auto voucher generation during AR Receipt           AR
    */
    
    
    PROCEDURE ar_cheque_transfer (
        rec_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_type     VARCHAR2(10);
        i          NUMBER;
    BEGIN
        --i := 1/0;
      
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;

            SELECT DECODE (accounted_date, null, receipt_date, accounted_date),
                   in_company_id, 
                   DECODE (payment_mode, 'CASH', 'CRV', 'BRV')
            INTO acc_date,
                 company, 
                 v_type
            FROM ar_receipts
            WHERE receipt_id = rec_id;

            v_no:=get_voucher_no (acc_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;

        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no
            )
            SELECT v_id, 
                   DECODE (r.payment_mode, 'CASH', 'CRV', 'BRV'), v_no,
                   TRUNC(acc_date) , 
                   r.remarks, 
                   batchid, 
                   r.created_by, 
                   r.creation_date,
                   r.last_updated_by, 
                   r.last_update_date, 
                   'PREPARED',
                   NULL, 
                   NULL,
                   'AR',
                   'RECEIPT', 
                   r.receipt_id, 
                   company, 
                   branch, 
                   r.doc_no
            FROM ar_receipts r    
            WHERE r.receipt_id = rec_id;
        END IF;
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE, 
               receipt_id
        FROM ar_cheque_transfer_v
        WHERE receipt_id = rec_id
        AND branch_id = in_branch_id;

        UPDATE ar_receipts
        SET    gl_voucher_id=v_id
        WHERE  receipt_id = rec_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    /*
    -- During DO Approval Advance Payment Voucher will be generated
    */
   
    -- voucher type --  BRV
    -- module -- AR
    -- receipt type -- 06
    -- receipt from -- 01
    -- receipt from id -- cust id
    
    PROCEDURE ar_do_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_type     VARCHAR2(10);
        i          NUMBER;
        l_amount   NUMBER;
        l_receivable_account_id NUMBER;
        l_cust_id  NUMBER;
        l_code VARCHAR2(50);
        l_text VARCHAR2(500);
        l_cnt NUMBER;
    BEGIN
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;

            SELECT approved_date,
                   in_company_id, 
                   'BRV'
            INTO acc_date,
                 company, 
                 v_type
            FROM inv_sales_orders
            WHERE sales_order_id = do_id;

            v_no:=get_voucher_no (acc_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;

        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'BRV', 
                   v_no, 
                   SYSDATE, 
                   'Entry Against DO# '|| r.po_no, 
                   batchid, 
                   user_id, 
                   SYSDATE,
                   NULL, 
                   NULL, 
                   'APPROVED',
                   user_id, 
                   SYSDATE,
                   'AR',
                   'DO APPROVE', 
                   r.sales_order_id, 
                   company, 
                   branch, 
                   r.po_no , 
                   '06' , 
                   r.customer_id , 
                   '01' , 
                   user_id , 
                   SYSDATE
            FROM inv_sales_orders r    
            WHERE r.sales_order_id = do_id;
        END IF;
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               NULL, 
               NULL, 
               sales_order_id
        FROM ar_do_transfer_v
        WHERE sales_order_id = do_id
        AND branch_id = in_branch_id;

        UPDATE inv_sales_orders
        SET    gl_voucher_id = v_id
        WHERE  sales_order_id = do_id;
        
        SELECT SUM(credit) , MAX(receiveable_account_id)
        INTO l_amount , l_receivable_account_id
        FROM ar_do_transfer_v
        WHERE sales_order_id = do_id
        AND debit = 0
        AND branch_id = in_branch_id;
        
        SELECT customer_id
        INTO l_cust_id
        FROM inv_sales_orders
        WHERE sales_order_id = do_id;
        
        UPDATE ar_customers_detail
        SET opening_balance = nvl(opening_balance,0) + NVL(l_amount,0)
        WHERE customer_id  = l_cust_id
        AND branch_id = in_branch_id;
        
        gbl_supp.send_sms_during_do (
            in_do_id   => do_id
        );
        
        COMMIT;
       
        SELECT NVL(COUNT(1),0)
        INTO l_cnt
        FROM ar_do_bank_charge
        WHERE sales_order_id = do_id;
        
        IF l_cnt > 0 THEN
        
            acc_supp.ar_do_bank_charge_trn (
                do_id            => do_id,
                user_id          => user_id,
                gl_v_id          => gl_v_id,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_code,
                out_error_text   => l_text
            );
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    PROCEDURE ar_do_bank_charge_trn (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_type     VARCHAR2(10);
        i          NUMBER;
        l_amount   NUMBER;
        l_receivable_account_id NUMBER;
        l_cust_id  NUMBER;
    BEGIN
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;

            SELECT approved_date,
                   in_company_id, 
                   'BPV'
            INTO acc_date,
                 company, 
                 v_type
            FROM inv_sales_orders
            WHERE sales_order_id = do_id;

            v_no:=get_voucher_no (acc_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;

        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'BPV', 
                   v_no, 
                   SYSDATE, 
                   'Entry Against DO for Bank Charge# '|| r.po_no, 
                   batchid, 
                   user_id, 
                   SYSDATE,
                   NULL, 
                   NULL, 
                   'APPROVED',
                   user_id, 
                   SYSDATE,
                   'AR',
                   'DO APPROVE', 
                   r.sales_order_id, 
                   company, 
                   branch, 
                   r.po_no , 
                   '06' , 
                   r.customer_id , 
                   '01' , 
                   user_id , 
                   SYSDATE
            FROM inv_sales_orders r    
            WHERE r.sales_order_id = do_id;
        END IF;
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               NULL, 
               NULL, 
               sales_order_id
        FROM ar_do_bank_charge
        WHERE sales_order_id = do_id
        AND branch_id = in_branch_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
  
    
    FUNCTION get_costing_exchange_rate (
        in_po_id         IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT exch_rate
        FROM imp_ccns
        WHERE po_id = in_po_id;
        l_exchange_rate NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_exchange_rate;
        CLOSE c1;
        RETURN l_exchange_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_po_exchange_rate (
        in_po_id         IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT exch_rate
        FROM performa_inv_master
        WHERE po_no = in_po_id;
        l_exch_rate NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_exch_rate;
        CLOSE c1;
        RETURN l_exch_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION po_exch_rate_from_inv (
        in_invoice_id       IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT po_exch_rate
        FROM (
            SELECT po_exch_rate
            FROM ap_invoice_lines
            WHERE invoice_id = in_invoice_id
        )
        WHERE ROWNUM < 2 ;
        l_po_exch_rate NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_po_exch_rate;
        CLOSE c1;
        RETURN l_po_exch_rate;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is for voucher creating 
    */
    
    FUNCTION get_voucher_no (
        v_date           IN     DATE, 
        v_type           IN     VARCHAR2, 
        p_company               NUMBER, 
        p_branch                VARCHAR2
    ) RETURN NUMBER
    IS
        v_no   NUMBER;
    BEGIN
        SELECT NVL (MAX (gv.voucher_no), 0) + 1
        INTO v_no
        FROM gl_vouchers gv
        WHERE gv.voucher_date BETWEEN TRUNC (v_date, 'Month') AND LAST_DAY (v_date)
        AND gv.voucher_type = v_type
        AND gv.COMPANY_ID = p_company
        AND gv.BRANCH_ID = p_branch;

        RETURN v_no;
    END;
    
    /*
    -- This function is for checking delivery challan export or local type.
      Y = Export 
      N = Local
    */
    
    FUNCTION check_export_in_dc (
        in_dc_id         IN     NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT chk_export
        FROM inv_delivery_challans
        WHERE challan_id = in_dc_id;
        l_chk_export VARCHAR2(20);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk_export;
        CLOSE c1;
        
        RETURN l_chk_export;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
     -- This function is for local or foreign gl account id of item
    */
    
    FUNCTION get_invoice_account_id (
        in_dc_id         IN     NUMBER,
        in_item_id       IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT CASE 
                   WHEN check_export_in_dc (
                            in_dc_id         =>       in_dc_id
                        ) = 'N' THEN gl_loc_sal_acc_id
                   ELSE gl_for_sal_acc_id
                END account_id
        FROM inv_items         
        WHERE item_id = in_item_id;
        
        l_account_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_account_id;
        CLOSE c1;
        
        RETURN l_account_id;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION get_trial_balance (
        in_pnl_mst_id    IN     NUMBER,
        in_month_year    IN     VARCHAR2,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER
    IS
        CURSOR trial_balance
        IS
        SELECT SUM(NVL(balance,0))
        FROM gl_trial_v
        WHERE record_level = in_record_level
        AND acc_id IN ( 
                        SELECT coa_level5_id
                        FROM gl_profit_loss_dtl 
                        WHERE pnl_mst_id = in_pnl_mst_id
                      )
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND TO_CHAR(voucher_date, 'MON-RRRR') = in_month_year
        AND status = 'APPROVED';
        
        l_balance NUMBER;
    BEGIN
        OPEN trial_balance;
            FETCH trial_balance INTO l_balance;
        CLOSE trial_balance;
        
        RETURN l_balance;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_fiscal_year_start_date (
        in_to_date       IN     DATE
    ) RETURN DATE
    IS
        CURSOR c1
        IS
        SELECT start_date
        FROM gl_fiscal_year
        WHERE in_to_date BETWEEN start_date AND end_date;
        
        l_fiscal_year_end_date DATE;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_fiscal_year_end_date;
        CLOSE c1;
        
       -- IF in_to_date >= curr_fiscal_year_last_date THEN
            RETURN l_fiscal_year_end_date;
      --  ELSE
       --     RETURN NULL;
      --  END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
        
    FUNCTION get_yearly_trial_balance (
        in_pnl_mst_id    IN     NUMBER,
        in_end_date      IN     DATE,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER
    IS
        CURSOR fiscal_year
        IS
        SELECT start_date
        FROM gl_fiscal_year
        WHERE end_date = in_end_date;
        
        l_balance NUMBER;
        l_start_date DATE;
    BEGIN
    
        OPEN fiscal_year;
            FETCH fiscal_year INTO l_start_date; 
        CLOSE fiscal_year;
    
        SELECT SUM(NVL(balance,0)) 
        INTO l_balance
        FROM gl_trial_v
        WHERE record_level = in_record_level
        AND acc_id IN ( 
                        SELECT coa_level5_id
                        FROM gl_profit_loss_dtl 
                        WHERE pnl_mst_id = in_pnl_mst_id
                      )
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND voucher_date BETWEEN l_start_date AND TRUNC(SYSDATE,'MM')-1
        AND status = 'APPROVED';
        
        IF in_end_date < curr_fiscal_year_last_date THEN
            RETURN 0;
        ELSE
            RETURN l_balance;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE ins_gl_profit_loss_data (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        CURSOR profit_loss_qty
        IS
        SELECT lev1.name lev1,
               lev3.name lev3,
               lev3.id lev3_id,
               TO_CHAR(d.fiscal_year) fiscal_year,
               d.qty,
               m.pnl_mst_id,
               d.fiscal_year year_n,
               0 month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               0 cfy_qty
        FROM gl_profit_loss_mst m,
             gl_profit_loss_setup lev1,
             gl_profit_loss_setup lev2,
             gl_profit_loss_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty
             FROM gl_profit_loss_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id = NVL(in_branch_id,m.branch_id)
        AND level2_setup_id IN (101,102) 
        UNION ALL
        SELECT lev1.name lev1,
               lev3.name lev3,
               lev3.id lev3_id,
               month||' - '||year,
               CASE 
                   WHEN level2_setup_id = 101 THEN sales_supp.get_bulk_sales_qty(this_year.month||'-'||this_year.year,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) 
                   WHEN level2_setup_id = 102 THEN sales_supp.get_cylinder_sales_qty(this_year.month||'-'||this_year.year,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END qty,
               m.pnl_mst_id,
               year year_n,
               month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               CASE
                   WHEN lev3.id = 1001 then sales_supp.get_bulk_sales_cfy (
                                                in_to_date     => in_end_date,
                                                in_company_id  => in_company_id,
                                                in_branch_id   => in_branch_id
                                            )
                   WHEN lev3.id = 1002 then sales_supp.get_cylinder_sales_cfy (
                                                in_to_date     => in_end_date,
                                                in_company_id  => in_company_id,
                                                in_branch_id   => in_branch_id
                                            )
               END cfy_qty
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_profit_loss_mst m,
            gl_profit_loss_setup lev1,
            gl_profit_loss_setup lev2,
            gl_profit_loss_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102)
        ORDER BY year_n, month_n;

        CURSOR profit_loss_amt
        IS
        SELECT lev1.name lev1,
               lev3.name lev3,
               TO_CHAR(d.fiscal_year) fiscal_year,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amount,
               0 cfy_amt,
               m.pnl_mst_id,
               d.fiscal_year year_n,
               0 month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id
        FROM gl_profit_loss_mst m,
             gl_profit_loss_setup lev1,
             gl_profit_loss_setup lev2,
             gl_profit_loss_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty
             FROM gl_profit_loss_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id = NVL(in_branch_id,m.branch_id)
        UNION ALL
        SELECT lev1.name lev1,
               lev3.name lev3,
               month||' - '||year,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) 
               END amount,
               --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount ,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_yearly_trial_balance ( m.pnl_mst_id,in_end_date, 5, in_company_id, in_branch_id)
                   ELSE acc_supp.get_yearly_trial_balance ( m.pnl_mst_id,in_end_date, 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END cfy_amt,
               --acc_supp.get_yearly_trial_balance ( m.pnl_mst_id,in_end_date, 5, in_company_id, in_branch_id) cfy_amt,
               m.pnl_mst_id,
               TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
               month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_profit_loss_mst m,
            gl_profit_loss_setup lev1,
            gl_profit_loss_setup lev2,
            gl_profit_loss_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        ORDER BY year_n, month_n;
        
        CURSOR profit_loss_amt_sum
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR gross_profit
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        
        CURSOR gross_profit_pct
        IS
        SELECT a.total_fiscal_year,
               a.total_year_n,
               a.total_month_n,
               ROUND(((a.total_amount / NULLIF(b.total_amount,0)) *100),2) gross_pct
        FROM (
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ) a,
        (
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n) b
        WHERE a.total_fiscal_year = b.total_fiscal_year
        ORDER BY 2,3;
        
        CURSOR net_sales
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR profit_b4_interest
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id NOT IN (401,402,501,502,601,801)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id NOT IN (401,402,501,502,601,801)
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;        
        
        CURSOR profit_b4_dep_income_tx
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id NOT IN (501,502,601)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id NOT IN (501,502,601)
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR profit_b4_income_tx
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id <> 601
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level2_setup_id <> 601
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
    BEGIN

        FOR i IN profit_loss_qty LOOP
            INSERT INTO gl_profit_loss_qty  (
                lev1, 
                lev3, 
                lev3_id, 
                fiscal_year, 
                qty, 
                cfy_qty,
                pnl_mst_id, 
                year_n, 
                month_n, 
                level1_serial, 
                level2_serial, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                i.lev1, 
                i.lev3, 
                i.lev3_id, 
                i.fiscal_year, 
                i.qty, 
                i.cfy_qty,
                i.pnl_mst_id, 
                i.year_n, 
                i.month_n, 
                i.level1_serial, 
                i.level2_serial, 
                null, 
                null, 
                in_company_id, 
                in_branch_id
            );
            
        END LOOP;
        
        COMMIT;
        
        FOR j IN profit_loss_amt LOOP
            INSERT INTO gl_profit_loss_amt (
                lev1, 
                lev3, 
                fiscal_year, 
                amount, 
                cfy_amt,
                pnl_mst_id, 
                year_n, 
                month_n, 
                level1_serial, 
                level2_serial, 
                from_date, 
                to_date, 
                company_id, 
                branch_id,
                signed_operator,
                lev3_id
            )
            VALUES (
                j.lev1, 
                j.lev3, 
                j.fiscal_year, 
                j.amount,
                j.cfy_amt, 
                j.pnl_mst_id, 
                j.year_n, 
                j.month_n, 
                j.level1_serial, 
                j.level2_serial, 
                null,
                null,
                in_company_id, 
                in_branch_id,
                j.signed_operator,
                j.level3_setup_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR k IN profit_loss_amt_sum LOOP
            INSERT INTO gl_profit_loss_amt_sum ( 
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                k.total_fiscal_year, 
                k.total_year_n, 
                k.total_month_n, 
                k.total_amount, 
                null,
                null,
                in_company_id, 
                in_branch_id
            );
            
        END LOOP;
        
        COMMIT;
        
        FOR m IN gross_profit LOOP
            INSERT INTO gl_profit_loss_gross_profit (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                m.total_fiscal_year, 
                m.total_year_n, 
                m.total_month_n, 
                m.total_amount,         
                NULL,
                NULL,
                in_company_id,
                in_branch_id
            );
            
        END LOOP;
        COMMIT;
        
        FOR n IN gross_profit_pct LOOP
            INSERT INTO gl_pnl_gross_profit_pct (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                gross_pct, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                n.total_fiscal_year, 
                n.total_year_n, 
                n.total_month_n, 
                n.gross_pct, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        COMMIT;
        
        FOR x IN net_sales LOOP
            INSERT INTO gl_profit_loss_net_sales (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                x.total_fiscal_year, 
                x.total_year_n, 
                x.total_month_n, 
                x.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR a IN profit_b4_interest LOOP
            INSERT INTO gl_profit_b4_interest (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                a.total_fiscal_year, 
                a.total_year_n, 
                a.total_month_n, 
                a.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR y IN profit_b4_dep_income_tx LOOP
            INSERT INTO gl_profit_b4_dep_income_tx (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                y.total_fiscal_year, 
                y.total_year_n, 
                y.total_month_n, 
                y.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR z IN profit_b4_income_tx LOOP
            INSERT INTO gl_profit_b4_income_tx (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                z.total_fiscal_year, 
                z.total_year_n, 
                z.total_month_n, 
                z.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
        -- This procedure is added in scheduler for getting profit and loss data.
           For making the report faster.
    */
    
    PROCEDURE populate_gl_profit_loss
    IS
        CURSOR branch
        IS
        SELECT company_no,
               branch_id
        FROM sys_branches
        WHERE active = 'Y';
        
        CURSOR c2 
        IS
        SELECT MIN(start_date),
               MAX(end_date)
        FROM gl_fiscal_year;
        
        l_start_date DATE;
        l_end_date DATE;
    BEGIN
    
        DELETE FROM gl_profit_loss_qty;
        DELETE FROM gl_profit_loss_amt;
        DELETE FROM gl_profit_loss_amt_sum;
        DELETE FROM gl_profit_loss_gross_profit;
        DELETE FROM gl_pnl_gross_profit_pct;
        DELETE FROM gl_profit_loss_net_sales;
        DELETE FROM gl_profit_b4_dep_income_tx;
        DELETE FROM gl_profit_b4_income_tx;
        DELETE FROM gl_profit_b4_interest;
        
        COMMIT;
        
        OPEN c2;
            FETCH c2 INTO l_start_date, l_end_date;
        CLOSE c2;
        
        FOR m IN branch LOOP
            acc_supp.ins_gl_profit_loss_data (
                in_start_date    => l_start_date,
                in_end_date      => l_end_date,
                in_company_id    => m.company_no,
                in_branch_id     => m.branch_id
            );
        END LOOP;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION get_net_sales_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER := 0;
    BEGIN
        --IF in_end_date < curr_fiscal_year_last_date THEN
         --   RETURN 0;
        --ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_loss_net_sales
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        --END IF;     
        
        RETURN l_amt;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_gross_sales_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER := 0;
    BEGIN
        --IF in_end_date < curr_fiscal_year_last_date THEN
          --  RETURN 0;
        --ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_loss_gross_profit
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        --END IF;     
        
        RETURN l_amt;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_profit_b4_interest_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER;
    BEGIN
        --IF in_end_date < curr_fiscal_year_last_date THEN
         --   RETURN 0;
       -- ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_b4_interest
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        --END IF;     
        
        RETURN l_amt;
    
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_profit_b4_dep_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER;
    BEGIN
        --IF in_end_date < curr_fiscal_year_last_date THEN
        --    RETURN 0;
       -- ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_b4_dep_income_tx
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
       -- END IF;     
        
        RETURN l_amt;
    
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_profit_b4_inctx_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER;
    BEGIN
       -- IF in_end_date < curr_fiscal_year_last_date THEN
      --      RETURN 0;
       -- ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_b4_income_tx
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
       -- END IF;     
        
        RETURN l_amt;
    
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_profit_after_inctx_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        l_amt NUMBER;
    BEGIN
        --IF in_end_date < curr_fiscal_year_last_date THEN
        --    RETURN 0;
       -- ELSE
            SELECT SUM(NVL(total_amount,0))
            INTO l_amt
            FROM gl_profit_loss_amt_sum
            WHERE INSTR(total_fiscal_year, '-') > 0
            AND company_id = NVL(in_company_id,company_id)
            AND branch_id = NVL(in_branch_id,branch_id)
            AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        --END IF;     
        
        RETURN l_amt;
    
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_net_sales (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_loss_net_sales
        WHERE company_id = NVL(in_company_id,company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= TO_NUMBER(TO_CHAR(in_start_date,'rrrr'))+1
        AND total_year_n <= TO_NUMBER(TO_CHAR(in_end_date,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        
        l_amt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_gross_profit (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_loss_gross_profit
        WHERE company_id = NVL(in_company_id,company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= TO_NUMBER(TO_CHAR(in_start_date,'rrrr'))+1
        AND total_year_n <= TO_NUMBER(TO_CHAR(in_end_date,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        
    l_amt NUMBER;
    
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_profit_before_itd (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_b4_interest
        WHERE company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= to_number(to_char(in_START_DATE,'rrrr'))+1
        AND total_year_n <= to_number(to_char(IN_END_DATE,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        
        l_amt NUMBER;
    
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    
    FUNCTION get_profit_before_di (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_b4_dep_income_tx
        WHERE company_id = NVL(in_company_id,company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= to_number(to_char(in_start_date,'rrrr'))+1
        AND total_year_n <= to_number(to_char(in_end_date,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        
        l_amt NUMBER;
    
     BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_profit_before_it (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_b4_income_tx
        WHERE company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= to_number(to_char(in_start_DATE,'rrrr'))+1
        AND total_year_n <= to_number(to_char(in_end_DATE,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
        
        l_amt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_profit_after_it (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(total_amount) total_amount
        FROM gl_profit_loss_amt_sum
        WHERE company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id,branch_id)
        AND total_year_n >= to_number(to_char(in_start_DATE,'rrrr'))+1
        AND total_year_n <= to_number(to_char(in_end_DATE,'rrrr'))
        AND total_fiscal_year <> TO_CHAR(SYSDATE, 'MON - RRRR');
  
        l_amt NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amt;
        CLOSE c1;
        
        RETURN l_amt;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION ebitda_usd_exchange_rate 
    RETURN NUMBER
    IS
        l_rate NUMBER;
    BEGIN
        l_rate := 102;
        RETURN l_rate;
    END;
    
    FUNCTION get_ebitda_mt_qty (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(qty_mt) qty_mt
        FROM (
            SELECT ROUND(SUM(NVL(qty_kgs,0)) / 1000) qty_mt
            FROM mapics_sales s,
                 inv_items i
            WHERE s.invoice_date BETWEEN in_start_date AND in_end_date
            AND i.item_id IN (1,8,9,10,11,16,17,18,19)
            AND s.item_code = SUBSTR(i.old_item_code,3,5)
            AND s.invoice_date >= '01-JUL-2023'
            AND s.invoice_date <= TRUNC(SYSDATE, 'MM') -1
            UNION ALL
            SELECT ROUND(SUM(CASE 
                       WHEN m.level2_setup_id = 101 THEN d.qty / 1000
                       ELSE d.qty * m.capacity / 1000
                   END)) qty_mt
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6)
        );
        l_mt_qty NUMBER;
    BEGIN
        
        OPEN c1;
            FETCH c1 INTO l_mt_qty;
        CLOSE c1;
        
        RETURN NULLIF(l_mt_qty,0);
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
  
--############################################********************************************  
    
   PROCEDURE ins_gl_ebitda_data (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        CURSOR ebitda_qty
        IS
        SELECT sl,
               item_desc,
               item_id,
               sales_month,
               year_n,
               sales_year,
               item_capacity,
               qty_pcs,
               qty_mt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev3.name item_desc,
               lev3.id item_id,
               0 sales_month,
               d.fiscal_year year_n,
               d.period sales_year,
               m.capacity item_capacity,
               CASE 
                   WHEN m.level2_setup_id = 101 THEN 0
                   ELSE d.qty
               END qty_pcs,
               CASE 
                   WHEN m.level2_setup_id = 101 THEN d.qty / 1000
                   ELSE d.qty * m.capacity / 1000
               END qty_mt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                        -- current month
        SELECT 1 sl,
               lev3.name item_desc,
               lev3.id item_id,
               month_n sales_month,
               CASE 
                   WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                   WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
               END year_n,
               month||' - '||year_n sales_year,
               m.capacity item_capacity,
               sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
               sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                                        -- CFY
        SELECT 2 sl,
               item_desc,
               item_id,
               0,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(qty_pcs) qty_pcs,
               SUM(qty_mt) qty_mt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
                   sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 year_n,
                 TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id
        UNION ALL                                         --- YTD
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(qty_pcs) qty_pcs,
               SUM(qty_mt) qty_mt,
               pnl_mst_id
        FROM (
            SELECT 3 sl,                                  
                   item_desc,
                   item_id,
                   0,
                   0,
                   0 sales_year,
                   item_capacity,
                   SUM(qty_pcs) qty_pcs,
                   SUM(qty_mt) qty_mt,
                   pnl_mst_id
            FROM (
                SELECT 3 sl,
                       lev3.name item_desc,
                       lev3.id item_id,
                       month_n sales_month,
                       year_n,
                       month||' - '||year_n sales_year,
                       m.capacity item_capacity,
                       sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
                       sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
                       m.pnl_mst_id
                FROM(
                    SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                           TO_CHAR(D,'MON') AS MONTH,
                           EXTRACT(YEAR FROM d) AS YEAR_N
                    FROM (
                        SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                        FROM DUAL
                        CONNECT BY
                        ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                    )
                    WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                    ) this_year,
                    gl_ebitda_mst m,
                    gl_ebitda_setup lev1,
                    gl_ebitda_setup lev2,
                    gl_ebitda_setup lev3
                WHERE m.level1_setup_id = lev1.id
                AND m.level2_setup_id = lev2.id
                AND m.level3_setup_id = lev3.id     
                AND m.company_id = NVL(in_company_id, m.company_id)
                AND m.branch_id = NVL(in_branch_id, m.branch_id)
                AND in_end_date >= curr_fiscal_year_last_date
                AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
            )
            GROUP BY sl,
                     item_desc,
                     item_id,
                     0,
                     0,
                     0,
                     item_capacity,
                     pnl_mst_id
            UNION ALL
            SELECT 3 sl,                               -- 2016-2023
                   lev3.name item_desc,
                   lev3.id item_id,
                   0 sales_month,
                   0 year_n,
                   0 sales_year,
                   m.capacity item_capacity,
                   CASE 
                       WHEN m.level2_setup_id = 101 THEN 0
                       ELSE d.qty
                   END qty_pcs,
                   CASE    WHEN 
                    m.level2_setup_id = 101 THEN d.qty / 1000
                       ELSE d.qty * m.capacity / 1000
                   END qty_mt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 0,
                 TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id
        )
        ORDER BY sl,year_n,sales_month,item_capacity DESC NULLS LAST;
        --------------------------------------------------------------------------------
        CURSOR ebitda_amt 
        IS
        SELECT sl,
               item_desc,
               item_id,
               sales_month,
               year_n,
               sales_year,
               item_capacity,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev3.name item_desc,
               lev3.id item_id,
               0 sales_month,
               d.fiscal_year year_n,
               d.period sales_year,
               m.capacity item_capacity,
               -1 * d.amount amt_bdt,
               -1 * d.amount / ROUND(NULLIF(d.qty,0) * m.capacity / 1000) bdt_pmt,
               -1 * d.amount / ROUND(NULLIF(d.qty,0) * m.capacity / 1000) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               m.pnl_mst_id,
               m.signed_operator
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                        -- current month
        SELECT 1 sl,
               lev3.name item_desc,
               lev3.id item_id,
               month_n sales_month,
               CASE 
                   WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                   WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
               END year_n,
               month||' - '||year_n sales_year,
               m.capacity item_capacity,
               sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
               sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
               sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               m.pnl_mst_id,
               m.signed_operator 
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                                        -- CFY
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1,item_id) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1,item_id) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM (
            SELECT 2 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator 
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 year_n,
                 TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id,
                 signed_operator
        UNION ALL                                         --- YTD  (FAISAL)
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1, item_id) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1, item_id) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM (
            SELECT 3 sl,                               
                   lev3.name item_desc,
                   lev3.id item_id,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   m.capacity item_capacity,
                   -1 * d.amount amt_bdt,
                   -1 * d.amount / (NULLIF(d.qty,0) * m.capacity / 1000) bdt_pmt,
                   -1 * d.amount / (NULLIF(d.qty,0) * m.capacity / 1000) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
            UNION ALL                                        
            SELECT 3 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator 
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 0,
                 TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id,
                 signed_operator
        )
        ORDER BY sl,year_n,sales_month,item_capacity DESC NULLS LAST;
        
        -----------------------------------------------------------------------------
        
        CURSOR ebitda_deduction_heads
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2001 AND 3009
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2001 AND 3009
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 3009
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2001 AND 3009
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 3009
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_tolling_revenue
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1003
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 1003
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1003
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1003
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1003
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_other_income
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 7001 AND 7007
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 7001 AND 7007
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 7001 AND 7007
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 7001 AND 7007
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 7001 AND 7007
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_vat
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1004
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 1004
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1004
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1004
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1004
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_sales_comm
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1005
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 1005
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1005
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1005
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1005
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_sales_discnt
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1007
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 1007
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1007
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1007
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 1007
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_rm_cost
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 2001
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 2001
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 2001
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 2001
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 2001
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_foh_cost
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2002 AND 2015
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2002 AND 2015
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2002 AND 2015
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2002 AND 2015
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2002 AND 2015
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_cogs
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2001 AND 2015
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2001 AND 2015
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 2015
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2001 AND 2015
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 2015
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_sell_admin_oh 
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 3001 AND 3009
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 3001 AND 3009
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 3001 AND 3009
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 3001 AND 3009
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 3001 AND 3009
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        ---------------------------------------------------------------        
        CURSOR ebitda_berc_price
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 8001
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= curr_fiscal_year_last_date
        AND m.level3_setup_id = 8001
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 8001
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 8001
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= curr_fiscal_year_last_date
            AND m.level3_setup_id = 8001
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
    BEGIN
        FOR m IN ebitda_qty LOOP
            INSERT INTO gl_ebitda_qty (
                sl,
                item_desc,
                item_id,
                sales_month,
                year_n,
                sales_year,
                item_capacity,
                qty_pcs,
                qty_mt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                m.sl,
                m.item_desc,
                m.item_id,
                m.sales_month,
                m.year_n,
                m.sales_year,
                m.item_capacity,
                m.qty_pcs,
                m.qty_mt,
                in_company_id,
                in_branch_id,
                m.pnl_mst_id
            );
        END LOOP;
        
        FOR n IN ebitda_amt LOOP
            INSERT INTO gl_ebitda_amt (
                sl,
                item_desc,
                item_id,
                sales_month,
                year_n,
                sales_year,
                item_capacity,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id,
                signed_operator
            )
            VALUES (
                n.sl,
                n.item_desc,
                n.item_id,
                n.sales_month,
                n.year_n,
                n.sales_year,
                n.item_capacity,
                n.amt_bdt,
                n.bdt_pmt,
                n.usd_pmt,
                in_company_id,
                in_branch_id,
                n.pnl_mst_id,
                n.signed_operator
            );
        END LOOP;
        
        
        FOR r IN ebitda_deduction_heads LOOP 
            INSERT INTO gl_ebitda_deduction_heads (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                r.sl,
                r.lev1,
                r.lev3,
                r.sales_month,
                r.year_n,
                r.sales_year,
                r.level1_serial,
                r.level2_serial,
                r.signed_operator,
                r.level3_setup_id,
                r.month_n,
                r.amt_bdt,
                r.bdt_pmt,
                r.usd_pmt,
                in_company_id,
                in_branch_id,
                r.pnl_mst_id
            );
            
        END LOOP;
        
        FOR p IN ebitda_tolling_revenue LOOP
            INSERT INTO gl_ebitda_tolling_revenue (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                p.sl,
                p.lev1,
                p.lev3,
                p.sales_month,
                p.year_n,
                p.sales_year,
                p.level1_serial,
                p.level2_serial,
                p.signed_operator,
                p.level3_setup_id,
                p.month_n,
                p.amt_bdt,
                p.bdt_pmt,
                p.usd_pmt,
                in_company_id,
                in_branch_id,
                p.pnl_mst_id
            );
        END LOOP;
        
        FOR q IN ebitda_other_income LOOP
            INSERT INTO gl_ebitda_other_income (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                q.sl,
                q.lev1,
                q.lev3,
                q.sales_month,
                q.year_n,
                q.sales_year,
                q.level1_serial,
                q.level2_serial,
                q.signed_operator,
                q.level3_setup_id,
                q.month_n,
                q.amt_bdt,
                q.bdt_pmt,
                q.usd_pmt,
                in_company_id,
                in_branch_id,
                q.pnl_mst_id
            );
        END LOOP;
        
        FOR a IN ebitda_less_vat LOOP
            INSERT INTO gl_ebitda_less_vat (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                a.sl,
                a.lev1,
                a.lev3,
                a.sales_month,
                a.year_n,
                a.sales_year,
                a.level1_serial,
                a.level2_serial,
                a.signed_operator,
                a.level3_setup_id,
                a.month_n,
                a.amt_bdt,
                a.bdt_pmt,
                a.usd_pmt,
                in_company_id,
                in_branch_id,
                a.pnl_mst_id
            );
        END LOOP;
        
        FOR b IN ebitda_less_sales_comm LOOP
            INSERT INTO gl_ebitda_less_sales_com (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                b.sl,
                b.lev1,
                b.lev3,
                b.sales_month,
                b.year_n,
                b.sales_year,
                b.level1_serial,
                b.level2_serial,
                b.signed_operator,
                b.level3_setup_id,
                b.month_n,
                b.amt_bdt,
                b.bdt_pmt,
                b.usd_pmt,
                in_company_id,
                in_branch_id,
                b.pnl_mst_id
            );
        END LOOP;
        
        
        FOR c IN ebitda_less_sales_discnt LOOP
            INSERT INTO gl_ebitda_less_sales_discnt (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                c.sl,
                c.lev1,
                c.lev3,
                c.sales_month,
                c.year_n,
                c.sales_year,
                c.level1_serial,
                c.level2_serial,
                c.signed_operator,
                c.level3_setup_id,
                c.month_n,
                c.amt_bdt,
                c.bdt_pmt,
                c.usd_pmt,
                in_company_id,
                in_branch_id,
                c.pnl_mst_id
            );
        END LOOP;
        
        FOR d IN ebitda_rm_cost LOOP
            INSERT INTO gl_ebitda_rm_cost (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                d.sl,
                d.lev1,
                d.lev3,
                d.sales_month,
                d.year_n,
                d.sales_year,
                d.level1_serial,
                d.level2_serial,
                d.signed_operator,
                d.level3_setup_id,
                d.month_n,
                d.amt_bdt,
                d.bdt_pmt,
                d.usd_pmt,
                in_company_id,
                in_branch_id,
                d.pnl_mst_id
            );
        END LOOP;
        
        
        
        FOR e IN ebitda_foh_cost LOOP
            INSERT INTO gl_ebitda_foh_cost (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                e.sl,
                e.lev1,
                e.lev3,
                e.sales_month,
                e.year_n,
                e.sales_year,
                e.level1_serial,
                e.level2_serial,
                e.signed_operator,
                e.level3_setup_id,
                e.month_n,
                e.amt_bdt,
                e.bdt_pmt,
                e.usd_pmt,
                in_company_id,
                in_branch_id,
                e.pnl_mst_id
            );
        END LOOP;
        
        FOR f IN ebitda_cogs LOOP
            INSERT INTO gl_ebitda_cogs (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                f.sl,
                f.lev1,
                f.lev3,
                f.sales_month,
                f.year_n,
                f.sales_year,
                f.level1_serial,
                f.level2_serial,
                f.signed_operator,
                f.level3_setup_id,
                f.month_n,
                f.amt_bdt,
                f.bdt_pmt,
                f.usd_pmt,
                in_company_id,
                in_branch_id,
                f.pnl_mst_id
            );
        END LOOP;
        
        FOR g IN ebitda_sell_admin_oh LOOP
            INSERT INTO gl_ebitda_sell_admin_oh (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                g.sl,
                g.lev1,
                g.lev3,
                g.sales_month,
                g.year_n,
                g.sales_year,
                g.level1_serial,
                g.level2_serial,
                g.signed_operator,
                g.level3_setup_id,
                g.month_n,
                g.amt_bdt,
                g.bdt_pmt,
                g.usd_pmt,
                in_company_id,
                in_branch_id,
                g.pnl_mst_id
            );
        END LOOP;
        
        
        FOR h IN ebitda_berc_price LOOP
            INSERT INTO gl_ebitda_berc_price (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                h.sl,
                h.lev1,
                h.lev3,
                h.sales_month,
                h.year_n,
                h.sales_year,
                h.level1_serial,
                h.level2_serial,
                h.signed_operator,
                h.level3_setup_id,
                h.month_n,
                h.amt_bdt,
                h.bdt_pmt,
                h.usd_pmt,
                in_company_id,
                in_branch_id,
                h.pnl_mst_id
            );
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    /*
        -- This procedure is added in scheduler for getting ebitda data.
           For making the report faster.
    */
    
    PROCEDURE populate_gl_ebitda
    IS
        CURSOR branch
        IS
        SELECT company_no,
               branch_id
        FROM sys_branches
        WHERE active = 'Y';
        
        CURSOR c2 
        IS
        SELECT TO_DATE('01-JUL-2017') start_date,
               MAX(end_date)
        FROM gl_fiscal_year;
        
        CURSOR c3 
        IS
        SELECT COUNT(*)
        FROM gl_fiscal_year
        WHERE year_ind = 'P'
        AND status = 1;
        
        l_start_date DATE;
        l_end_date DATE;
        l_cnt NUMBER;
    BEGIN
        
        OPEN c3;
            FETCH c3 INTO l_cnt;
        CLOSE c3;
        
        IF l_cnt > 0 THEN
            ins_ebitda_amt_prev;
            COMMIT;
        END IF;
        
        DELETE FROM gl_ebitda_qty;
        DELETE FROM gl_ebitda_amt;
        DELETE FROM gl_ebitda_deduction_heads;
        DELETE FROM gl_ebitda_tolling_revenue;  
        DELETE FROM gl_ebitda_other_income;      
        DELETE FROM gl_ebitda_less_vat;           
        DELETE FROM gl_ebitda_less_sales_com;      
        DELETE FROM gl_ebitda_less_sales_discnt;  
        DELETE FROM gl_ebitda_rm_cost;        
        DELETE FROM gl_ebitda_foh_cost;         
        DELETE FROM gl_ebitda_cogs;         
        DELETE FROM gl_ebitda_sell_admin_oh;
        DELETE FROM gl_ebitda_berc_price;    
        
        COMMIT;
        
        OPEN c2;
            FETCH c2 INTO l_start_date, l_end_date;
        CLOSE c2;
        
        FOR m IN branch LOOP
            acc_supp.ins_gl_ebitda_data (
                in_start_date    => l_start_date,
                in_end_date      => l_end_date,
                in_company_id    => m.company_no,
                in_branch_id     => m.branch_id
            );
        END LOOP;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
        -- This function is for getting item wise MT qty in EBITDA report.
    */
    
    FUNCTION get_ebitda_mt_qty_itm_wise (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_item_id       IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT ROUND(SUM(qty_mt)) qty_mt
        FROM (
            SELECT SUM(NVL(qty_kgs,0)) / 1000 qty_mt
            FROM mapics_sales s,
                 inv_items i
            WHERE s.invoice_date BETWEEN in_start_date AND in_end_date
            AND i.item_id = CASE 
                                WHEN in_item_id = 1001   THEN 1
                                WHEN in_item_id = 1002.1 THEN 8
                                WHEN in_item_id = 1002.2 THEN 16
                                WHEN in_item_id = 1002.3 THEN 9
                                WHEN in_item_id = 1002.4 THEN 17
                                WHEN in_item_id = 1002.5 THEN 11
                                WHEN in_item_id = 1002.6 THEN 19
                            END
            AND s.item_code = SUBSTR(i.old_item_code,3,5)
            AND s.invoice_date >= '01-JUL-2023'
            AND s.invoice_date <= TRUNC(SYSDATE, 'MM') -1
            UNION ALL
            SELECT SUM(CASE 
                       WHEN m.level2_setup_id = 101 THEN d.qty / 1000
                       ELSE d.qty * m.capacity / 1000
                   END) qty_mt
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.level3_setup_id = in_item_id
        );
        l_mt_qty NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_mt_qty;
        CLOSE c1;
        RETURN NULLIF(l_mt_qty,0);
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    /*
        -- This voucher will be created duing invoice save for suspense account transfer.
    */
    
    PROCEDURE ap_suspense_vr_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
    BEGIN
        IF gl_v_id IS NULL THEN
            
            SELECT gl_voucher_id_s.NEXTVAL
            INTO v_id
            FROM dual;

            SELECT TRUNC(invoice_date) 
            INTO acc_date
            FROM inv_sales_invoices
            WHERE sales_invoice_id = inv_id;


            v_no:=get_voucher_no(acc_date,'JVR',company,branch); 
            
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                posted_by, 
                posting_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id, 
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date
            )
            SELECT v_id, 
                   'JVR',
                   v_no,
                   acc_date, 
                   'Entry of Suspense a/c Against Sale Invoice # '|| si.sales_invoice_id, 
                   133,
                   si.creation_date, 
                   133, 
                   SYSDATE,
                   'APPROVED', 
                   128, 
                   SYSDATE, 
                   NULL, 
                   NULL,
                   'AR', 
                   'SUSPENSE_ACCOUNT', 
                   si.sales_invoice_id, 
                   company, 
                   branch , 
                   si.invoice_no, 
                   '03',                                      
                   si.customer_id , 
                   '01', 
                   234, 
                   si.invoice_date
            FROM inv_sales_invoices si, 
                 ar_customers c
            WHERE si.customer_id = c.customer_id 
            AND si.sales_invoice_id = inv_id;
        ELSE
            v_id:= gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id,
            sales_invoice_item_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit, 
               credit,
               narration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE, 
               sales_invoice_id,
               inv_sales_invoice_items_id
        FROM ar_invoice_suspense_trn_v
        WHERE sales_invoice_id = inv_id
        AND branch_id = branch;
        
        UPDATE inv_sales_invoices 
        SET suspense_voucher_id = v_id 
        WHERE sales_invoice_id = inv_id;

        COMMIT;
    
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    /*
        -- This voucher will be created duing invoice save for LPG transport cost.
    */

    PROCEDURE ap_lpg_transport_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
    BEGIN
        IF gl_v_id IS NULL THEN
            
            SELECT gl_voucher_id_s.NEXTVAL
            INTO v_id
            FROM dual;

            SELECT TRUNC(invoice_date) 
            INTO acc_date
            FROM inv_sales_invoices
            WHERE sales_invoice_id = inv_id;


            v_no:=get_voucher_no(acc_date,'JVR',company,branch); 
            
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                posted_by, 
                posting_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id, 
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date
            )
            SELECT v_id, 
                   'JVR',
                   v_no,
                   acc_date, 
                   'Entry of LPG Transport cost Against Sale Invoice # '|| si.sales_invoice_id, 
                   133,
                   si.creation_date, 
                   133, 
                   SYSDATE,
                   'APPROVED', 
                   128, 
                   SYSDATE, 
                   NULL, 
                   NULL,
                   'AR', 
                   'TRANSPORT_COST', 
                   si.sales_invoice_id, 
                   company, 
                   branch , 
                   si.invoice_no, 
                   '04',                                      
                   si.customer_id , 
                   '01', 
                   234, 
                   si.invoice_date
            FROM inv_sales_invoices si, 
                 ar_customers c
            WHERE si.customer_id = c.customer_id 
            AND si.sales_invoice_id = inv_id;
        ELSE
            v_id:= gl_v_id;
        END IF;

        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit, 
               credit,
               narration, 
               user_id, 
               SYSDATE, 
               user_id, 
               SYSDATE, 
               sales_invoice_id
        FROM ar_invoice_lpg_transcost_v
        WHERE sales_invoice_id = inv_id
        AND branch_id = branch;
        
        UPDATE inv_sales_invoices 
        SET transport_voucher_id = v_id 
        WHERE sales_invoice_id = inv_id;

        COMMIT;
    
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    FUNCTION get_trial_balance_ebitda (
        in_pnl_mst_id    IN     NUMBER,
        in_month_year    IN     VARCHAR2,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER
    IS
        CURSOR trial_balance
        IS
        SELECT SUM(NVL(balance,0))
        FROM gl_trial_v
        WHERE record_level = in_record_level
        AND acc_id IN ( 
                        SELECT coa_level5_id
                        FROM gl_ebitda_dtl 
                        WHERE pnl_mst_id = in_pnl_mst_id
                      )
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND TO_CHAR(voucher_date, 'MON-RRRR') = in_month_year
        AND status = 'APPROVED';
        
        l_balance NUMBER;
    BEGIN
        OPEN trial_balance;
            FETCH trial_balance INTO l_balance;
        CLOSE trial_balance;
        
        RETURN l_balance;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_periodical_start_date (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN DATE
    IS
        l_date DATE;
        l_current_fiscal_year NUMBER;
        l_fiscal_start_date DATE;
        l_first_half NUMBER;
        l_year NUMBER;
    BEGIN
        SELECT fiscal_year, start_date
        INTO l_current_fiscal_year, l_fiscal_start_date
        FROM gl_fiscal_year
        WHERE SYSDATE BETWEEN start_date AND end_date;
        
        IF in_month >= 7 THEN
            l_year := in_year - 1;
        ELSE
            l_year := in_year;
        END IF;
        
        IF in_month = 0 AND in_year > 0 THEN
            l_date := TO_DATE(('01-JUL-'||(in_year-1)),'DD-MON-RRRR') ;
        ELSIF in_month = 0 AND in_year = 0 THEN
            l_date := '01-JUL-2017';
        ELSIF in_month > 0 AND in_year = l_current_fiscal_year THEN
            l_date := TO_DATE(('01-'|| LPAD(in_month,2,'0') || '-'|| l_year),'DD-MM-RRRR') ;
        END IF;
        
        RETURN l_date;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_periodical_end_date (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN DATE
    IS
        l_date DATE;
        l_current_fiscal_year NUMBER;
        l_fiscal_end_date DATE;
        l_first_half NUMBER;
        l_year NUMBER;
    BEGIN
        SELECT fiscal_year, end_date
        INTO l_current_fiscal_year, l_fiscal_end_date
        FROM gl_fiscal_year
        WHERE SYSDATE BETWEEN start_date AND end_date;
        
        IF in_month >= 7 THEN
            l_year := in_year - 1;
        ELSE
            l_year := in_year;
        END IF;
        
        IF in_month = 0 AND in_year > 0 THEN
            l_date := TO_DATE(('30-JUN-'||in_year),'DD-MON-RRRR');
        ELSIF in_month = 0 AND in_year = 0 THEN
            l_date := TRUNC(SYSDATE,'MM')-1; --l_fiscal_end_date;
        ELSIF in_month > 0 AND in_year = l_current_fiscal_year THEN
            l_date := LAST_DAY(TO_DATE(('01-'|| LPAD(in_month,2,'0') || '-'|| l_year),'DD-MM-RRRR')) ;
        END IF;
        
        RETURN l_date;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION get_ebitda_exchange_rate (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN NUMBER
    IS
        l_current_fiscal_year NUMBER;
        l_exch_rate NUMBER;
    BEGIN
        SELECT fiscal_year
        INTO l_current_fiscal_year
        FROM gl_fiscal_year
        WHERE SYSDATE BETWEEN start_date AND end_date;
  
        IF in_year = 0 AND in_month = 0 THEN -- YTD
            SELECT AVG(exch_rate)
            INTO l_exch_rate
            FROM gl_ebitda_exchange_rate
            WHERE start_date >= acc_supp.get_periodical_start_date(in_year,in_month)
            AND end_date <= TRUNC(SYSDATE,'MM')-1;
        ELSIF in_year = l_current_fiscal_year AND in_month = 0 THEN  --CFY
            SELECT AVG(exch_rate)
            INTO l_exch_rate
            FROM gl_ebitda_exchange_rate
            WHERE start_date >= acc_supp.get_periodical_start_date(in_year,in_month)
            AND end_date <= TRUNC(SYSDATE,'MM')-1;
        ELSIF in_year < l_current_fiscal_year AND in_month = 0 THEN  --HISTORICAL DATA
            SELECT exch_rate
            INTO l_exch_rate
            FROM gl_ebitda_exchange_rate
            WHERE start_date = acc_supp.get_periodical_start_date(in_year,in_month)
            AND end_date = acc_supp.get_periodical_end_date(in_year,in_month);
        ELSIF in_year > 0 AND in_month > 0 THEN -- CURRENT MONTHS
            SELECT exch_rate
            INTO l_exch_rate
            FROM gl_ebitda_exchange_rate
            WHERE start_date = acc_supp.get_periodical_start_date(in_year,in_month)
            AND end_date = acc_supp.get_periodical_end_date(in_year,in_month);
        END IF;
        
        RETURN l_exch_rate;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_trial_bal_fourth_lev (
        in_fourth_lev_id IN     NUMBER,
        in_record_level  IN     NUMBER,
        in_as_on_date    IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER
    IS
        CURSOR trial_balance
        IS
        SELECT ABS(SUM(NVL(balance,0)))
        FROM gl_trial_v
        WHERE record_level = in_record_level
        AND acc_id IN ( 
                        SELECT chart_of_account_id
                        FROM gl_chart_of_accounts
                        WHERE parent_control_account_id = in_fourth_lev_id
                      )
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND voucher_date <= in_as_on_date
        AND status = 'APPROVED';
        
        l_balance NUMBER;
    BEGIN
        OPEN trial_balance;
            FETCH trial_balance INTO l_balance;
        CLOSE trial_balance;
        
        RETURN l_balance;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_3rd_lev_desc_frm_4th (
        in_4th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT description
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_4th_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_3rd_lev_code_frm_4th (
        in_4th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT control_account_code
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_4th_lev_code);
        l_code VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_code;
        CLOSE c1;
        RETURN l_code;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_2nd_lev_desc_frm_3rd (
        in_3rd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT description
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_3rd_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_2nd_lev_code_frm_3rd (
        in_3rd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT control_account_code
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_3rd_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_1st_lev_desc_frm_2nd (
        in_2nd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT description
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_2nd_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_1st_lev_code_frm_2nd (
        in_2nd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT control_account_code
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_control_accounts
                                     WHERE control_account_code = in_2nd_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION get_ap_invoice_qty (
        in_grn_item_id      IN     NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(invoice_qty,0))
        FROM ap_invoice_lines
        WHERE grn_item_id = in_grn_item_id;
        l_invoice_qty NUMBER := 0;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_invoice_qty;
        CLOSE c1;
        
        RETURN NVL(l_invoice_qty,0);
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    /*
    -- Auto voucher generation during invoice Matching for Prepayment  --   AP
    */
    
    PROCEDURE ap_invoice_prepayment_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER  :=  in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        v_id       NUMBER;
        v_no       NUMBER;
        chk        NUMBER;
        acc_date   DATE;
        remarks    VARCHAR2(300);
        l_cnt      NUMBER;
    BEGIN
        SELECT TRUNC(accounting_date), 
               i.invoice_amount,
               remarks
        INTO acc_date, 
             chk,
             remarks
        FROM ap_invoices i    
        WHERE invoice_id = inv_id;
        
        SELECT COUNT(*)
        INTO l_cnt 
        FROM ap_invoice_transfer_prepay_v
        WHERE invoice_id = inv_id;
        
        IF l_cnt > 0  THEN
        
            IF gl_v_id IS NULL THEN
                SELECT gl_voucher_id_s.NEXTVAL    
                INTO v_id      
                FROM dual;
                
                v_no := get_voucher_no(acc_date,'JVP',company,branch);
                
                INSERT INTO gl_vouchers (
                    voucher_id, 
                    voucher_type, 
                    voucher_no, 
                    voucher_date,
                    description, 
                    created_by, 
                    creation_date,
                    last_updated_by, 
                    last_updated_date, 
                    status,
                    approved_by, 
                    approval_date, 
                    cheked_by, 
                    checked_date, 
                    module,
                    module_doc, 
                    module_doc_id, 
                    company_id, 
                    branch_id,
                    pay_to_id,
                    paid_to,
                    paid_to_type
                )
                SELECT v_id, 
                       'JVP',
                       v_no,
                       acc_date, 
                       'Entry Aginst Advance to Vendor # '|| si.ap_invoice_no, 
                       si.created_by,
                       si.creation_date, 
                       si.last_updated_by, 
                       si.last_update_date,
                      'APPROVED',
                      si.TRANSFER_ID,
                      si.TRANSFER_DATE,
                      si.CREATED_BY,
                      si.CREATION_DATE,
                      'AP', 
                      'INVOICE-PREPAYMENT', 
                      si.invoice_id, 
                      company, 
                      branch,
                      si.vendor_id,
                      '01',
                      '06'
                FROM ap_invoices si, 
                     inv_vendors c
                WHERE si.vendor_id = c.vendor_id 
                AND si.invoice_id = inv_id;
            ELSE
                v_id:=gl_v_id;
            END IF;

            INSERT INTO gl_voucher_accounts (
                voucher_account_id, 
                voucher_id, 
                account_id, 
                debit, 
                credit,
                naration, 
                created_by, 
                creation_date, 
                last_updated_by,
                last_update_date, 
                reference_id
            )
            SELECT gl_voucher_account_id_s.NEXTVAL, 
                   v_id, 
                   account_id, 
                   debit,
                   credit, 
                   naration, 
                   user_id, 
                   SYSDATE, 
                   user_id, 
                   SYSDATE,
                   invoice_id
            FROM ap_invoice_transfer_prepay_v
            WHERE invoice_id = inv_id;
            
            
            UPDATE ap_invoices
            SET gl_voucher_id = v_id
            WHERE invoice_id = inv_id;
            
            COMMIT;
            
        ELSE
            out_error_code := 'NO DATA';
            out_error_text := 'NO DATA IN VIEW';
        END IF;
        
        --****************** For the expense part
        /*
        acc_supp.ap_invoice_expense_transfer (
            inv_id           => inv_id,
            user_id          => user_id,
            gl_v_id          => gl_v_id,
            in_company_id    => in_company_id,
            in_branch_id     => in_branch_id
        );
        
        COMMIT;
        */
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END ;
    
    /*
    -- This function is for getting 4th level desc of chart of accounts from 5th level 
    */
    
    
    FUNCTION get_4th_lev_desc_frm_5th (
        in_5th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT description
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_chart_of_accounts
                                     WHERE chart_of_account_code = in_5th_lev_code);
        l_desc VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_desc;
        CLOSE c1;
        RETURN l_desc;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is for getting 4th level code of chart of accounts from 5th level 
    */
    
    FUNCTION get_4th_lev_code_frm_5th (
        in_5th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT control_account_code
        FROM gl_control_accounts
        WHERE control_account_id IN (SELECT parent_control_account_id
                                     FROM gl_chart_of_accounts
                                     WHERE chart_of_account_code = in_5th_lev_code);
        l_code VARCHAR2(200);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_code;
        CLOSE c1;
        RETURN l_code;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This procedure is for updating uploaded bank statement serial number
    */
    
    PROCEDURE upd_bank_serial_no (
        in_do_id         IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT a.sales_order_id,
               b.bank_id,
               b.bank_sr_no,
               a.gl_voucher_id,
               v.voucher_date,
               a.company_id,
               a.branch_id
        FROM inv_sales_orders a,
             sales_order_attachments b,
             gl_chart_of_accounts c,
             ar_customers cr,
             ar_customers_detail cd,
             gl_vouchers v
        WHERE a.sales_order_id = b.sales_order_id
        AND b.bank_id = c.chart_of_account_id
        AND a.customer_id = cr.customer_id
        AND a.branch_id = cd.branch_id
        AND cr.customer_id = cd.customer_id
        AND a.gl_voucher_id = v.voucher_id
        AND a.sales_order_id = in_do_id;
        l_cnt NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_cnt
        FROM (
            SELECT bank_sr_no
            FROM sales_order_attachments
            WHERE sales_order_id = in_do_id
            MINUS
            SELECT bank_sr_no
            FROM upload_bank_statement
            );
        
        IF l_cnt = 0 THEN
            FOR m IN c1 LOOP 
                UPDATE upload_bank_statement
                SET voucher_id = m.gl_voucher_id,
                    voucher_date = m.voucher_date,
                    status = 'APPROVED',
                    settled_date = SYSDATE
                WHERE bank_sr_no = m.bank_sr_no
                AND bank_id = m.bank_id
                AND company_id = m.company_id
                AND branch_id = m.branch_id;
            END LOOP;
        ELSE
            out_error_text := 'BANK SERIAL NUMBER NOT EXISTS IN BANK STATEMENT';
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    /*
    -- During Collection Approval Voucher will be generated
    */
   
    -- voucher type --  BRV
    -- module -- AR
    -- receipt type -- 06
    -- receipt from -- 01
    -- receipt from id -- cust id
    
    PROCEDURE ar_collection_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_date     DATE;
        v_type     VARCHAR2(10);
        i          NUMBER;
        l_amount   NUMBER;
        l_receivable_account_id NUMBER;
        l_cust_id  NUMBER;
        l_code VARCHAR2(50);
        l_text VARCHAR2(500);
        l_cnt NUMBER;
    BEGIN
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;

            SELECT approved_date,deposit_date,
                   in_company_id, 
                   'BRV'
            INTO acc_date,v_date,
                 company, 
                 v_type
            FROM inv_sales_collection
            WHERE collection_id = do_id;

            v_no:=get_voucher_no (v_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;

        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'BRV', 
                   v_no, 
                   v_date, 
                   'Entry Against Collection# '|| r.collection_no, 
                   batchid, 
                   user_id, 
                   SYSDATE,
                   user_id, 
                   acc_date, 
                   'APPROVED',
                   user_id, 
                   SYSDATE,
                   'AR',
                   'COLL_APPROVE', 
                   r.collection_id, 
                   company, 
                   branch, 
                   r.collection_no , 
                   '06' , 
                   r.customer_id , 
                   '01' , 
                   user_id , 
                   SYSDATE
            FROM inv_sales_collection r    
            WHERE r.collection_id = do_id
            AND collection_type='SALES';
            
        END IF;
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               NULL, 
               NULL, 
               sales_order_id
        FROM ar_collection_transfer_v
        WHERE sales_order_id = do_id
        AND branch_id = in_branch_id;

        UPDATE inv_sales_collection
        SET    gl_voucher_id = v_id
        WHERE  collection_id = do_id;
        
        SELECT SUM(credit) , MAX(receiveable_account_id)
        INTO l_amount , l_receivable_account_id
        FROM ar_collection_transfer_v
        WHERE sales_order_id = do_id
        AND debit = 0
        AND branch_id = in_branch_id;
        
        SELECT customer_id
        INTO l_cust_id
        FROM inv_sales_collection
        WHERE collection_id = do_id;
        
        UPDATE ar_customers_detail
        SET opening_balance = nvl(opening_balance,0) + NVL(l_amount,0)
        WHERE customer_id  = l_cust_id
        AND branch_id = in_branch_id;
        
        gbl_supp.send_sms_during_do (
            in_do_id   => do_id
        );
        
        COMMIT;
       
        SELECT NVL(COUNT(1),0)
        INTO l_cnt
        FROM ar_collection_bank_charge
        WHERE sales_order_id = do_id;
        
        IF l_cnt > 0 THEN
        
            acc_supp.ar_collection_bank_charge_trn (
                do_id            => do_id,
                user_id          => user_id,
                gl_v_id          => gl_v_id,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_code,
                out_error_text   => l_text
            );
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    PROCEDURE ar_collection_bank_charge_trn (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_type     VARCHAR2(10);
        i          NUMBER;
        l_amount   NUMBER;
        l_receivable_account_id NUMBER;
        l_cust_id  NUMBER;
    BEGIN
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;

            SELECT approved_date,
                   in_company_id, 
                   'BPV'
            INTO acc_date,
                 company, 
                 v_type
            FROM inv_sales_collection
            WHERE collection_id = do_id;

            v_no:=get_voucher_no (acc_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;

        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'BPV', 
                   v_no, 
                   SYSDATE, 
                   'Entry Against Collection for Bank Charge# '|| r.collection_no, 
                   batchid, 
                   user_id, 
                   SYSDATE,
                   NULL, 
                   NULL, 
                   'APPROVED',
                   user_id, 
                   SYSDATE,
                   'AR',
                   'DO APPROVE', 
                   r.collection_id, 
                   company, 
                   branch, 
                   r.collection_no , 
                   '06' , 
                   r.customer_id , 
                   '01' , 
                   user_id , 
                   SYSDATE
            FROM inv_sales_collection r    
            WHERE r.collection_id = do_id;
        END IF;
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               NULL, 
               NULL, 
               sales_order_id
        FROM ar_collection_bank_charge
        WHERE sales_order_id = do_id
        AND branch_id = in_branch_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    
    PROCEDURE upd_bank_serial_no_coll (
        in_do_id         IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT a.collection_id,
               b.bank_id,
               b.bank_sr_no,
               a.gl_voucher_id,
               v.voucher_date,
               a.company_id,
               a.branch_id
        FROM inv_sales_collection a,
             sales_coll_attachments b,
             gl_chart_of_accounts c,
             ar_customers cr,
             ar_customers_detail cd,
             gl_vouchers v
        WHERE a.collection_id = b.collection_id
        AND b.bank_id = c.chart_of_account_id
        AND a.customer_id = cr.customer_id
        AND a.branch_id = cd.branch_id
        AND cr.customer_id = cd.customer_id
        AND a.gl_voucher_id = v.voucher_id
        AND a.collection_id = in_do_id;
        l_cnt NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_cnt
        FROM (
            SELECT bank_sr_no
            FROM sales_coll_attachments
            WHERE collection_id = in_do_id
            MINUS
            SELECT bank_sr_no
            FROM upload_bank_statement
            );
        
        IF l_cnt = 0 THEN
            FOR m IN c1 LOOP 
                UPDATE upload_bank_statement
                SET voucher_id = m.gl_voucher_id,
                    voucher_date = m.voucher_date,
                    status = 'APPROVED'
                WHERE bank_sr_no = m.bank_sr_no
                AND bank_id = m.bank_id
                AND company_id = m.company_id
                AND branch_id = m.branch_id;
            END LOOP;
        ELSE
            out_error_text := 'BANK SERIAL NUMBER NOT EXISTS IN BANK STATEMENT';
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    FUNCTION get_trial_balance_sum (
        in_coa_id        IN     NUMBER,
        in_date          IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(BALANCE,0))
        FROM gl_trial_v
        WHERE acc_id = in_coa_id
        AND status = 'APPROVED'
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND record_level = 5
        AND voucher_date < in_date;
        l_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amount;
        CLOSE c1;
        RETURN l_amount;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE iou_payment_transfer (
        in_iou_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company       NUMBER := in_company_id;
        branch        VARCHAR2(20) := in_branch_id;
        v_id          NUMBER;
        v_no          NUMBER;
        acc_date      DATE;
        description   VARCHAR(250);
        pay_mode      VARCHAR(250);
        pay_amount    NUMBER;
        created_by    NUMBER;
        creation_date DATE;
    BEGIN
        SELECT approved_date,
               amount,
              'Entry Aginst IOU ID '|| iou_id,
               DECODE (payment_type,'C', 'CPV', 'BPV'),
               created_by,
               TRUNC(creation_date),
               company_id
        INTO acc_date,
             pay_amount, 
             description,
             pay_mode,
             created_by,
             creation_date, 
             company
        FROM hr_iou_issue
        WHERE iou_id = in_iou_id;

        IF in_gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL    
            INTO v_id      
            FROM dual;
                
            v_no := get_voucher_no(acc_date,pay_mode,company,branch);
                
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date, 
                module,
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                pay_to_id,
                paid_to,
                PAID_TO_TYPE
              )
            SELECT v_id, 
                   pay_mode,
                   v_no,
                   acc_date, 
                   'Entry Aginst Employee Name. '|| c.emp_name , 
                   si.created_by,
                   si.creation_date, 
                   si.last_updated_by, 
                   si.last_updated_date,
                  'PREPARED',
                  NULL, 
                  NULL, 
                  'AP', 
                  'IOU-PAYMENT', 
                  si.iou_id, 
                  company, 
                  branch,
                  si.iou_to_id,
                  '02',
                  '08'
            FROM hr_iou_issue si, 
                 hr_employees c
            WHERE si.iou_to_id = c.emp_id 
            AND si.iou_id = in_iou_id;
        ELSE
            v_id:=in_gl_v_id;
        END IF;
        
        INSERT INTO gl_voucher_accounts(
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               account_id, 
               debit, 
               credit,
               naration, 
               in_user_id, 
               SYSDATE, 
               in_user_id, 
               SYSDATE, 
               iou_id
        FROM ap_iou_transfer_v
        WHERE iou_id = in_iou_id
        AND branch_id = in_branch_id;
        
        UPDATE hr_iou_issue
        SET gl_voucher_id = v_id
        WHERE iou_id = in_iou_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END; 
    
    FUNCTION fund_position_today_amt (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(today_amount) 
        FROM (
            SELECT SUM(NVL(s.cr_amount,0)) - SUM(NVL(s.dr_amount,0)) today_amount
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND NVL(bank_upload_type,'##') <> 'CDAR'
            GROUP BY s.bank_id,
                     s.branch_id
            UNION ALL
            SELECT SUM(NVL(s.cr_amount,0)) - SUM(NVL(s.dr_amount,0)) cdar
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND bank_upload_type = 'CDAR'
            AND voucher_id IS NOT NULL
            GROUP BY s.bank_id,
                     s.branch_id
        );
        
        l_today_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_today_amount;
        CLOSE c1;
        
        RETURN l_today_amount;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION fund_position_unsettled_amt (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(s.cr_amount,0)) - SUM(NVL(s.dr_amount,0)) unsettled_amount
        FROM upload_bank_statement s
        WHERE bank_upload_type = 'CDAR'
        AND s.bank_id = in_bank_id
        AND s.branch_id = NVL(in_branch_id,s.branch_id)
        AND s.voucher_id IS NULL
        AND s.tran_date <= in_date
        AND s.tran_date >= TO_DATE('02/01/2024', 'MM/DD/RRRR')            --> from first february this event started
        GROUP BY s.bank_id,
                 s.branch_id;
                 
        l_unsettled_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_unsettled_amount;
        CLOSE c1;
        
        RETURN l_unsettled_amount;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE iou_payment_receive (
        in_iour_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company       NUMBER := in_company_id;
        branch        VARCHAR2(20) := in_branch_id;
        v_id          NUMBER;
        v_no          NUMBER;
        acc_date      DATE;
        description   VARCHAR(250);
        pay_mode      VARCHAR(250);
        created_by    NUMBER;
        creation_date DATE;
        l_cnt         NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_cnt 
        FROM ap_iou_receive_v
        WHERE iour_id = in_iour_id
        AND branch_id = in_branch_id;
        
        IF l_cnt > 0 THEN
        
            SELECT approved_date,
                  'Entry Aginst IOU Rcv ID '|| iour_id,
                   'JV', 
                   created_by,
                   TRUNC(creation_date),
                   company_id
            INTO acc_date,
                 description,
                 pay_mode,
                 created_by,
                 creation_date, 
                 company
            FROM hr_iou_receive_m 
            WHERE iour_id = in_iour_id;

            IF in_gl_v_id IS NULL THEN
                SELECT gl_voucher_id_s.NEXTVAL    
                INTO v_id      
                FROM dual;
                    
                v_no := get_voucher_no(acc_date,pay_mode,company,branch);
                    
                INSERT INTO gl_vouchers (
                    voucher_id, 
                    voucher_type, 
                    voucher_no, 
                    voucher_date,
                    description, 
                    created_by, 
                    creation_date,
                    last_updated_by, 
                    last_updated_date, 
                    status,
                    approved_by, 
                    approval_date, 
                    module,
                    module_doc, 
                    module_doc_id, 
                    company_id, 
                    branch_id,
                    pay_to_id,
                    paid_to,
                    paid_to_type
                  )
                SELECT v_id,
                       'JVP', 
                       v_no,
                       SYSDATE,--acc_date,
                       'Entry Aginst Employee/Vendor Name. '|| c.emp_name , 
                       si.created_by,
                       si.creation_date, 
                       si.last_updated_by, 
                       si.last_updated_date,
                      'PREPARED',
                      NULL, 
                      NULL, 
                      'AP', 
                      'IOU-RECEIPT', 
                      d.iour_id, 
                      company,
                      branch,
                      si.iou_to_id,
                      '02',
                      '09'
                FROM hr_iou_receive_m d, 
                     hr_employees c,
                     hr_iou_issue si
                WHERE si.iou_to_id = c.emp_id
                and   si.iou_id = d.iou_id 
                AND d.iour_id = in_iour_id;
            ELSE
                v_id:=in_gl_v_id;
            END IF;
            
            INSERT INTO gl_voucher_accounts(
                voucher_account_id, 
                voucher_id, 
                account_id, 
                debit, 
                credit,
                naration, 
                created_by, 
                creation_date, 
                last_updated_by,
                last_update_date, 
                reference_id
            )
            SELECT gl_voucher_account_id_s.NEXTVAL, 
                   v_id, 
                   account_id, 
                   debit, 
                   credit,
                   naration, 
                   in_user_id, 
                   SYSDATE, 
                   in_user_id, 
                   SYSDATE, 
                   iour_id
            FROM ap_iou_receive_v
            WHERE iour_id = in_iour_id
            AND branch_id = in_branch_id;
            
            UPDATE hr_iou_receive_m
            SET gl_voucher_id = v_id
            WHERE iour_id = in_iour_id;
            
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END; 
    
    
    PROCEDURE iou_payment_receive_reimb (
        in_iour_id       IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT DISTINCT payment_type
        FROM ap_iou_receive_reimb_v
        WHERE iour_id = in_iour_id
        AND branch_id = in_branch_id;
        
        company       NUMBER := in_company_id;
        branch        VARCHAR2(20) := in_branch_id;
        v_id          NUMBER;
        v_no          NUMBER;
        acc_date      DATE;
        description   VARCHAR(250);
        pay_mode      VARCHAR(250);
        pay_amount    NUMBER;
        created_by    NUMBER;
        creation_date DATE;
        l_voucher_typ VARCHAR2(50);
        l_cnt         NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_cnt
        FROM ap_iou_receive_reimb_v
        WHERE iour_id = in_iour_id
        AND branch_id = in_branch_id;
        
        IF l_cnt > 0 THEN
        
            FOR m IN c1 LOOP
                SELECT approved_date,
                      'Entry Aginst IOU Rcv ID '|| iour_id ,
                       created_by,
                       TRUNC(creation_date),
                       company_id
                INTO acc_date ,
                     description,
                     created_by,
                     creation_date, 
                     company
                FROM hr_iou_receive_m 
                WHERE iour_id = in_iour_id;
                
                l_voucher_typ := m.payment_type;

                SELECT DECODE (l_voucher_typ, 'C', 'CPV', 'BPV')
                INTO pay_mode
                FROM dual;

                IF in_gl_v_id IS NULL THEN
                    SELECT gl_voucher_id_s.NEXTVAL    
                    INTO v_id      
                    FROM dual;
                        
                    v_no := get_voucher_no(acc_date,pay_mode,company,branch);
                        
                    INSERT INTO gl_vouchers (
                        voucher_id, 
                        voucher_type, 
                        voucher_no, 
                        voucher_date,
                        description, 
                        created_by, 
                        creation_date,
                        last_updated_by, 
                        last_updated_date, 
                        status,
                        approved_by, 
                        approval_date, 
                        module,
                        module_doc, 
                        module_doc_id, 
                        company_id, 
                        branch_id,
                        pay_to_id,
                        paid_to,
                        paid_to_type
                      )
                    SELECT v_id,
                           pay_mode, 
                           v_no,
                           SYSDATE,--acc_date,
                           'Entry Aginst Employee/Vendor Name. '|| c.emp_name , 
                           si.created_by,
                           si.creation_date, 
                           si.last_updated_by, 
                           si.last_updated_date,
                          'PREPARED',
                           NULL, 
                           NULL, 
                          'AP', 
                          'IOU-RECEIPT-REIMB',   
                          d.iour_id, 
                          company,
                          branch,
                          si.iou_to_id,
                          '02',                  
                          '09'                   
                    FROM hr_iou_receive_m d, 
                         hr_employees c,
                         hr_iou_issue si
                    WHERE si.iou_to_id = c.emp_id
                    and   si.iou_id = d.iou_id 
                    AND d.iour_id = in_iour_id;
                ELSE
                    v_id:=in_gl_v_id;
                END IF;
                
                INSERT INTO gl_voucher_accounts(
                    voucher_account_id, 
                    voucher_id, 
                    account_id, 
                    debit, 
                    credit,
                    naration, 
                    created_by, 
                    creation_date, 
                    last_updated_by,
                    last_update_date, 
                    reference_id
                )
                SELECT gl_voucher_account_id_s.NEXTVAL, 
                       v_id, 
                       account_id, 
                       debit, 
                       credit,
                       naration, 
                       in_user_id, 
                       SYSDATE, 
                       in_user_id, 
                       SYSDATE, 
                       iour_id
                FROM ap_iou_receive_reimb_v
                WHERE iour_id = in_iour_id
                AND branch_id = in_branch_id
                AND NVL(payment_type, '#') = l_voucher_typ;
                
                IF l_voucher_typ = 'C' THEN                
                    UPDATE hr_iou_receive_m
                    SET gl_voucher_id_reimb_c = v_id
                    WHERE iour_id = in_iour_id;
                ELSIF l_voucher_typ = 'B' THEN
                    UPDATE hr_iou_receive_m
                    SET gl_voucher_id_reimb_b = v_id
                    WHERE iour_id = in_iour_id;
                END IF;
                
                COMMIT;
                
            END LOOP;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;  
    
    /*
    -- Auto voucher generation during invoice Matching for Services  --   AP
    */
    
    PROCEDURE ap_invoice_services_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER  :=  in_company_id;
        branch     VARCHAR2(20) := in_branch_id;
        v_id       NUMBER;
        v_no       NUMBER;
        chk        NUMBER;
        acc_date   DATE;
        remarks    VARCHAR2(300);
        l_cnt      NUMBER;
    BEGIN
        SELECT TRUNC(accounting_date), 
               i.invoice_amount,
               remarks
        INTO acc_date, 
             chk,
             remarks
        FROM ap_invoices i    
        WHERE invoice_id = inv_id;
        
        SELECT COUNT(*)
        INTO l_cnt 
        FROM ap_invoice_transfer_service_v
        WHERE invoice_id = inv_id;
        
        IF l_cnt > 0  THEN
        
            IF gl_v_id IS NULL THEN
                SELECT gl_voucher_id_s.NEXTVAL    
                INTO v_id      
                FROM dual;
                
                v_no := get_voucher_no(acc_date,'JVP',company,branch);
                
                INSERT INTO gl_vouchers (
                    voucher_id, 
                    voucher_type, 
                    voucher_no, 
                    voucher_date,
                    description, 
                    created_by, 
                    creation_date,
                    last_updated_by, 
                    last_updated_date, 
                    status,
                    approved_by, 
                    approval_date, 
                    cheked_by, 
                    checked_date, 
                    module,
                    module_doc, 
                    module_doc_id, 
                    company_id, 
                    branch_id,
                    pay_to_id,
                    paid_to,
                    paid_to_type
                )
                SELECT v_id, 
                       'JVP',
                       v_no,
                       acc_date, 
                       remarks || ' Entry Aginst Booking Service # '|| si.ap_invoice_no, 
                       si.created_by,
                       si.creation_date, 
                       si.last_updated_by, 
                       si.last_update_date,
                      'APPROVED',
                      si.TRANSFER_ID,
                      si.TRANSFER_DATE,
                      si.CREATED_BY,
                      si.CREATION_DATE,
                      'AP', 
                      'INVOICE-SERVICES', 
                      si.invoice_id, 
                      company, 
                      branch,
                      si.vendor_id,
                      '01',
                      '05'
                FROM ap_invoices si, 
                     inv_vendors c
                WHERE si.vendor_id = c.vendor_id 
                AND si.invoice_id = inv_id;
            ELSE
                v_id:=gl_v_id;
            END IF;

            INSERT INTO gl_voucher_accounts (
                voucher_account_id, 
                voucher_id, 
                account_id, 
                debit, 
                credit,
                naration, 
                created_by, 
                creation_date, 
                last_updated_by,
                last_update_date, 
                reference_id
            )
            SELECT gl_voucher_account_id_s.NEXTVAL, 
                   v_id, 
                   account_id, 
                   debit,
                   credit, 
                   naration, 
                   user_id, 
                   SYSDATE, 
                   user_id, 
                   SYSDATE,
                   invoice_id
            FROM ap_invoice_transfer_service_v
            WHERE invoice_id = inv_id;
            
            
            UPDATE ap_invoices
            SET gl_voucher_id = v_id
            WHERE invoice_id = inv_id;
            
            COMMIT;
            
        ELSE
            out_error_code := 'NO DATA';
            out_error_text := 'NO DATA IN VIEW';
        END IF;
  
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END ;
    
    
    FUNCTION fund_position_today_debit (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(today_amount) debit
        FROM (
            SELECT SUM(NVL(s.dr_amount,0)) today_amount
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND NVL(bank_upload_type,'##') <> 'CDAR'
            GROUP BY s.bank_id,
                     s.branch_id
            UNION ALL
            SELECT SUM(NVL(s.dr_amount,0)) cdar
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND bank_upload_type = 'CDAR'
            AND voucher_id IS NOT NULL
            GROUP BY s.bank_id,
                     s.branch_id
        );
        
        l_today_debit NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_today_debit;
        CLOSE c1;
        
        RETURN l_today_debit;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION fund_position_today_credit (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(today_amount) credit
        FROM (
            SELECT SUM(NVL(s.cr_amount,0)) today_amount
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND NVL(bank_upload_type,'##') <> 'CDAR'
            GROUP BY s.bank_id,
                     s.branch_id
            UNION ALL
            SELECT SUM(NVL(s.cr_amount,0)) cdar
            FROM upload_bank_statement s
            WHERE TRUNC(s.tran_date) = TRUNC(TO_DATE(in_date))
            AND s.bank_id = in_bank_id
            AND s.branch_id = NVL(in_branch_id,s.branch_id)
            AND bank_upload_type = 'CDAR'
            AND voucher_id IS NOT NULL
            GROUP BY s.bank_id,
                     s.branch_id
        );
        
        l_today_credit NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_today_credit;
        CLOSE c1;
        
        RETURN l_today_credit;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION get_iou_amount (
        in_iou_app_date  IN     DATE,
        in_gl_account_id IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(amount) amt
        FROM hr_iou_issue
        WHERE TRUNC(approved_date) = TRUNC(in_iou_app_date)
        AND branch_id = in_branch_id
        AND gl_account_id = in_gl_account_id
        AND status = 'APPROVED';
        
        l_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amount;
        CLOSE c1;
        
        RETURN l_amount;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION fund_position_today_debit_c (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(debit,0))
        FROM gl_trial_v
        WHERE acc_id = in_bank_id
        AND status = 'APPROVED'
        AND branch_id = NVL(in_branch_id, branch_id)
        AND record_level = 5
        AND voucher_date = in_date;
        l_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amount;
        CLOSE c1;
        RETURN l_amount;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    FUNCTION fund_position_today_credit_c (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(NVL(credit,0))
        FROM gl_trial_v
        WHERE acc_id = in_bank_id
        AND status = 'APPROVED'
        AND branch_id = NVL(in_branch_id, branch_id)
        AND record_level = 5
        AND voucher_date = in_date;
        l_amount NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_amount;
        CLOSE c1;
        RETURN l_amount;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    PROCEDURE ins_gl_fund_position (
        in_date          IN     DATE,
        in_company       IN     NUMBER,
        in_branch        IN     VARCHAR2
    )
    IS
        CURSOR fund_flow
        IS
        SELECT DECODE(v.in_usage,'N', 'Non Active', 'C' , 'Cash', 'R' , 'Reserve',  'Y','Active' , 'P' , 'Project') active_nonactive,
               DECODE(v.in_usage,'N', '4Non Active', 'C' , '1Cash', 'R', '2Reserve' ,'Y' ,'3Active', 'P', 'Project') sorting,
               b.branch_name,
               v.short_desc bank_name,
               NVL(acc_supp.get_trial_balance_sum(v.acc_id, in_date, in_company, b.branch_id),0) opening_balance,
               NVL(cp.amount,0) + NVL(acc_supp.get_iou_amount(in_date, v.acc_id, b.branch_id) , 0)  amount,
               NVL(acc_supp.fund_position_today_amt(v.acc_id, in_date, b.branch_id),0) today_amount,
               NVL(acc_supp.fund_position_today_debit(v.acc_id, in_date, b.branch_id),0) debit_amount,
               NVL(acc_supp.fund_position_today_credit(v.acc_id, in_date, b.branch_id),0) credit_amount,
               NVL(acc_supp.fund_position_unsettled_amt(v.acc_id, in_date, b.branch_id),0) unsettled_amount,
               NVL(cp.reserve_amount,0) reserve_amount,
               NVL(acc_supp.get_trial_balance_sum(v.acc_id,in_date, in_company, b.branch_id),0) -
               NVL(cp.amount,0) + 
               NVL(acc_supp.fund_position_today_amt(v.acc_id, in_date, b.branch_id),0) + 
               NVL(acc_supp.fund_position_unsettled_amt(v.acc_id, in_date, b.branch_id),0) closing_amount
        FROM gl_account_chart_v v,
             sys_branches b,
             (
               SELECT *
               FROM gl_cheque_present
               WHERE entry_date = in_date
             ) cp      
        WHERE v.branch_id = b.branch_id
        AND v.acc_id = cp.bank_id(+)
        AND v.branch_id = NVL(in_branch, v.branch_id)
        AND v.parent_control_account_id IN (200)
        AND v.acc_id NOT IN (835)
        AND v.in_usage IS NOT NULL
        UNION ALL
        SELECT DECODE(v.in_usage,'N', 'Non Active', 'C' , 'Cash', 'R' , 'Reserve',  'Y','Active' , 'P' , 'Project') active_nonactive,
               DECODE(v.in_usage,'N', '4Non Active', 'C' , '1Cash', 'R', '2Reserve' ,'Y' ,'3Active', 'P', 'Project') sorting,
               b.branch_name,
               v.short_desc bank_name,
               NVL(acc_supp.get_trial_balance_sum(v.acc_id, in_date, in_company, b.branch_id),0) opening_balance,
               NVL(cp.amount,0) + NVL(acc_supp.get_iou_amount(in_date, v.acc_id, b.branch_id) , 0)  amount,
               NVL(acc_supp.fund_position_today_amt(v.acc_id, in_date, b.branch_id),0) today_amount,
               NVL(acc_supp.fund_position_today_debit_c(v.acc_id, in_date, b.branch_id),0) debit_amount,
               NVL(acc_supp.fund_position_today_credit_c(v.acc_id, in_date, b.branch_id),0) credit_amount,
               NVL(acc_supp.fund_position_unsettled_amt(v.acc_id, in_date, b.branch_id),0) unsettled_amount,
               NVL(cp.reserve_amount,0) reserve_amount,
               NVL(acc_supp.get_trial_balance_sum(v.acc_id,in_date, in_company, b.branch_id),0) +
               NVL(acc_supp.fund_position_today_debit_c(v.acc_id, in_date, b.branch_id),0) -
               NVL(acc_supp.fund_position_today_credit_c(v.acc_id, in_date, b.branch_id),0)  closing_amount
        FROM gl_account_chart_v v,
             sys_branches b,
             (
               SELECT *
               FROM gl_cheque_present
               WHERE entry_date = in_date
             ) cp      
        WHERE v.branch_id = b.branch_id
        AND v.acc_id = cp.bank_id(+)
        AND v.branch_id = NVL(in_branch, v.branch_id)
        AND v.parent_control_account_id IN (105)
        AND v.acc_id NOT IN (835)
        AND v.in_usage IS NOT NULL;
    BEGIN
        DELETE FROM gl_fund_position;
        COMMIT;
        
        FOR i IN fund_flow LOOP
            INSERT INTO gl_fund_position (
                active_nonactive, 
                sorting, 
                branch_name, 
                bank_name, 
                opening_balance, 
                amount, 
                today_amount, 
                debit_amount, 
                credit_amount, 
                unsettled_amount, 
                reserve_amount, 
                closing_amount
            )
            VALUES (
                i.active_nonactive, 
                i.sorting, 
                i.branch_name, 
                i.bank_name, 
                i.opening_balance, 
                i.amount, 
                i.today_amount, 
                i.debit_amount, 
                i.credit_amount, 
                i.unsettled_amount, 
                i.reserve_amount, 
                i.closing_amount
            );
            
        END LOOP;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    
    /*
    -- calculate upto previous fiscal year last date
    */
    
    PROCEDURE ins_pnl_data_prev (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        CURSOR profit_loss_qty
        IS
        SELECT lev1.name lev1,
               lev3.name lev3,
               lev3.id lev3_id,
               TO_CHAR(d.fiscal_year) fiscal_year,
               d.qty,
               m.pnl_mst_id,
               d.fiscal_year year_n,
               0 month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               0 cfy_qty
        FROM gl_profit_loss_mst m,
             gl_profit_loss_setup lev1,
             gl_profit_loss_setup lev2,
             gl_profit_loss_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty
             FROM gl_profit_loss_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id = NVL(in_branch_id,m.branch_id)
        AND level2_setup_id IN (101,102) 
        UNION ALL
        SELECT lev1.name lev1,
               lev3.name lev3,
               lev3.id lev3_id,
               month||' - '||year,
               CASE 
                   WHEN level2_setup_id = 101 THEN sales_supp.get_bulk_sales_qty(this_year.month||'-'||this_year.year,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) 
                   WHEN level2_setup_id = 102 THEN sales_supp.get_cylinder_sales_qty(this_year.month||'-'||this_year.year,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END qty,
               m.pnl_mst_id,
               year year_n,
               month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               CASE
                   WHEN lev3.id = 1001 then sales_supp.get_bulk_sales_cfy (
                                                in_to_date     => in_end_date,
                                                in_company_id  => in_company_id,
                                                in_branch_id   => in_branch_id
                                            )
                   WHEN lev3.id = 1002 then sales_supp.get_cylinder_sales_cfy (
                                                in_to_date     => in_end_date,
                                                in_company_id  => in_company_id,
                                                in_branch_id   => in_branch_id
                                            )
               END cfy_qty
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_profit_loss_mst m,
            gl_profit_loss_setup lev1,
            gl_profit_loss_setup lev2,
            gl_profit_loss_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102)
        ORDER BY year_n, month_n;

        CURSOR profit_loss_amt
        IS
        SELECT lev1.name lev1,
               lev3.name lev3,
               TO_CHAR(d.fiscal_year) fiscal_year,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amount,
               0 cfy_amt,
               m.pnl_mst_id,
               d.fiscal_year year_n,
               0 month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id
        FROM gl_profit_loss_mst m,
             gl_profit_loss_setup lev1,
             gl_profit_loss_setup lev2,
             gl_profit_loss_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty
             FROM gl_profit_loss_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id = NVL(in_branch_id,m.branch_id)
        UNION ALL
        SELECT lev1.name lev1,
               lev3.name lev3,
               month||' - '||year,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) 
               END amount,
               --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount ,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_prev ( m.pnl_mst_id,in_end_date, 5, in_company_id, in_branch_id)
                   ELSE acc_supp.get_trial_balance_prev ( m.pnl_mst_id,in_end_date, 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END cfy_amt,
               --acc_supp.get_yearly_trial_balance ( m.pnl_mst_id,in_end_date, 5, in_company_id, in_branch_id) cfy_amt,
               m.pnl_mst_id,
               TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
               month_n,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_profit_loss_mst m,
            gl_profit_loss_setup lev1,
            gl_profit_loss_setup lev2,
            gl_profit_loss_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
        ORDER BY year_n, month_n;
        
        CURSOR profit_loss_amt_sum
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR gross_profit
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        
        CURSOR gross_profit_pct
        IS
        SELECT a.total_fiscal_year,
               a.total_year_n,
               a.total_month_n,
               ROUND(((a.total_amount / NULLIF(b.total_amount,0)) *100),2) gross_pct
        FROM (
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount 
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 215
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ) a,
        (
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n) b
        WHERE a.total_fiscal_year = b.total_fiscal_year
        ORDER BY 2,3;
        
        CURSOR net_sales
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id >= 101 AND m.level2_setup_id <= 107 
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR profit_b4_interest
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id NOT IN (401,402,501,502,601,801)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id NOT IN (401,402,501,502,601,801)
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;        
        
        CURSOR profit_b4_dep_income_tx
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id NOT IN (501,502,601)
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id NOT IN (501,502,601)
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
        CURSOR profit_b4_income_tx
        IS
        SELECT total_fiscal_year,
               year_n total_year_n,
               month_n total_month_n,
               SUM(amount) total_amount
        FROM (
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   TO_CHAR(d.fiscal_year) total_fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount
                       ELSE d.amount
                   END amount,
                   d.fiscal_year year_n,
                   0 month_n
            FROM gl_profit_loss_mst m,
                 gl_profit_loss_setup lev1,
                 gl_profit_loss_setup lev2,
                 gl_profit_loss_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty
                 FROM gl_profit_loss_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id = NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id <> 601
            UNION ALL
            SELECT lev1.name lev1,
                   lev3.name lev3,
                   month||' - '||year fiscal_year,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END amount,
                   --acc_supp.get_trial_balance (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amount,
                   TO_NUMBER(TO_CHAR(in_end_date, 'RRRR')) year_n,
                   month_n
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_profit_loss_mst m,
                gl_profit_loss_setup lev1,
                gl_profit_loss_setup lev2,
                gl_profit_loss_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date -- curr_fiscal_year_last_date
            AND m.level2_setup_id <> 601
        )
        GROUP BY total_fiscal_year,
                 year_n,
                 month_n
        ORDER BY 2,3;
        
    BEGIN

        FOR i IN profit_loss_qty LOOP
            INSERT INTO gl_profit_loss_qty  (
                lev1, 
                lev3, 
                lev3_id, 
                fiscal_year, 
                qty, 
                cfy_qty,
                pnl_mst_id, 
                year_n, 
                month_n, 
                level1_serial, 
                level2_serial, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                i.lev1, 
                i.lev3, 
                i.lev3_id, 
                i.fiscal_year, 
                i.qty, 
                i.cfy_qty,
                i.pnl_mst_id, 
                i.year_n, 
                i.month_n, 
                i.level1_serial, 
                i.level2_serial, 
                null, 
                null, 
                in_company_id, 
                in_branch_id
            );
            
        END LOOP;
        
        COMMIT;
        
        FOR j IN profit_loss_amt LOOP
            INSERT INTO gl_profit_loss_amt (
                lev1, 
                lev3, 
                fiscal_year, 
                amount, 
                cfy_amt,
                pnl_mst_id, 
                year_n, 
                month_n, 
                level1_serial, 
                level2_serial, 
                from_date, 
                to_date, 
                company_id, 
                branch_id,
                signed_operator,
                lev3_id
            )
            VALUES (
                j.lev1, 
                j.lev3, 
                j.fiscal_year, 
                j.amount,
                j.cfy_amt, 
                j.pnl_mst_id, 
                j.year_n, 
                j.month_n, 
                j.level1_serial, 
                j.level2_serial, 
                null,
                null,
                in_company_id, 
                in_branch_id,
                j.signed_operator,
                j.level3_setup_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR k IN profit_loss_amt_sum LOOP
            INSERT INTO gl_profit_loss_amt_sum ( 
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                k.total_fiscal_year, 
                k.total_year_n, 
                k.total_month_n, 
                k.total_amount, 
                null,
                null,
                in_company_id, 
                in_branch_id
            );
            
        END LOOP;
        
        COMMIT;
        
        FOR m IN gross_profit LOOP
            INSERT INTO gl_profit_loss_gross_profit (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                m.total_fiscal_year, 
                m.total_year_n, 
                m.total_month_n, 
                m.total_amount,         
                NULL,
                NULL,
                in_company_id,
                in_branch_id
            );
            
        END LOOP;
        COMMIT;
        
        FOR n IN gross_profit_pct LOOP
            INSERT INTO gl_pnl_gross_profit_pct (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                gross_pct, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                n.total_fiscal_year, 
                n.total_year_n, 
                n.total_month_n, 
                n.gross_pct, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        COMMIT;
        
        FOR x IN net_sales LOOP
            INSERT INTO gl_profit_loss_net_sales (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                x.total_fiscal_year, 
                x.total_year_n, 
                x.total_month_n, 
                x.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR a IN profit_b4_interest LOOP
            INSERT INTO gl_profit_b4_interest (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                a.total_fiscal_year, 
                a.total_year_n, 
                a.total_month_n, 
                a.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR y IN profit_b4_dep_income_tx LOOP
            INSERT INTO gl_profit_b4_dep_income_tx (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                y.total_fiscal_year, 
                y.total_year_n, 
                y.total_month_n, 
                y.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
        FOR z IN profit_b4_income_tx LOOP
            INSERT INTO gl_profit_b4_income_tx (
                total_fiscal_year, 
                total_year_n, 
                total_month_n, 
                total_amount, 
                from_date, 
                to_date, 
                company_id, 
                branch_id
            )
            VALUES (
                z.total_fiscal_year, 
                z.total_year_n, 
                z.total_month_n, 
                z.total_amount, 
                null,
                null,
                in_company_id,
                in_branch_id
            );
        END LOOP;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
        -- This procedure is added in scheduler for getting profit and loss data for pervious year.
           For making the report faster.
    */
    
    PROCEDURE populate_gl_profit_loss_prev
    IS
        CURSOR branch
        IS
        SELECT company_no,
               branch_id
        FROM sys_branches
        WHERE active = 'Y';
        
        CURSOR c2 
        IS
        SELECT MIN(start_date),
               MAX(end_date)
        FROM gl_fiscal_year;
        
        l_start_date DATE;
        l_end_date DATE;
        l_prev_fiscal_year NUMBER;
    BEGIN
    
        SELECT fiscal_year
        INTO l_prev_fiscal_year
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        
        DELETE FROM gl_profit_loss_prev_amt
        WHERE fiscal_year = l_prev_fiscal_year;
        COMMIT;
    
        DELETE FROM gl_profit_loss_qty;
        DELETE FROM gl_profit_loss_amt;
        DELETE FROM gl_profit_loss_amt_sum;
        DELETE FROM gl_profit_loss_gross_profit;
        DELETE FROM gl_pnl_gross_profit_pct;
        DELETE FROM gl_profit_loss_net_sales;
        DELETE FROM gl_profit_b4_dep_income_tx;
        DELETE FROM gl_profit_b4_income_tx;
        DELETE FROM gl_profit_b4_interest;
        
        COMMIT;
        
        OPEN c2;
            FETCH c2 INTO l_start_date, l_end_date;
        CLOSE c2;
        
        FOR m IN branch LOOP
            acc_supp.ins_pnl_data_prev (
                in_start_date    => l_start_date,
                in_end_date      => prev_fiscal_year_last_date,
                in_company_id    => m.company_no,
                in_branch_id     => m.branch_id
            );
            
        END LOOP;
        
        COMMIT;
        
        acc_supp.ins_pnl_amt_prev;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
     --  Year ind column is added in fiscal year table.
         Here C = For current fiscal year
              P = For previous fiscal year
         This function is for getting last date of current fiscal yaer
    */
    
    
    FUNCTION curr_fiscal_year_last_date 
    RETURN DATE
    IS
        CURSOR c1
        IS
        SELECT end_date
        FROM gl_fiscal_year
        WHERE year_ind = 'C';
        l_last_date DATE;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_last_date;
        CLOSE c1;
        
        RETURN l_last_date;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE ins_gl_pnl_prev_amt (
        in_pnl_mst_id    IN     NUMBER, 
        in_fiscal_year   IN     NUMBER, 
        in_from_date     IN     DATE, 
        in_to_date       IN     DATE, 
        in_amount        IN     NUMBER,
        in_qty           IN     NUMBER
    )
    IS
        l_pnl_amt_id NUMBER;
        l_start_date DATE;
        l_end_date DATE;
    BEGIN
        SELECT NVL(MAX(pnl_amt_id),0)+1
        INTO l_pnl_amt_id
        FROM gl_profit_loss_prev_amt;
        
        INSERT INTO gl_profit_loss_prev_amt (
            pnl_amt_id, 
            pnl_mst_id, 
            fiscal_year, 
            from_date, 
            to_date, 
            amount,
            qty,
            created_by, 
            creation_date, 
            last_updated_by, 
            last_updated_date
        )
        VALUES (
            l_pnl_amt_id,
            in_pnl_mst_id,
            in_fiscal_year,
            in_from_date,
            in_to_date,
            in_amount,
            in_qty,
            NULL,
            NULL,
            NULL,
            NULL
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
     /*
     -- Inserting previous fiscal year data of PNL
     */
    
    PROCEDURE ins_pnl_amt_prev
    IS
        CURSOR c1
        IS
        SELECT pnl_mst_id,
               MAX(yearn) yearn,
               SUM(qty) qty,
               SUM(amt) amt
        FROM (
            SELECT pnl_mst_id,
                   MAX(year_n) yearn,
                   SUM(NVL(qty,0)) qty,
                   0 amt
            FROM gl_profit_loss_qty
            WHERE month_n <> 0
            GROUP BY pnl_mst_id
            UNION 
            SELECT pnl_mst_id,
                   MAX(year_n) yearn,
                   0 qty,
                   SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amount,0)
                            ELSE NVL(amount,0)
                       END) amt
            FROM gl_profit_loss_amt
            WHERE month_n <> 0
            GROUP BY pnl_mst_id
                )
        GROUP BY pnl_mst_id
        ORDER BY pnl_mst_id;
        
        l_start_date DATE;
        l_end_date DATE;
        l_prev_fiscal_year NUMBER;
    BEGIN
        
        SELECT fiscal_year
        INTO l_prev_fiscal_year
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        
        DELETE FROM gl_profit_loss_prev_amt
        WHERE fiscal_year = l_prev_fiscal_year;
        COMMIT;
        
        FOR i IN c1 LOOP
            SELECT start_date,
                   end_date
            INTO l_start_date,
                 l_end_date
            FROM gl_fiscal_year
            WHERE fiscal_year = i.yearn;
            
            ins_gl_pnl_prev_amt (
                in_pnl_mst_id    => i.pnl_mst_id, 
                in_fiscal_year   => i.yearn, 
                in_from_date     => l_start_date, 
                in_to_date       => l_end_date, 
                in_amount        => i.amt,
                in_qty           => i.qty
            );
            
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
     --  Year ind column is added in fiscal year table.
         Here C = For current fiscal year
              P = For previous fiscal year
         This function is for getting last date of previous fiscal yaer
    */
    
    FUNCTION prev_fiscal_year_last_date 
    RETURN DATE
    IS
        CURSOR c1
        IS
        SELECT end_date
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        l_last_date DATE;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_last_date;
        CLOSE c1;
        
        RETURN l_last_date;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_trial_balance_prev (
        in_pnl_mst_id    IN     NUMBER,
        in_end_date      IN     DATE,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER
    IS
        CURSOR fiscal_year
        IS
        SELECT start_date
        FROM gl_fiscal_year
        WHERE end_date = in_end_date;
        
        l_balance NUMBER;
        l_start_date DATE;
    BEGIN
    
        OPEN fiscal_year;
            FETCH fiscal_year INTO l_start_date; 
        CLOSE fiscal_year;
    
        SELECT SUM(NVL(balance,0)) 
        INTO l_balance
        FROM gl_trial_v
        WHERE record_level = in_record_level
        AND acc_id IN ( 
                        SELECT coa_level5_id
                        FROM gl_profit_loss_dtl 
                        WHERE pnl_mst_id = in_pnl_mst_id
                      )
        AND company_id = NVL(in_company_id, company_id)
        AND branch_id = NVL(in_branch_id, branch_id)
        AND voucher_date BETWEEN l_start_date AND in_end_date
        AND status = 'APPROVED';
        
    
        RETURN l_balance;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 0;
    END;
    
    /*
    -- For previous fiscal year
    */
    
    PROCEDURE ins_gl_ebitda_prev (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    )
    IS
        CURSOR ebitda_qty
        IS
        SELECT sl,
               item_desc,
               item_id,
               sales_month,
               year_n,
               sales_year,
               item_capacity,
               qty_pcs,
               qty_mt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev3.name item_desc,
               lev3.id item_id,
               0 sales_month,
               d.fiscal_year year_n,
               d.period sales_year,
               m.capacity item_capacity,
               CASE 
                   WHEN m.level2_setup_id = 101 THEN 0
                   ELSE d.qty
               END qty_pcs,
               CASE 
                   WHEN m.level2_setup_id = 101 THEN d.qty / 1000
                   ELSE d.qty * m.capacity / 1000
               END qty_mt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                        -- current month
        SELECT 1 sl,
               lev3.name item_desc,
               lev3.id item_id,
               month_n sales_month,
               CASE 
                   WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                   WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
               END year_n,
               month||' - '||year_n sales_year,
               m.capacity item_capacity,
               sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
               sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                                        -- CFY
        SELECT 2 sl,
               item_desc,
               item_id,
               0,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(qty_pcs) qty_pcs,
               SUM(qty_mt) qty_mt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
                   sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 year_n,
                 TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id
        UNION ALL                                         --- YTD
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(qty_pcs) qty_pcs,
               SUM(qty_mt) qty_mt,
               pnl_mst_id
        FROM (
            SELECT 3 sl,                                  
                   item_desc,
                   item_id,
                   0,
                   0,
                   0 sales_year,
                   item_capacity,
                   SUM(qty_pcs) qty_pcs,
                   SUM(qty_mt) qty_mt,
                   pnl_mst_id
            FROM (
                SELECT 3 sl,
                       lev3.name item_desc,
                       lev3.id item_id,
                       month_n sales_month,
                       year_n,
                       month||' - '||year_n sales_year,
                       m.capacity item_capacity,
                       sales_supp.get_ebitda_sales_qty_pcs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) qty_pcs,
                       sales_supp.get_ebitda_sales_qty_kgs(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / 1000 qty_mt,
                       m.pnl_mst_id
                FROM(
                    SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                           TO_CHAR(D,'MON') AS MONTH,
                           EXTRACT(YEAR FROM d) AS YEAR_N
                    FROM (
                        SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                        FROM DUAL
                        CONNECT BY
                        ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                    )
                    WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                    ) this_year,
                    gl_ebitda_mst m,
                    gl_ebitda_setup lev1,
                    gl_ebitda_setup lev2,
                    gl_ebitda_setup lev3
                WHERE m.level1_setup_id = lev1.id
                AND m.level2_setup_id = lev2.id
                AND m.level3_setup_id = lev3.id     
                AND m.company_id = NVL(in_company_id, m.company_id)
                AND m.branch_id = NVL(in_branch_id, m.branch_id)
                AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
                AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
            )
            GROUP BY sl,
                     item_desc,
                     item_id,
                     0,
                     0,
                     0,
                     item_capacity,
                     pnl_mst_id
            UNION ALL
            SELECT 3 sl,                               -- 2016-2023
                   lev3.name item_desc,
                   lev3.id item_id,
                   0 sales_month,
                   0 year_n,
                   0 sales_year,
                   m.capacity item_capacity,
                   CASE 
                       WHEN m.level2_setup_id = 101 THEN 0
                       ELSE d.qty
                   END qty_pcs,
                   CASE    WHEN 
                    m.level2_setup_id = 101 THEN d.qty / 1000
                       ELSE d.qty * m.capacity / 1000
                   END qty_mt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 0,
                 TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id
        )
        ORDER BY sl,year_n,sales_month,item_capacity DESC NULLS LAST;
        --------------------------------------------------------------------------------
        CURSOR ebitda_amt 
        IS
        SELECT sl,
               item_desc,
               item_id,
               sales_month,
               year_n,
               sales_year,
               item_capacity,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev3.name item_desc,
               lev3.id item_id,
               0 sales_month,
               d.fiscal_year year_n,
               d.period sales_year,
               m.capacity item_capacity,
               -1 * d.amount amt_bdt,
               -1 * d.amount / ROUND(NULLIF(d.qty,0) * m.capacity / 1000) bdt_pmt,
               -1 * d.amount / ROUND(NULLIF(d.qty,0) * m.capacity / 1000) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               m.pnl_mst_id,
               m.signed_operator
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                        -- current month
        SELECT 1 sl,
               lev3.name item_desc,
               lev3.id item_id,
               month_n sales_month,
               CASE 
                   WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                   WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
               END year_n,
               month||' - '||year_n sales_year,
               m.capacity item_capacity,
               sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
               sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
               sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               m.pnl_mst_id,
               m.signed_operator
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        UNION ALL                                                        -- CFY
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1,item_id) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1,item_id) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM (
            SELECT 2 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 year_n,
                 TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id,
                 signed_operator
        UNION ALL                                         --- YTD  (FAISAL)
        SELECT sl,
               item_desc,
               item_id,
               0 sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               item_capacity,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1, item_id) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty_itm_wise(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1, item_id) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id,
               signed_operator
        FROM (
            SELECT 3 sl,                               
                   lev3.name item_desc,
                   lev3.id item_id,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   m.capacity item_capacity,
                   -1 * d.amount amt_bdt,
                   -1 * d.amount / (NULLIF(d.qty,0) * m.capacity / 1000) bdt_pmt,
                   -1 * d.amount / (NULLIF(d.qty,0) * m.capacity / 1000) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
            UNION ALL                                        
            SELECT 3 sl,
                   lev3.name item_desc,
                   lev3.id item_id,
                   month_n sales_month,
                   CASE 
                       WHEN (month_n >= 7 AND month_n <= 12) THEN year_n + 1
                       WHEN (month_n >= 0 AND month_n <= 6)  THEN year_n 
                   END year_n,
                   month||' - '||year_n sales_year,
                   m.capacity item_capacity,
                   sales_supp.get_ebitda_sales_amount(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) amt_bdt,  
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) bdt_pmt,
                   sales_supp.get_ebitda_sales_bdt_pmt(m.level2_setup_id,this_year.month||'-'||this_year.year_n,NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
                   m.pnl_mst_id,
                   m.signed_operator   
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND level2_setup_id IN (101,102.1,102.2,102.3,102.4,102.5,102.6) 
        )
        GROUP BY sl,
                 item_desc,
                 item_id,
                 0,
                 0,
                 TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
                 item_capacity,
                 pnl_mst_id,
                 signed_operator
        )
        ORDER BY sl,year_n,sales_month,item_capacity DESC NULLS LAST;
        
        -----------------------------------------------------------------------------
        
        CURSOR ebitda_deduction_heads
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2001 AND 3009
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2001 AND 3009
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 3009
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2001 AND 3009
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 3009
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_tolling_revenue
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1003
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 1003
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1003
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1003
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1003
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_other_income
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 7001 AND 7007
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 7001 AND 7007
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 7001 AND 7007
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 7001 AND 7007
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 7001 AND 7007
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_vat
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1004
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 1004
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id               
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1004
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1004
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1004
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_sales_comm
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1005
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 1005
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1005
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1005
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1005
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_less_sales_discnt
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 1007
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 1007
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1007
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 1007
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 1007
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_rm_cost
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 2001
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 2001
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 2001
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 2001
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 2001
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_foh_cost
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2002 AND 2015
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2002 AND 2015
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2002 AND 2015
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2002 AND 2015
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2002 AND 2015
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_cogs
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 2001 AND 2015
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 2001 AND 2015
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 2015
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 2001 AND 2015
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 2001 AND 2015
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
        CURSOR ebitda_sell_admin_oh 
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id BETWEEN 3001 AND 3009
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id BETWEEN 3001 AND 3009
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 3001 AND 3009
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id BETWEEN 3001 AND 3009
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id BETWEEN 3001 AND 3009
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        ---------------------------------------------------------------        
        CURSOR ebitda_berc_price
        IS
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               year_n,
               sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               amt_bdt,
               bdt_pmt,
               usd_pmt,
               pnl_mst_id
        FROM 
        (
        SELECT 0 sl,                               -- 2016-2023
               lev1.name lev1,
               lev3.name lev3,
               0 sales_month,
               d.fiscal_year year_n,
               TO_CHAR(d.period) sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               0 month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                   ELSE d.amount 
               END amt_bdt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM gl_ebitda_mst m,
             gl_ebitda_setup lev1,
             gl_ebitda_setup lev2,
             gl_ebitda_setup lev3,
             (
             SELECT pnl_mst_id,
                    fiscal_year,
                    from_date,
                    to_date,
                    amount,
                    qty,
                    period
             FROM gl_ebitda_prev_amt
             WHERE from_date >= in_start_date
             AND to_date <= in_end_date
             ) d
        WHERE m.pnl_mst_id = d.pnl_mst_id
        AND m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id
        AND m.company_id = NVL(in_company_id,m.company_id)
        AND m.branch_id =NVL(in_branch_id,m.branch_id)
        AND m.level3_setup_id = 8001
        UNION ALL                                        -- current month
        SELECT 1 sl,                               
               lev1.name lev1,
               lev3.name lev3,
               month_n sales_month,
               TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
               month||' - '||year sales_year,
               lev1.serial level1_serial,
               lev2.serial level2_serial,
               m.signed_operator,
               m.level3_setup_id,
               month_n month_n,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
               END bdt_amt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
               END bdt_pmt,
               CASE 
                   WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
               END usd_pmt,
               m.pnl_mst_id
        FROM(
            SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                   TO_CHAR(D,'MON') AS MONTH,
                   EXTRACT(YEAR FROM d) AS YEAR_N,
                   EXTRACT(YEAR FROM d) AS YEAR
            FROM (
                SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                FROM DUAL
                CONNECT BY
                ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            )
            WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
            ) this_year,
            gl_ebitda_mst m,
            gl_ebitda_setup lev1,
            gl_ebitda_setup lev2,
            gl_ebitda_setup lev3
        WHERE m.level1_setup_id = lev1.id
        AND m.level2_setup_id = lev2.id
        AND m.level3_setup_id = lev3.id     
        AND m.company_id = NVL(in_company_id, m.company_id)
        AND m.branch_id = NVL(in_branch_id, m.branch_id)
        AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
        AND m.level3_setup_id = 8001
        UNION ALL                                            -- CFY
        SELECT sl,
               lev1,
               lev3,
               0 sales_month,
               year_n,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0 month_n,
               SUM(bdt_amt) bdt_amt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(bdt_amt) / acc_supp.get_ebitda_mt_qty(acc_supp.get_fiscal_year_start_date(in_end_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM (
            SELECT 2 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   month_n sales_month,
                   TO_NUMBER(TO_CHAR(TO_DATE(in_end_date), 'RRRR')) year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   month_n month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 8001
        )
        GROUP BY sl,
               lev1,
               lev3,
               0,
               TO_CHAR((acc_supp.get_fiscal_year_start_date(in_end_date)) , 'MON-RRRR') ||' TO '||TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               year_n,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               0,
               pnl_mst_id
        UNION ALL                                                    ---- YTD
        SELECT sl,
               lev1,
               lev3,
               sales_month,
               0 year_n,
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR') sales_year,
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               SUM(amt_bdt) amt_bdt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) bdt_pmt,
               SUM(amt_bdt) / acc_supp.get_ebitda_mt_qty(TO_DATE(in_start_date), TRUNC(SYSDATE, 'MM')-1) / acc_supp.ebitda_usd_exchange_rate usd_pmt,
               pnl_mst_id
        FROM 
            (
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   d.fiscal_year year_n,
                   d.period sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount 
                       ELSE d.amount 
                   END amt_bdt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date)
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                       ELSE d.amount / acc_supp.get_ebitda_mt_qty(d.from_date, d.to_date) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM gl_ebitda_mst m,
                 gl_ebitda_setup lev1,
                 gl_ebitda_setup lev2,
                 gl_ebitda_setup lev3,
                 (
                 SELECT pnl_mst_id,
                        fiscal_year,
                        from_date,
                        to_date,
                        amount,
                        qty,
                        period
                 FROM gl_ebitda_prev_amt
                 WHERE from_date >= in_start_date
                 AND to_date <= in_end_date
                 ) d
            WHERE m.pnl_mst_id = d.pnl_mst_id
            AND m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id
            AND m.company_id = NVL(in_company_id,m.company_id)
            AND m.branch_id =NVL(in_branch_id,m.branch_id)
            AND m.level3_setup_id = 8001
            UNION ALL                                        
            SELECT 3 sl,                               
                   lev1.name lev1,
                   lev3.name lev3,
                   0 sales_month,
                   0 year_n,
                   month||' - '||year sales_year,
                   lev1.serial level1_serial,
                   lev2.serial level2_serial,
                   m.signed_operator,
                   m.level3_setup_id,
                   0 month_n,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))
                   END bdt_amt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id))  / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year)))
                   END bdt_pmt,
                   CASE 
                       WHEN NVL(m.signed_operator,'##') = '-' THEN -1 * acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                       ELSE acc_supp.get_trial_balance_ebitda (m.pnl_mst_id, this_year.month||'-'||this_year.year , 5, NVL(in_company_id, m.company_id), NVL(in_branch_id, m.branch_id)) / acc_supp.get_ebitda_mt_qty(TO_DATE('01-'||month||'-'||year), LAST_DAY(TO_DATE('01-'||month||'-'||year))) / acc_supp.ebitda_usd_exchange_rate
                   END usd_pmt,
                   m.pnl_mst_id
            FROM(
                SELECT EXTRACT(MONTH FROM d) AS MONTH_N,
                       TO_CHAR(D,'MON') AS MONTH,
                       EXTRACT(YEAR FROM d) AS YEAR_N,
                       EXTRACT(YEAR FROM d) AS YEAR
                FROM (
                    SELECT ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) d
                    FROM DUAL
                    CONNECT BY
                    ADD_MONTHS(TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)), LEVEL - 1) <= TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                )
                WHERE TO_DATE(acc_supp.get_fiscal_year_start_date(in_end_date)) < TO_DATE(CASE WHEN TO_DATE(in_end_date) > SYSDATE THEN TRUNC(SYSDATE,'MM')-1 ELSE TO_DATE(in_end_date) END )
                ) this_year,
                gl_ebitda_mst m,
                gl_ebitda_setup lev1,
                gl_ebitda_setup lev2,
                gl_ebitda_setup lev3
            WHERE m.level1_setup_id = lev1.id
            AND m.level2_setup_id = lev2.id
            AND m.level3_setup_id = lev3.id     
            AND m.company_id = NVL(in_company_id, m.company_id)
            AND m.branch_id = NVL(in_branch_id, m.branch_id)
            AND in_end_date >= prev_fiscal_year_last_date --curr_fiscal_year_last_date
            AND m.level3_setup_id = 8001
            )
        GROUP BY  sl,
               lev1,
               lev3,
               sales_month,
               '0',
               TO_CHAR(TO_DATE(in_start_date), 'MON-RRRR') ||' TO '|| TO_CHAR((TRUNC(SYSDATE, 'MM')-1),'MON-RRRR'),
               level1_serial,
               level2_serial,
               signed_operator,
               level3_setup_id,
               month_n,
               pnl_mst_id
        )
        ORDER BY sl, month_n;
        
    BEGIN
        FOR m IN ebitda_qty LOOP
            INSERT INTO gl_ebitda_qty (
                sl,
                item_desc,
                item_id,
                sales_month,
                year_n,
                sales_year,
                item_capacity,
                qty_pcs,
                qty_mt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                m.sl,
                m.item_desc,
                m.item_id,
                m.sales_month,
                m.year_n,
                m.sales_year,
                m.item_capacity,
                m.qty_pcs,
                m.qty_mt,
                in_company_id,
                in_branch_id,
                m.pnl_mst_id
            );
        END LOOP;
        
        FOR n IN ebitda_amt LOOP
            INSERT INTO gl_ebitda_amt (
                sl,
                item_desc,
                item_id,
                sales_month,
                year_n,
                sales_year,
                item_capacity,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id,
                signed_operator
            )
            VALUES (
                n.sl,
                n.item_desc,
                n.item_id,
                n.sales_month,
                n.year_n,
                n.sales_year,
                n.item_capacity,
                n.amt_bdt,
                n.bdt_pmt,
                n.usd_pmt,
                in_company_id,
                in_branch_id,
                n.pnl_mst_id,
                n.signed_operator
            );
        END LOOP;
        
        
        FOR r IN ebitda_deduction_heads LOOP 
            INSERT INTO gl_ebitda_deduction_heads (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                r.sl,
                r.lev1,
                r.lev3,
                r.sales_month,
                r.year_n,
                r.sales_year,
                r.level1_serial,
                r.level2_serial,
                r.signed_operator,
                r.level3_setup_id,
                r.month_n,
                r.amt_bdt,
                r.bdt_pmt,
                r.usd_pmt,
                in_company_id,
                in_branch_id,
                r.pnl_mst_id
            );
            
        END LOOP;
        
        FOR p IN ebitda_tolling_revenue LOOP
            INSERT INTO gl_ebitda_tolling_revenue (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                p.sl,
                p.lev1,
                p.lev3,
                p.sales_month,
                p.year_n,
                p.sales_year,
                p.level1_serial,
                p.level2_serial,
                p.signed_operator,
                p.level3_setup_id,
                p.month_n,
                p.amt_bdt,
                p.bdt_pmt,
                p.usd_pmt,
                in_company_id,
                in_branch_id,
                p.pnl_mst_id
            );
        END LOOP;
        
        FOR q IN ebitda_other_income LOOP
            INSERT INTO gl_ebitda_other_income (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                q.sl,
                q.lev1,
                q.lev3,
                q.sales_month,
                q.year_n,
                q.sales_year,
                q.level1_serial,
                q.level2_serial,
                q.signed_operator,
                q.level3_setup_id,
                q.month_n,
                q.amt_bdt,
                q.bdt_pmt,
                q.usd_pmt,
                in_company_id,
                in_branch_id,
                q.pnl_mst_id
            );
        END LOOP;
        
        FOR a IN ebitda_less_vat LOOP
            INSERT INTO gl_ebitda_less_vat (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                a.sl,
                a.lev1,
                a.lev3,
                a.sales_month,
                a.year_n,
                a.sales_year,
                a.level1_serial,
                a.level2_serial,
                a.signed_operator,
                a.level3_setup_id,
                a.month_n,
                a.amt_bdt,
                a.bdt_pmt,
                a.usd_pmt,
                in_company_id,
                in_branch_id,
                a.pnl_mst_id
            );
        END LOOP;
        
        FOR b IN ebitda_less_sales_comm LOOP
            INSERT INTO gl_ebitda_less_sales_com (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                b.sl,
                b.lev1,
                b.lev3,
                b.sales_month,
                b.year_n,
                b.sales_year,
                b.level1_serial,
                b.level2_serial,
                b.signed_operator,
                b.level3_setup_id,
                b.month_n,
                b.amt_bdt,
                b.bdt_pmt,
                b.usd_pmt,
                in_company_id,
                in_branch_id,
                b.pnl_mst_id
            );
        END LOOP;
        
        
        FOR c IN ebitda_less_sales_discnt LOOP
            INSERT INTO gl_ebitda_less_sales_discnt (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                c.sl,
                c.lev1,
                c.lev3,
                c.sales_month,
                c.year_n,
                c.sales_year,
                c.level1_serial,
                c.level2_serial,
                c.signed_operator,
                c.level3_setup_id,
                c.month_n,
                c.amt_bdt,
                c.bdt_pmt,
                c.usd_pmt,
                in_company_id,
                in_branch_id,
                c.pnl_mst_id
            );
        END LOOP;
        
        FOR d IN ebitda_rm_cost LOOP
            INSERT INTO gl_ebitda_rm_cost (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                d.sl,
                d.lev1,
                d.lev3,
                d.sales_month,
                d.year_n,
                d.sales_year,
                d.level1_serial,
                d.level2_serial,
                d.signed_operator,
                d.level3_setup_id,
                d.month_n,
                d.amt_bdt,
                d.bdt_pmt,
                d.usd_pmt,
                in_company_id,
                in_branch_id,
                d.pnl_mst_id
            );
        END LOOP;
        
        
        
        FOR e IN ebitda_foh_cost LOOP
            INSERT INTO gl_ebitda_foh_cost (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                e.sl,
                e.lev1,
                e.lev3,
                e.sales_month,
                e.year_n,
                e.sales_year,
                e.level1_serial,
                e.level2_serial,
                e.signed_operator,
                e.level3_setup_id,
                e.month_n,
                e.amt_bdt,
                e.bdt_pmt,
                e.usd_pmt,
                in_company_id,
                in_branch_id,
                e.pnl_mst_id
            );
        END LOOP;
        
        FOR f IN ebitda_cogs LOOP
            INSERT INTO gl_ebitda_cogs (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                f.sl,
                f.lev1,
                f.lev3,
                f.sales_month,
                f.year_n,
                f.sales_year,
                f.level1_serial,
                f.level2_serial,
                f.signed_operator,
                f.level3_setup_id,
                f.month_n,
                f.amt_bdt,
                f.bdt_pmt,
                f.usd_pmt,
                in_company_id,
                in_branch_id,
                f.pnl_mst_id
            );
        END LOOP;
        
        FOR g IN ebitda_sell_admin_oh LOOP
            INSERT INTO gl_ebitda_sell_admin_oh (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                g.sl,
                g.lev1,
                g.lev3,
                g.sales_month,
                g.year_n,
                g.sales_year,
                g.level1_serial,
                g.level2_serial,
                g.signed_operator,
                g.level3_setup_id,
                g.month_n,
                g.amt_bdt,
                g.bdt_pmt,
                g.usd_pmt,
                in_company_id,
                in_branch_id,
                g.pnl_mst_id
            );
        END LOOP;
        
        
        FOR h IN ebitda_berc_price LOOP
            INSERT INTO gl_ebitda_berc_price (
                sl,
                lev1,
                lev3,
                sales_month,
                year_n,
                sales_year,
                level1_serial,
                level2_serial,
                signed_operator,
                level3_setup_id,
                month_n,
                amt_bdt,
                bdt_pmt,
                usd_pmt,
                company_id,
                branch_id,
                pnl_mst_id
            )
            VALUES (
                h.sl,
                h.lev1,
                h.lev3,
                h.sales_month,
                h.year_n,
                h.sales_year,
                h.level1_serial,
                h.level2_serial,
                h.signed_operator,
                h.level3_setup_id,
                h.month_n,
                h.amt_bdt,
                h.bdt_pmt,
                h.usd_pmt,
                in_company_id,
                in_branch_id,
                h.pnl_mst_id
            );
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    
    /*
        -- This procedure is added in scheduler for getting ebitda data.
           For making the report faster.
    */
    
    PROCEDURE populate_gl_ebitda_prev
    IS
        CURSOR branch
        IS
        SELECT company_no,
               branch_id
        FROM sys_branches
        WHERE active = 'Y';
        
        CURSOR c2 
        IS
        SELECT TO_DATE('01-JUL-2017') start_date,
               MAX(end_date)
        FROM gl_fiscal_year;
        
        l_start_date DATE;
        l_end_date DATE;
        l_prev_fiscal_year NUMBER;
    BEGIN
    
        SELECT fiscal_year
        INTO l_prev_fiscal_year
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        
        DELETE FROM gl_ebitda_prev_amt
        WHERE fiscal_year = l_prev_fiscal_year;
        COMMIT;
        
        DELETE FROM gl_ebitda_qty;
        DELETE FROM gl_ebitda_amt;
        DELETE FROM gl_ebitda_deduction_heads;
        DELETE FROM gl_ebitda_tolling_revenue;  
        DELETE FROM gl_ebitda_other_income;      
        DELETE FROM gl_ebitda_less_vat;           
        DELETE FROM gl_ebitda_less_sales_com;      
        DELETE FROM gl_ebitda_less_sales_discnt;  
        DELETE FROM gl_ebitda_rm_cost;        
        DELETE FROM gl_ebitda_foh_cost;         
        DELETE FROM gl_ebitda_cogs;         
        DELETE FROM gl_ebitda_sell_admin_oh;
        DELETE FROM gl_ebitda_berc_price;         
        
        COMMIT;
        
        OPEN c2;
            FETCH c2 INTO l_start_date, l_end_date;
        CLOSE c2;
        
        FOR m IN branch LOOP
            acc_supp.ins_gl_ebitda_prev (
                in_start_date    => l_start_date,
                in_end_date      => prev_fiscal_year_last_date,
                in_company_id    => m.company_no,
                in_branch_id     => m.branch_id
            );
        END LOOP;
        
        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
    -- Insertion of pervious data
    */
    
    PROCEDURE ins_gl_ebitda_prev_amt (
        in_pnl_mst_id    IN     NUMBER, 
        in_fiscal_year   IN     NUMBER, 
        in_from_date     IN     DATE, 
        in_to_date       IN     DATE, 
        in_amount        IN     NUMBER,
        in_qty           IN     NUMBER,
        in_period        IN     VARCHAR2
    )
    IS
        l_pnl_amt_id NUMBER;
        l_start_date DATE;
        l_end_date DATE;
    BEGIN
        SELECT NVL(MAX(pnl_amt_id),0)+1
        INTO l_pnl_amt_id
        FROM gl_ebitda_prev_amt;
        
        INSERT INTO gl_ebitda_prev_amt (
            pnl_amt_id, 
            pnl_mst_id, 
            fiscal_year, 
            from_date, 
            to_date, 
            amount,
            qty,
            created_by, 
            creation_date, 
            last_updated_by, 
            last_updated_date,
            period
        )
        VALUES (
            l_pnl_amt_id,
            in_pnl_mst_id,
            in_fiscal_year,
            in_from_date,
            in_to_date,
            in_amount,
            in_qty,
            NULL,
            NULL,
            NULL,
            NULL,
            in_period
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
     -- This procedure for inserting data in amt_prev table for last 
        fiscal year CFY
    */
    
    PROCEDURE ins_ebitda_amt_prev
    IS
        CURSOR c1
        IS
        SELECT pnl_mst_id,
               item_id,
               MAX(yearn) yearn,
               SUM(qty_pcs) qty_pcs,
               SUM(qty_mt) qty_mt,
               SUM(amt_bdt) amt_bdt,
               SUM(bdt_pmt) bdt_pmt,
               SUM(usd_pmt) usd_pmt
        FROM (
            SELECT DISTINCT pnl_mst_id,
                   item_id,
                   yearn,
                   qty_pcs,
                   qty_mt,
                   amt_bdt,
                   bdt_pmt,
                   usd_pmt
            FROM (
                SELECT pnl_mst_id,
                       item_id,
                       MAX(year_n) yearn,
                       SUM(NVL(qty_pcs,0)) qty_pcs,
                       SUM(NVL(qty_mt,0)) qty_mt,
                       0 amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_qty
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id, item_id
                UNION 
                SELECT pnl_mst_id,
                       item_id,
                       MAX(year_n) yearn,
                       0 qty_pcs,
                       0 qty_mt,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_amt
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id, item_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_deduction_heads
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_tolling_revenue
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_other_income
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_less_vat
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_less_sales_com
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_less_sales_discnt
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_rm_cost
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_foh_cost
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_cogs
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_sell_admin_oh
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
                UNION
                SELECT pnl_mst_id,
                       0,
                       MAX(year_n) yearn,
                       0,
                       0,
                       SUM(CASE 
                            WHEN signed_operator = '-' THEN -1 * NVL(amt_bdt,0)
                            ELSE NVL(amt_bdt,0)
                       END) amt_bdt,
                       0 bdt_pmt,
                       0 usd_pmt
                FROM gl_ebitda_berc_price
                WHERE sales_month <> 0
                GROUP BY pnl_mst_id
            )
         )
        GROUP BY pnl_mst_id, item_id
        ORDER BY pnl_mst_id,item_id;
        
        l_start_date DATE;
        l_end_date DATE;
        l_prev_fiscal_year NUMBER;
        l_qty NUMBER;
    BEGIN
        
        SELECT fiscal_year
        INTO l_prev_fiscal_year
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        
        DELETE FROM gl_ebitda_prev_amt
        WHERE fiscal_year = l_prev_fiscal_year;
        COMMIT;
        
        FOR i IN c1 LOOP
            SELECT start_date,
                   end_date
            INTO l_start_date,
                 l_end_date
            FROM gl_fiscal_year
            WHERE fiscal_year = i.yearn;
            
            IF i.item_id = 1001 THEN
                l_qty := i.qty_mt;
            ELSE
                l_qty := i.qty_pcs;
            END IF;
            
            ins_gl_ebitda_prev_amt (
                in_pnl_mst_id    => i.pnl_mst_id, 
                in_fiscal_year   => i.yearn, 
                in_from_date     => l_start_date, 
                in_to_date       => l_end_date, 
                in_amount        => i.amt_bdt,
                in_qty           => i.qty_pcs,
                in_period        => TO_CHAR(l_start_date , 'MON-RRRR') || ' TO '|| TO_CHAR(l_end_date , 'MON-RRRR')
            );
            
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE pnl_ebitda_job_scheduler
    IS
        CURSOR c1
        IS
        SELECT status
        FROM gl_fiscal_year
        WHERE year_ind = 'P';
        
        l_status VARCHAR2(10);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_status;
        CLOSE c1;
        
        IF l_status = 0 THEN
            populate_gl_profit_loss;
            populate_gl_ebitda;
        ELSIF l_status = 1 THEN
            IF TO_CHAR(SYSDATE, 'MON') = 'JUL' THEN
                populate_gl_profit_loss_prev;
                populate_gl_ebitda_prev;
            ELSE
                populate_gl_profit_loss_prev;
                populate_gl_profit_loss;
                populate_gl_ebitda_prev;
                populate_gl_ebitda;
            END IF;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
     PROCEDURE ar_loan_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    )
    IS
        company    NUMBER := in_company_id;
        branch     VARCHAR(20) := in_branch_id;
        batchid    NUMBER;
        v_id       NUMBER;
        v_no       NUMBER;
        acc_date   DATE;
        v_date     DATE;
        v_type     VARCHAR2(10);
        l_code VARCHAR2(50);
        l_text VARCHAR2(500);
        l_cnt NUMBER;
    BEGIN
        IF gl_v_id IS NULL THEN
            SELECT gl_voucher_id_s.NEXTVAL 
            INTO v_id 
            FROM DUAL;
            
          SELECT approved_date,deposit_date,
                 in_company_id, 
                 'BRV'
            INTO acc_date,v_date,
                 company, 
                 v_type
            FROM inv_sales_collection
            WHERE collection_id = do_id;

            v_no:=get_voucher_no (v_date,v_type,company,branch) ;
        ELSE
            v_id:=gl_v_id;
        END IF;
        
        IF gl_v_id IS NULL THEN
            INSERT INTO gl_vouchers (
                voucher_id, 
                voucher_type, 
                voucher_no, 
                voucher_date,
                description, 
                batch_id, 
                created_by, 
                creation_date,
                last_updated_by, 
                last_updated_date, 
                status,
                approved_by, 
                approval_date,
                module, 
                module_doc, 
                module_doc_id, 
                company_id, 
                branch_id,
                reference_no , 
                receive_type, 
                receive_from_id, 
                receive_from , 
                cheked_by, 
                checked_date 
            )
            SELECT v_id, 
                   'BRV', 
                   v_no, 
                   v_date, 
                   'Entry Against Loan # '|| r.collection_no, 
                   batchid, 
                   user_id, 
                   SYSDATE,
                   user_id, 
                   acc_date, 
                   'APPROVED',
                   user_id, 
                   SYSDATE,
                   'AR',
                   'COLL_APPROVE', 
                   r.collection_id, 
                   company, 
                   branch, 
                   r.collection_no , 
                   '09' , 
                   r.customer_id , 
                   '01' , 
                   user_id , 
                   SYSDATE
            FROM inv_sales_collection r    
            WHERE r.collection_id = do_id
            and collection_type='LOAN';
        END IF;
        
        INSERT INTO gl_voucher_accounts (
            voucher_account_id, 
            voucher_id, 
            account_id, 
            debit, 
            credit,
            naration, 
            created_by, 
            creation_date, 
            last_updated_by,
            last_update_date, 
            reference_id
        )
        SELECT gl_voucher_account_id_s.NEXTVAL, 
               v_id, 
               receiveable_account_id, 
               debit,
               credit, 
               naration, 
               user_id, 
               SYSDATE, 
               NULL, 
               NULL, 
               sales_order_id
        FROM ar_collection_transfer_v
        WHERE sales_order_id = do_id
        AND branch_id = in_branch_id;
        
        UPDATE inv_sales_collection
        SET    gl_voucher_id = v_id
        WHERE  collection_id = do_id;
        
        gbl_supp.send_sms_during_do (
            in_do_id   => do_id
        );
        
        COMMIT;
        
        SELECT NVL(COUNT(1),0)
        INTO l_cnt
        FROM ar_collection_bank_charge
        WHERE sales_order_id = do_id;
        
        IF l_cnt > 0 THEN
        
            acc_supp.ar_collection_bank_charge_trn (
                do_id            => do_id,
                user_id          => user_id,
                gl_v_id          => gl_v_id,
                in_company_id    => in_company_id,
                in_branch_id     => in_branch_id,
                out_error_code   => l_code,
                out_error_text   => l_text
            );
            
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;

END acc_supp;
/
