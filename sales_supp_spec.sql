CREATE OR REPLACE PACKAGE sales_supp
IS  
    /*
    -- Sales Support       
    */  
    FUNCTION get_customer_security_rate (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    
    FUNCTION get_cust_type_wise_item_rate (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_cust_type_wise_vat1 (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_cust_type_wise_vat2 (
        in_customer_type IN VARCHAR2,
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE sales_rate_update (
        in_date IN DATE,
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    );
    
    PROCEDURE sales_table_log_write (
        in_date IN DATE
    );
    
    PROCEDURE ins_sales_data;
    
    PROCEDURE ins_production_data;
    
    PROCEDURE sync_customer_amt_balance (
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    );
    
    FUNCTION get_own_stock (
        in_company_id  IN NUMBER,
        in_branch_id   IN VARCHAR2,
        in_location_id IN NUMBER,
        in_customer_id IN NUMBER,
        in_item_id     IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_customer_stock (
        in_company_id  IN NUMBER,
        in_branch_id   IN VARCHAR2,
        in_location_id IN NUMBER,
        in_customer_id IN NUMBER,
        in_item_id     IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE sales_rate_correction (
        in_prev_month_year IN VARCHAR2,
        in_curr_month_year IN VARCHAR2,
        in_company_id      IN NUMBER,
        in_branch_id       IN VARCHAR2
    );
    
    FUNCTION get_customer_pkg_qty (
        in_company_id   IN  NUMBER,
        in_branch_id    IN  VARCHAR2,
        in_customer_id  IN  NUMBER,
        in_item_id      IN  NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE customer_to_customer_transfer (
        in_location_id IN NUMBER,  -- location id from where we want to sell (FG Store ID)
        in_customer_id IN NUMBER,  -- new customer id to whom we want to transfer
        old_customer_id IN NUMBER,  -- old customer id from whom we want to transfer
        out_error_code OUT VARCHAR2,
        out_error_text OUT VARCHAR2
    );
    
    FUNCTION check_dc_admin (
        in_user_id   IN   NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION chk_dc_date_bypass (
        in_location_id   IN   NUMBER
    ) RETURN VARCHAR2;
    
    PROCEDURE sales_rate_correct_same_month (
        in_month_year    IN   VARCHAR2  
    );
    
    FUNCTION cust_credit_limit(
        p_customer_id       IN          NUMBER,
        p_comp              IN          VARCHAR2,
        p_branch            IN          VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION check_do_admin (
        in_user_id   IN   NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_bulk_sales_qty (
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_cylinder_sales_qty (
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_bulk_sales_cfy (
        in_to_date     IN  DATE,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_cylinder_sales_cfy (
        in_to_date     IN  DATE,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_ebitda_sales_qty_pcs (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_ebitda_sales_qty_kgs (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_ebitda_sales_amount (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_ebitda_sales_bdt_pmt (
        in_level_id    IN  NUMBER,
        in_month_year  IN  VARCHAR2,
        in_company_id  IN  NUMBER,
        in_branch_id   IN  VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_suspense_rate (
        in_item_id IN NUMBER
    ) RETURN NUMBER;
    
    FUNCTION chk_suspense_rate (
        in_sale_order_item_id IN NUMBER
    ) RETURN NUMBER;
    
    PROCEDURE ins_transport_cost_auto_gas (
        in_rate         IN   NUMBER
    );
    
    FUNCTION get_customer_package_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_customer_target_refill_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_customer_actual_refill_qty (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_customer_monthly_score (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN NUMBER;
    
    FUNCTION get_customer_monthly_category (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_month_year   IN   VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_customer_category_range (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_customer_id  IN   NUMBER,
        in_start_date   IN   VARCHAR2,
        in_end_date     IN   VARCHAR2
    ) RETURN VARCHAR2;
    
    PROCEDURE ins_customer_cat_period (
        in_fiscal_year  IN    NUMBER,
        in_sector       IN    NUMBER
    );
    
    PROCEDURE ins_customer_cat_detail (
        in_company_id   IN   NUMBER,
        in_branch_id    IN   VARCHAR2,
        in_period_id    IN   NUMBER
    );
    
    PROCEDURE update_challan_reference (
        in_customer_id  IN   NUMBER,
        in_item_id      IN   NUMBER
    );
    
END sales_supp;
/
