CREATE OR REPLACE PACKAGE inv_supp
IS  
    /*
    -- Inventory Support       
    */  
    
    FUNCTION get_current_stock (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_current_rate (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE upd_stock_balance (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_qty IN NUMBER,
        in_amount IN NUMBER,
        in_user_id IN NUMBER
    );
    
    PROCEDURE upd_stock_balance_trg (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_qty IN NUMBER,
        in_amount IN NUMBER,
        in_user_id IN NUMBER
    );
    
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
    );
    
    PROCEDURE ins_stock_balance (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER,
        in_user_id IN NUMBER
    );
    
    PROCEDURE pop_stock_balance (
        in_company_id IN NUMBER,
        in_item_id IN NUMBER,
        in_user_id IN NUMBER,
        in_item_main_category IN VARCHAR2
    );
    
    PROCEDURE pop_stock_balance_loc (
        in_company_id IN NUMBER,
        in_location_id IN NUMBER,
        in_user_id IN NUMBER
    );
    
    FUNCTION get_curr_stock_no_calc (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_curr_rate_no_calc (
        in_company_id IN NUMBER,
        in_branch_id IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_transfer_location (
        in_location_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE upd_wip_store (
        in_issue_id IN NUMBER,
        in_user_id IN NUMBER
    );
    
    PROCEDURE ins_indent_cs_from_pi (
        in_pi_id IN NUMBER,
        in_user_id IN NUMBER
    );
    
    FUNCTION check_wip_item (
        in_item_id IN NUMBER
    ) RETURN VARCHAR2;
    
    PROCEDURE sync_stock_balance;
    
    PROCEDURE sync_stock_balance_msg (
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    );
    
    PROCEDURE close_sale_order (
        in_challan_id IN NUMBER
    );
    
    FUNCTION get_rm_store_type_id RETURN NUMBER;
    
    FUNCTION get_wip_store_type_id RETURN NUMBER;
    
    FUNCTION get_damage_store_type_id RETURN NUMBER;
    
    FUNCTION get_scrap_store_type_id RETURN NUMBER;
    
    FUNCTION get_repair_store_type_id RETURN NUMBER;
    
    FUNCTION get_repair_store_id RETURN NUMBER;
    
    FUNCTION get_damage_store_id RETURN NUMBER;
    
    FUNCTION get_location_group_id RETURN VARCHAR2;
    
    FUNCTION get_transfer_item_id (
        in_item_id  IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION rate_calculation (
        in_company_id IN NUMBER,
        in_branch_id  IN VARCHAR2,
        in_location_id IN NUMBER,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE upd_challan_ref (
        in_loan_rec_id IN NUMBER,
        in_rigp_id IN NUMBER,
        in_vendor_id IN NUMBER,
        in_calling_time IN VARCHAR2,
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    );
    
    FUNCTION get_customer_security_rate (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE upd_customer_request (
        in_loan_rec_id  IN  NUMBER,
        out_error_code  OUT VARCHAR2,
        out_error_text  OUT VARCHAR2  
    );
    
    PROCEDURE handle_faulty_quantity (
        in_loan_rec_id  IN  NUMBER,
        out_error_code  OUT VARCHAR2,
        out_error_text  OUT VARCHAR2  
    );
    
    PROCEDURE close_replacement_request (
        in_request_id   IN  NUMBER,
        out_error_code  OUT NUMBER,
        out_error_text  OUT NUMBER
    );
    
    FUNCTION get_customer_stock_balance (
        in_customer_id    IN  NUMBER,
        in_item_id        IN  NUMBER,
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_transfer_type  IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_customer_scrap_stock (
        in_customer_id    IN  NUMBER,
        in_item_id        IN  NUMBER,
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER
    ) RETURN NUMBER;
    
    
    PROCEDURE ins_customer_request_hist (
        in_request_mst_id IN  NUMBER,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2
    );
    
    FUNCTION get_ttl_buffer_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_ttl_replace_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_ttl_repair_leakage_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_ttl_buffer_leakage_stock (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_item_id        IN  NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE close_leakage_request (
        in_request_id     IN  NUMBER,
        out_error_code    OUT NUMBER,
        out_error_text    OUT NUMBER
    );
    
    PROCEDURE ins_irn_for_scn (
        in_igp_id         IN  NUMBER,
        in_user_id        IN  NUMBER,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2  
    );

    PROCEDURE create_grn_for_scn (
        irnid             IN  inv_irns.irn_id%type,
        user_id           IN  NUMBER,
        company_id        IN  NUMBER, 
        branch_id         IN  VARCHAR2,
        out_error_code    OUT VARCHAR2,
        out_error_text    OUT VARCHAR2 
    );
    
    PROCEDURE prc_po_close (
        p_po_id inv_pos.po_id%type
    );
    
    PROCEDURE ins_inv_igp_checked (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_vendor_id      IN  NUMBER,
        in_user_id        IN  NUMBER
    );
    
    PROCEDURE ins_inv_igp_checked_s (
        in_company_id     IN  NUMBER,
        in_branch_id      IN  VARCHAR2,
        in_location_id    IN  NUMBER,
        in_vendor_id      IN  NUMBER,
        in_user_id        IN  NUMBER
    );
    
    PROCEDURE ins_indent_cs_from_pi (
        in_pi_id IN NUMBER,
        in_user_id IN NUMBER,
        out_error_code OUT VARCHAR2,
        out_error_msg OUT VARCHAR2
    );
    
    PROCEDURE ins_indent_cs_from_po (
        in_po_id IN NUMBER,
        in_user_id IN NUMBER,
        out_error_code OUT VARCHAR2,
        out_error_msg OUT VARCHAR2
    );
    
    PROCEDURE ins_irn_grn_from_igp (
        in_igp_id IN NUMBER
    );
    
END inv_supp;
/
