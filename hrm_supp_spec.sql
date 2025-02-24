CREATE OR REPLACE PACKAGE hrm_supp
IS  
   
    FUNCTION get_kpi_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_general_evaluation_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_overall_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_overall_category (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_pdp_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER;
    
    FUNCTION get_pdp_category (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_graph_result (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2;
    
    PROCEDURE upd_emp_appraisal_mst (
        in_appraisal_mst_id      IN  NUMBER,
        in_user_id               IN  NUMBER,
        in_level_ind             IN  NUMBER,
        out_error_code           OUT VARCHAR2,
        out_error_text           OUT VARCHAR2
    ); 
    
    PROCEDURE ins_emp_appraisal_history (
        in_appraisal_mst_id      IN  NUMBER,
        in_present_user_id       IN  NUMBER,
        in_present_kpi_score     IN  NUMBER,
        in_present_ge_score      IN  NUMBER,
        in_present_overall_score IN  NUMBER,
        in_present_overall_cat   IN  VARCHAR2,
        in_appraisal_type        IN  VARCHAR2,
        in_level_ind             IN  NUMBER,
        out_error_code           OUT VARCHAR2,
        out_error_text           OUT VARCHAR2
    ) ;
    
    PROCEDURE p_count_table_data (
        in_appraisal_mst_id      IN  NUMBER,
        out_kpi_total_cnt        OUT NUMBER,
        out_kpi_given_cnt        OUT NUMBER,
        out_ge_total_cnt         OUT NUMBER,
        out_ge_given_cnt         OUT NUMBER
    );
    
    PROCEDURE upd_acitvity_mst_status (
        in_emp_id                IN  NUMBER,
        in_start_date            IN  DATE,
        in_end_date              IN  DATE
    );
    PROCEDURE attendance_entry(p_empid IN NUMBER
        , p_att_status IN VARCHAR2
        , p_unit IN NUMBER
        , p_latitude IN NUMBER
        , p_longitude IN NUMBER
    );
    
    
    PROCEDURE update_attendance_activity (
        in_attendance_id        IN  NUMBER,
        in_latitude             IN  NUMBER,
        in_longitude            IN  NUMBER,
        in_attendance_loc       IN  VARCHAR2
    );
    
    PROCEDURE ins_salary_breakups_datewise (
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2,
        out_error_code          OUT VARCHAR2,
        out_error_text          OUT VARCHAR2
    );
    
    PROCEDURE upd_salary_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    );
    
    PROCEDURE ins_sal_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    );
    
    PROCEDURE del_sal_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    );
    
    PROCEDURE del_sal_breakups_resign (
        in_emp_id               IN  NUMBER,
        in_date                 IN  DATE
    );

END hrm_supp;
/
