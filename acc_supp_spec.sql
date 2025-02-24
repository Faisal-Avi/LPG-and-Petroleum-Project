CREATE OR REPLACE PACKAGE acc_supp
IS  
    FUNCTION get_adv_chk_draft_value (
        in_invoice_id    IN     NUMBER
    ) RETURN NUMBER;

    FUNCTION check_adv_payment_type (
        in_payment_term  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_invoice_avd_chk_amt (
        in_invoice_id    IN     NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE upd_ar_adv_cheque (
        in_invoice_id    IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE upd_ar_adv_cheque (
        in_cheque_no     IN     VARCHAR2,
        in_amount        IN     NUMBER
    );
    
    FUNCTION check_advance_cheque (
        in_dc_id         IN     NUMBER
    ) RETURN VARCHAR2;
    
    /*
     -- This voucher is generated when GRN 
    */
    
    PROCEDURE inv_grn_expense_voucher (
        in_grn_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    PROCEDURE inv_grn_voucher (
        g_id             IN     NUMBER,
        user_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    /*
     -- During Invoice Matching
    */
    
    PROCEDURE ap_invoice_expense_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    PROCEDURE ap_invoice_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    /*
     -- During Payment
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
    ) RETURN NUMBER;
    
    PROCEDURE ap_payment_transfer (
        pay_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    
    /*
    -- Consumption voucher during Delivery Challan
    */
    
    PROCEDURE ap_delivery_challan_transfer (
        in_dc_id         IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    /*
    -- During Sale Invoice 
    */
    
    PROCEDURE ar_invoice_transfer (
        in_inv_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
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
    );
    
    /*
    -- During AR Receipt
    */
    
    PROCEDURE ar_cheque_transfer (
        rec_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    /*
    -- During DO Approval Advance Payment Voucher will be generated
    */
    
    PROCEDURE ar_do_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE ar_do_bank_charge_trn (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    FUNCTION get_costing_exchange_rate (
        in_po_id         IN     NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_po_exchange_rate (
        in_po_id         IN     NUMBER
    ) RETURN NUMBER;
    
    FUNCTION po_exch_rate_from_inv (
        in_invoice_id    IN     NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_voucher_no (
        v_date           IN     DATE, 
        v_type           IN     VARCHAR2, 
        p_company               NUMBER, 
        p_branch                VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION check_export_in_dc (
        in_dc_id         IN     NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_invoice_account_id (
        in_dc_id         IN     NUMBER,
        in_item_id       IN     NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_trial_balance (
        in_pnl_mst_id    IN     NUMBER,
        in_month_year    IN     VARCHAR2,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER;
     
    FUNCTION get_fiscal_year_start_date (
        in_to_date       IN     DATE
    ) RETURN DATE;
    
    FUNCTION get_yearly_trial_balance (
        in_pnl_mst_id    IN     NUMBER,
        in_end_date      IN     DATE,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    
    
    PROCEDURE ins_gl_profit_loss_data (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    
    PROCEDURE populate_gl_profit_loss;
    
    
    FUNCTION get_net_sales_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_gross_sales_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_b4_interest_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_b4_dep_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_b4_inctx_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_after_inctx_cfy (
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    
    FUNCTION get_net_sales (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_gross_profit (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    
    FUNCTION get_profit_before_itd (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_before_di (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_profit_before_it (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    
    FUNCTION get_profit_after_it (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION ebitda_usd_exchange_rate 
    RETURN NUMBER;
     
    FUNCTION get_ebitda_mt_qty (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE
    ) RETURN NUMBER;
    
    PROCEDURE ins_gl_ebitda_data (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    PROCEDURE populate_gl_ebitda;
    
    FUNCTION get_ebitda_mt_qty_itm_wise (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_item_id       IN     NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE ap_suspense_vr_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE ap_lpg_transport_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    FUNCTION get_trial_balance_ebitda (
        in_pnl_mst_id    IN     NUMBER,
        in_month_year    IN     VARCHAR2,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER;
    
    
    FUNCTION get_periodical_start_date (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN DATE;
    
    FUNCTION get_periodical_end_date (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN DATE;
    
    FUNCTION get_ebitda_exchange_rate (
        in_year          IN     NUMBER,
        in_month         IN     NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_trial_bal_fourth_lev (
        in_fourth_lev_id IN     NUMBER,
        in_record_level  IN     NUMBER,
        in_as_on_date    IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER;
    
    FUNCTION get_3rd_lev_desc_frm_4th (
        in_4th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_3rd_lev_code_frm_4th (
        in_4th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_2nd_lev_desc_frm_3rd (
        in_3rd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_2nd_lev_code_frm_3rd (
        in_3rd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_1st_lev_desc_frm_2nd (
        in_2nd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_1st_lev_code_frm_2nd (
        in_2nd_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_ap_invoice_qty (
        in_grn_item_id      IN     NUMBER
    ) RETURN NUMBER;
    
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
    );
    
    FUNCTION get_4th_lev_desc_frm_5th (
        in_5th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_4th_lev_code_frm_5th (
        in_5th_lev_code  IN     VARCHAR2
    ) RETURN VARCHAR2;
    
    PROCEDURE upd_bank_serial_no (
        in_do_id         IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    /*
    -- During Collection Approval Voucher will be generated
    */
    
    PROCEDURE ar_collection_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE ar_collection_bank_charge_trn (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE upd_bank_serial_no_coll (
        in_do_id         IN     NUMBER,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    FUNCTION get_trial_balance_sum (
        in_coa_id        IN     NUMBER,
        in_date          IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;

    PROCEDURE iou_payment_transfer (
        in_iou_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    FUNCTION fund_position_today_amt (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION fund_position_unsettled_amt (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    PROCEDURE iou_payment_receive (
        in_iour_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE iou_payment_receive_reimb (
        in_iour_id        IN     NUMBER,
        in_user_id       IN     NUMBER,
        in_gl_v_id       IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    PROCEDURE ap_invoice_services_transfer (
        inv_id           IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
    
    FUNCTION fund_position_today_debit (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION fund_position_today_credit (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_iou_amount (
        in_iou_app_date  IN     DATE,
        in_gl_account_id IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION fund_position_today_debit_c (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION fund_position_today_credit_c (
        in_bank_id       IN     NUMBER,
        in_date          IN     DATE,
        in_branch_id     IN     VARCHAR2
    ) RETURN NUMBER;
    
    PROCEDURE ins_gl_fund_position (
        in_date          IN     DATE,
        in_company       IN     NUMBER,
        in_branch        IN     VARCHAR2
    );
    
    PROCEDURE ins_pnl_data_prev (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    PROCEDURE populate_gl_profit_loss_prev;
    
    FUNCTION curr_fiscal_year_last_date 
    RETURN DATE;
    
    PROCEDURE ins_gl_pnl_prev_amt (
        in_pnl_mst_id    IN     NUMBER, 
        in_fiscal_year   IN     NUMBER, 
        in_from_date     IN     DATE, 
        in_to_date       IN     DATE, 
        in_amount        IN     NUMBER,
        in_qty           IN     NUMBER
    );
    
    PROCEDURE ins_pnl_amt_prev;
    
    FUNCTION prev_fiscal_year_last_date
    RETURN DATE;
    
    FUNCTION get_trial_balance_prev (
        in_pnl_mst_id    IN     NUMBER,
        in_end_date      IN     DATE,
        in_record_level  IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2  
    ) RETURN NUMBER;

    PROCEDURE ins_gl_ebitda_prev (
        in_start_date    IN     DATE,
        in_end_date      IN     DATE,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2
    );
    
    PROCEDURE populate_gl_ebitda_prev;
    
    PROCEDURE ins_gl_ebitda_prev_amt (
        in_pnl_mst_id    IN     NUMBER, 
        in_fiscal_year   IN     NUMBER, 
        in_from_date     IN     DATE, 
        in_to_date       IN     DATE, 
        in_amount        IN     NUMBER,
        in_qty           IN     NUMBER,
        in_period        IN     VARCHAR2
    );
    
    PROCEDURE ins_ebitda_amt_prev;
    
    PROCEDURE pnl_ebitda_job_scheduler;
    
    PROCEDURE ar_loan_transfer (
        do_id            IN     NUMBER,
        user_id          IN     NUMBER,
        gl_v_id          IN     NUMBER,
        in_company_id    IN     NUMBER,
        in_branch_id     IN     VARCHAR2,
        out_error_code   OUT    VARCHAR2,
        out_error_text   OUT    VARCHAR2
    );
END acc_supp;
/
