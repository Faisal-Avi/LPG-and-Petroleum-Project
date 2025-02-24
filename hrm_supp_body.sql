CREATE OR REPLACE PACKAGE BODY LPG_TEST.hrm_supp
IS  

    /*
    -- This function is created for getting KPI score during appraisal
    */

    FUNCTION get_kpi_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER
    IS  
        CURSOR c1
        IS
        SELECT SUM(weight) total_weight,
               SUM(calc_marks) total_obtained
        FROM hr_emp_appraisal_kpi
        WHERE master_id = in_appraisal_mst_id;
        
        l_total_weight NUMBER;
        l_total_obtained NUMBER;
        l_kpi_pct NUMBER; 
        
        l_kpi_score NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_total_weight, l_total_obtained;
        CLOSE c1;
        
        l_kpi_pct := ROUND(((l_total_obtained / NULLIF(l_total_weight,0) ) * 100),2);
        
        l_kpi_score :=  CASE 
                            WHEN l_kpi_pct = 100 THEN 5
                            WHEN l_kpi_pct BETWEEN 95 AND 99.99 THEN 4
                            WHEN l_kpi_pct BETWEEN 91 AND 94.99 THEN 3
                            WHEN l_kpi_pct BETWEEN 81 AND 90.99 THEN 2
                            WHEN l_kpi_pct BETWEEN  1 AND 80.99 THEN 1
                        END ;
                        
        RETURN l_kpi_score;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for getting General Evaluation score during appraisal
    */
    
    FUNCTION get_general_evaluation_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT SUM(obtained_marks) total_marks,
               COUNT(*) total_categories
        FROM hr_emp_appraisal_gen_evln
        WHERE master_id = in_appraisal_mst_id; 
          
        l_total_marks NUMBER;
        l_total_categories NUMBER;
        
        l_general_evaluation_score NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_total_marks, l_total_categories;
        CLOSE c1;
        l_general_evaluation_score := ROUND((l_total_marks / l_total_categories),2);
        
        RETURN l_general_evaluation_score;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for getting Overall score during appraisal
    */
    
    FUNCTION get_overall_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER
    IS
        l_kpi_score NUMBER;
        l_ge_score NUMBER;
        l_overall_score NUMBER;
    BEGIN
        l_kpi_score := get_kpi_score(in_appraisal_mst_id);
        l_ge_score := get_general_evaluation_score(in_appraisal_mst_id);
        
        l_overall_score := ROUND(((NVL(l_ge_score,0) +
                           NVL(l_kpi_score,0)) / 2),2) ;
                           
        RETURN l_overall_score;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for getting Overall category during appraisal
    */
    
    FUNCTION get_overall_category (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2
    IS
        l_overall_score NUMBER;
        l_overall_category VARCHAR2(100);
    BEGIN
        
        l_overall_score := get_overall_score(in_appraisal_mst_id);
    
        l_overall_category :=   CASE 
                                    WHEN l_overall_score BETWEEN 4 AND 5 THEN 'EXCEEDS EXPECTATION'
                                    WHEN l_overall_score BETWEEN 3 AND 3.99 THEN 'MEETS EXPECTATION'
                                    WHEN l_overall_score BETWEEN 2 AND 2.99 THEN 'IMPROVEMENT NEEDED'
                                    WHEN l_overall_score BETWEEN 0 AND 1.99 THEN 'UNACCEPTABLE'
                                END;
                                
        RETURN l_overall_category;
                                
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for getting pdp score passing appraisal master id
    */
    
    FUNCTION get_pdp_score (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN NUMBER
    IS
        CURSOR  c1
        IS
        SELECT SUM(obtained_marks) total_pdp_marks,
               COUNT(*) total_record
        FROM hr_emp_appraisal_pdp
        WHERE master_id = in_appraisal_mst_id;
        l_total_pdp_marks NUMBER := 0;
        l_rec_count NUMBER := 0;
        l_pdp_score NUMBER := 0;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_total_pdp_marks, l_rec_count;
        CLOSE c1;
        l_pdp_score := ROUND((l_total_pdp_marks / l_rec_count),2);
        
        RETURN l_pdp_score;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is written for getting pdp category
    */
    
    
    FUNCTION get_pdp_category (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2
    IS
        l_pdp_score NUMBER;
        l_pdp_category VARCHAR2(50);
    BEGIN
        l_pdp_score := get_pdp_score(in_appraisal_mst_id);
        
        l_pdp_category :=   CASE 
                                WHEN l_pdp_score BETWEEN 4 AND 5 THEN 'HIGH'
                                WHEN l_pdp_score BETWEEN 3 AND 3.99 THEN 'MODERATE'
                                WHEN l_pdp_score BETWEEN 0 AND 2.99 THEN 'LOW'
                            END;
       
        RETURN l_pdp_category;                    
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    --This function is for getting Graph result 
    */
    
    FUNCTION get_graph_result (
        in_appraisal_mst_id      IN  NUMBER
    ) RETURN VARCHAR2
    IS
        l_kpi_ge_category VARCHAR2(50);
        l_pdp_category VARCHAR2(50);
        l_graph_result VARCHAR2(500);
    BEGIN
        l_kpi_ge_category := get_overall_category(in_appraisal_mst_id);
        l_pdp_category := get_pdp_category(in_appraisal_mst_id);
        
        IF l_kpi_ge_category = 'IMPROVEMENT NEEDED' AND l_pdp_category = 'LOW' THEN
            l_graph_result := 'Risk (Low Potential/Low Performance)';
        ELSIF l_kpi_ge_category = 'IMPROVEMENT NEEDED' AND l_pdp_category = 'MODERATE' THEN
            l_graph_result := 'Inconsistent Player (Moderate Potential/Low Performance)';
        ELSIF l_kpi_ge_category = 'IMPROVEMENT NEEDED' AND l_pdp_category = 'HIGH' THEN
            l_graph_result := 'Potential Gem (High Potential/Low Performance)';
        ELSIF l_kpi_ge_category = 'MEETS EXPECTATION' AND l_pdp_category = 'LOW' THEN
            l_graph_result := 'Average Performer (Low Potential/Moderate Performance)';
        ELSIF l_kpi_ge_category = 'MEETS EXPECTATION' AND l_pdp_category = 'MODERATE' THEN
            l_graph_result := 'Core Player (Moderate Potential/Moderate Performance)';
        ELSIF l_kpi_ge_category = 'MEETS EXPECTATION' AND l_pdp_category = 'HIGH' THEN
            l_graph_result := 'High Potential (High Potential/Moderate Performance)';
        ELSIF l_kpi_ge_category = 'EXCEEDS EXPECTATION' AND l_pdp_category = 'LOW' THEN
            l_graph_result := 'Solid Performer (Low Potential/High Performance)';
        ELSIF l_kpi_ge_category = 'EXCEEDS EXPECTATION' AND l_pdp_category = 'MODERATE' THEN
            l_graph_result := 'High Performer (Moderate Potential/High Performance)';
        ELSIF l_kpi_ge_category = 'EXCEEDS EXPECTATION' AND l_pdp_category = 'HIGH' THEN
            l_graph_result := 'Star (High Potential/High Performance)';
        ELSE
            l_graph_result := 'Unacceptable';
        END IF;
        
        RETURN l_graph_result;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This procedure is for updating Appraisal Master table for different event
    */
    
    PROCEDURE upd_emp_appraisal_mst (
        in_appraisal_mst_id      IN  NUMBER,
        in_user_id               IN  NUMBER,
        in_level_ind             IN  NUMBER,
        out_error_code           OUT VARCHAR2,
        out_error_text           OUT VARCHAR2
    )
    IS 
    BEGIN
        IF in_level_ind = 1 THEN
            UPDATE hr_employee_appraisal_mst
            SET self_app_kpi_score = get_kpi_score(in_appraisal_mst_id),
                self_app_ge_score = get_general_evaluation_score(in_appraisal_mst_id),
                self_app_overall_score = get_overall_score(in_appraisal_mst_id),
                self_app_overall_cat = get_overall_category(in_appraisal_mst_id),
                self_app_by = in_user_id,
                self_app_by_name = gbl_supp.get_user_name(in_user_id),
                self_app_date = SYSDATE,
                level_ind = 1,
                status = 'SELF'
            WHERE id = in_appraisal_mst_id;
        ELSIF in_level_ind = 2 THEN
            UPDATE hr_employee_appraisal_mst
            SET supv_kpi_score = get_kpi_score(in_appraisal_mst_id),
                supv_app_ge_score = get_general_evaluation_score(in_appraisal_mst_id),
                supv_app_overall_score = get_overall_score(in_appraisal_mst_id),
                supv_app_overall_cat = get_overall_category(in_appraisal_mst_id),
                supv_app_by = in_user_id,
                supv_app_by_name = gbl_supp.get_user_name(in_user_id),
                supv_app_date = SYSDATE,
                level_ind = 2,
                status = 'SUPERVISOR'
            WHERE id = in_appraisal_mst_id;
        ELSIF in_level_ind = 3 THEN
            UPDATE hr_employee_appraisal_mst
            SET hod_kpi_score = get_kpi_score(in_appraisal_mst_id),
                hod_app_ge_score = get_general_evaluation_score(in_appraisal_mst_id),
                hod_app_overall_score = get_overall_score(in_appraisal_mst_id),
                hod_app_overall_cat = get_overall_category(in_appraisal_mst_id),
                hod_app_by = in_user_id,
                hod_app_by_name = gbl_supp.get_user_name(in_user_id),
                hod_app_date = SYSDATE,
                level_ind = 3,
                status = 'HOD'
            WHERE id = in_appraisal_mst_id;
        ELSIF in_level_ind = 4 THEN
            UPDATE hr_employee_appraisal_mst
            SET ceo_kpi_score = get_kpi_score(in_appraisal_mst_id),
                ceo_app_ge_score = get_general_evaluation_score(in_appraisal_mst_id),
                ceo_app_overall_score = get_overall_score(in_appraisal_mst_id),
                ceo_app_overall_cat = get_overall_category(in_appraisal_mst_id),
                ceo_app_by = in_user_id,
                ceo_app_by_name = gbl_supp.get_user_name(in_user_id),
                ceo_app_date = SYSDATE,
                level_ind = 4,
                status = 'MANAGEMENT'
            WHERE id = in_appraisal_mst_id;
            /*-----  FOR SMS SENDING
            DECLARE
                l_mobile_no VARCHAR2(20);
            BEGIN
                SELECT off_mobile_phone
                INTO l_mobile_no
                FROM hr_employee_v
                WHERE emp_id = (SELECT emp_id
                                FROM hr_employee_appraisal_mst
                                WHERE ID = in_appraisal_mst_id);
                gbl_supp.ins_gbl_sms_outgoing (
                    in_sms_text              => 'You appraisal is approved by Management',
                    in_masking_name          => 'BEXIMCOLPG',
                    in_receiver_no           => l_mobile_no,
                    in_created_by            => NULL,
                    in_ip_address            => NULL,
                    in_terminal              => NULL
                );
            EXCEPTION
                WHEN OTHERS THEN
                NULL;
            END;
            */
        ELSIF in_level_ind = 5 THEN
            UPDATE hr_employee_appraisal_mst
            SET hr_kpi_score = get_kpi_score(in_appraisal_mst_id),
                hr_app_ge_score = get_general_evaluation_score(in_appraisal_mst_id),
                hr_app_overall_score = get_overall_score(in_appraisal_mst_id),
                hr_app_overall_cat = get_overall_category(in_appraisal_mst_id),
                hr_app_by = in_user_id,
                hr_app_by_name = gbl_supp.get_user_name(in_user_id),
                hr_app_date = SYSDATE,
                level_ind = 5,
                status = 'HR'
            WHERE id = in_appraisal_mst_id;
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLCODE;
    END;    

    /*
    -- This procedure is created to maintain appraisal history
    */
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
    )
    IS
        CURSOR c1
        IS
        SELECT COUNT(*)
        FROM hr_emp_appraisal_mst_hist
        WHERE id = in_appraisal_mst_id
        AND level_ind = in_level_ind;
        
        l_mst_tbl_id NUMBER;
        
        l_cnt_level NUMBER := 0;
        
    BEGIN
        SELECT NVL(MAX(history_table_id),0)+1
        INTO l_mst_tbl_id
        FROM hr_emp_appraisal_mst_hist;
        
        OPEN c1;
            FETCH c1 INTO l_cnt_level;
        CLOSE c1;
        
        IF l_cnt_level = 0 THEN
        
            INSERT INTO hr_emp_appraisal_mst_hist (
                history_table_id, 
                id, 
                company_id, 
                company_name, 
                branch_id, 
                branch_name, 
                emp_id, 
                emp_no, 
                emp_name, 
                designation, 
                department, 
                grade, 
                joining_date, 
                time_in_position, 
                fiscal_year_id, 
                performance_period, 
                start_date, 
                end_date, 
                comments, 
                ip_address, 
                terminal, 
                last_updated_ip, 
                last_updated_terminal, 
                created_by, 
                created_date, 
                last_updated_by, 
                last_updated_date, 
                supervisor_name, 
                supervisor_id, 
                dm_or_upper_ind, 
                promotion_increment_type, 
                appraisee_comments, 
                supervisor_comments, 
                hod_comments, 
                hr_comments, 
                ceo_comments, 
                self_app_kpi_score, 
                self_app_ge_score, 
                self_app_overall_score, 
                self_app_overall_cat, 
                self_app_by, 
                self_app_date, 
                supv_kpi_score, 
                supv_app_ge_score, 
                supv_app_overall_score, 
                supv_app_overall_cat, 
                supv_app_by, 
                supv_app_date, 
                hod_kpi_score, 
                hod_app_ge_score, 
                hod_app_overall_score, 
                hod_app_overall_cat, 
                hod_app_by, 
                hod_app_date, 
                hr_kpi_score, 
                hr_app_ge_score, 
                hr_app_overall_score, 
                hr_app_overall_cat, 
                hr_app_by, 
                hr_app_date, 
                ceo_kpi_score, 
                ceo_app_ge_score, 
                ceo_app_overall_score, 
                ceo_app_overall_cat, 
                ceo_app_by, 
                ceo_app_date,
                appraisal_type,
                level_ind,
                position,
                pay_grade
            )
            SELECT  l_mst_tbl_id,
                    id, 
                    company_id, 
                    company_name, 
                    branch_id, 
                    branch_name, 
                    emp_id, 
                    emp_no, 
                    emp_name, 
                    designation, 
                    department, 
                    grade, 
                    joining_date, 
                    time_in_position, 
                    fiscal_year_id, 
                    performance_period, 
                    start_date, 
                    end_date, 
                    comments, 
                    ip_address, 
                    terminal, 
                    last_updated_ip, 
                    last_updated_terminal, 
                    created_by, 
                    created_date, 
                    last_updated_by, 
                    last_updated_date, 
                    supervisor_name, 
                    supervisor_id, 
                    dm_or_upper_ind, 
                    promotion_increment_type,
                    appraisee_comments, 
                    supervisor_comments, 
                    hod_comments, 
                    hr_comments, 
                    ceo_comments, 
                    self_app_kpi_score, 
                    self_app_ge_score, 
                    self_app_overall_score, 
                    self_app_overall_cat, 
                    self_app_by, 
                    self_app_date,
                    supv_kpi_score, 
                    supv_app_ge_score, 
                    supv_app_overall_score, 
                    supv_app_overall_cat, 
                    supv_app_by, 
                    supv_app_date, 
                    hod_kpi_score, 
                    hod_app_ge_score, 
                    hod_app_overall_score, 
                    hod_app_overall_cat, 
                    hod_app_by, 
                    hod_app_date, 
                    hr_kpi_score, 
                    hr_app_ge_score, 
                    hr_app_overall_score, 
                    hr_app_overall_cat, 
                    hr_app_by, 
                    hr_app_date, 
                    ceo_kpi_score, 
                    ceo_app_ge_score, 
                    ceo_app_overall_score, 
                    ceo_app_overall_cat, 
                    ceo_app_by, 
                    ceo_app_date,
                    in_appraisal_type,
                    in_level_ind,
                    position,
                    pay_grade
            FROM hr_employee_appraisal_mst
            WHERE id = in_appraisal_mst_id;
            
            INSERT INTO hr_emp_appraisal_gen_evln_hist (
                ge_hist_id, 
                hist_master_id,
                id,
                master_id, 
                general_evaluation_id, 
                general_evaluation_name, 
                obtained_marks, 
                ip_address, 
                terminal, 
                last_updated_ip, 
                last_updated_terminal, 
                created_by, 
                created_date, 
                last_updated_by, 
                last_updated_date
            )
            SELECT  seq_general_evaluation_hist.NEXTVAL,
                    l_mst_tbl_id,
                    id,
                    master_id,
                    general_evaluation_id,
                    general_evaluation_name,
                    obtained_marks,
                    ip_address,
                    terminal,
                    last_updated_ip,
                    last_updated_terminal,
                    created_by,
                    created_date,
                    last_updated_by,
                    last_updated_date
            FROM hr_emp_appraisal_gen_evln
            WHERE MASTER_ID = in_appraisal_mst_id;
            
            
            INSERT INTO hr_emp_appraisal_kpi_hist (
                kpi_hist_id,
                hist_master_id,
                id,
                master_id,
                objective_id,
                objective_description,
                objective_assign_date,
                objective_start_date,
                objective_end_date,
                weight,
                obtained_marks,
                calc_marks,
                ip_address,
                terminal,
                last_updated_ip,
                last_updated_terminal,
                created_by,
                created_date,
                last_updated_by,
                last_updated_date,
                possible_obstacles,
                evaluation_remarks,
                comments,
                activity_id,
                activity_desc,
                target,
                achieved
            )
            SELECT  seq_appraisal_kpi_hist.NEXTVAL,
                    l_mst_tbl_id,
                    id,
                    master_id,
                    objective_id,
                    objective_description,
                    objective_assign_date,
                    objective_start_date,
                    objective_end_date,
                    weight,
                    obtained_marks,
                    calc_marks,
                    ip_address,
                    terminal,
                    last_updated_ip,
                    last_updated_terminal,
                    created_by,
                    created_date,
                    last_updated_by,
                    last_updated_date,
                    possible_obstacles,
                    evaluation_remarks,
                    comments,
                    activity_id,
                    activity_desc,
                    target,
                    achieved
            FROM hr_emp_appraisal_kpi
            WHERE master_id = in_appraisal_mst_id;
            
            INSERT INTO hr_emp_appraisal_pdp_hist
            SELECT seq_personal_development_hist.NEXTVAL,
                   l_mst_tbl_id,
                   id, 
                   master_id, 
                   pdp_mst_id, 
                   pdp_desc, 
                   obtained_marks, 
                   ip_address, 
                   terminal, 
                   last_updated_ip, 
                   last_updated_terminal, 
                   created_by, 
                   created_date, 
                   last_updated_by, 
                   last_updated_date
            FROM hr_emp_appraisal_pdp
            WHERE master_id = in_appraisal_mst_id;

            COMMIT;
            
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLCODE;
    END;
    
    /*
    -- This procedure is for check general evaluation and kpi count
    */
    
    PROCEDURE p_count_table_data (
        in_appraisal_mst_id      IN  NUMBER,
        out_kpi_total_cnt        OUT NUMBER,
        out_kpi_given_cnt        OUT NUMBER,
        out_ge_total_cnt         OUT NUMBER,
        out_ge_given_cnt         OUT NUMBER
    )
    IS 
        CURSOR c1
        IS
        SELECT COUNT(*) ttl_kpi, 
               COUNT(obtained_marks) gvn_kpi 
        FROM hr_emp_appraisal_kpi
        WHERE master_id = in_appraisal_mst_id;
        
        CURSOR c2
        IS
        SELECT COUNT(*) ttl_ge, 
               COUNT(obtained_marks) gvn_ge
        FROM hr_emp_appraisal_gen_evln
        WHERE master_id = in_appraisal_mst_id;
        
        l_ttl_kpi NUMBER;
        l_gvn_kpi NUMBER;
        
        l_ttl_ge NUMBER;
        l_gvn_ge NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_ttl_kpi, l_gvn_kpi;
        CLOSE c1;
        
        OPEN c2;
            FETCH c2 INTO l_ttl_ge, l_gvn_ge;
        CLOSE c2;
        
        out_kpi_total_cnt  := l_ttl_kpi;
        out_kpi_given_cnt  := l_gvn_kpi;
        out_ge_total_cnt   := l_ttl_ge;
        out_ge_given_cnt   := l_gvn_ge;
        
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
    -- This procedure is for updating Activity Status of EMPLOYEE_ACTIVITY_TAB
    */
    
    PROCEDURE upd_acitvity_mst_status (
        in_emp_id                IN  NUMBER,
        in_start_date            IN  DATE,
        in_end_date              IN  DATE
    )
    IS
    BEGIN
        UPDATE employee_activity_tab
        SET status = 'CLOSED'
        WHERE emp_id = in_emp_id
        AND appraisal_start_date = in_start_date
        AND appraisal_end_date = in_end_date;
        
        UPDATE employee_objective_tab
        SET status = 'CLOSED'
        WHERE emp_id = in_emp_id
        AND objective_start_date = in_start_date
        AND objective_end_date = in_end_date;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END; 
    
    /*
    -- Human Resource Management Support     
    AUTHORE : 
    DATE    :
    Modified By:
    ===============
    NAME                    DATE        DESCRIPTION/COMMENTS
    Md. Rumman Alam         16/08/2023  Add a procedure named "attendance_entry" to track attandance time and location
      
    */
    
    PROCEDURE attendance_entry(
              p_empid           IN NUMBER
            , p_att_status      IN VARCHAR2
            , p_unit            IN NUMBER
            , p_latitude        IN NUMBER
            , p_longitude       IN NUMBER
    )
    IS
        l_attendance_id NUMBER;
        l_clob      clob;
        l_text      VARCHAR2(3999);
    BEGIN
        SELECT attendance_id_seq.nextval
        INTO l_attendance_id
        FROM dual;     
        BEGIN
      /*      l_clob := apex_web_service.make_rest_request(
                        p_url => 'http://192.168.188.126:8000/bex_lpg_api/get_location_name',
                        p_http_method => 'GET',
                        p_parm_name => apex_util.string_to_table('latitude:longitude'),
                        p_parm_value => apex_util.string_to_table(p_latitude||':'||p_longitude)
                    );  
      */
            SELECT SUBSTR(DBMS_LOB.substr(l_clob, 4000),1,INSTR(DBMS_LOB.substr(l_clob, 4000),'(',1)-1) 
            INTO l_text 
            FROM dual;  
            
        EXCEPTION
            WHEN OTHERS THEN
            NULL;
        END;
        
        INSERT INTO attendance_activity (
            attendance_id,
            attendance_date, 
            emp_id, 
            attendance_status, 
            unit_no, 
            latitude, 
            longitude, 
            attendance_loc
        )
        VALUES (
            l_attendance_id,
            SYSDATE,
            p_empid,
            p_att_status,
            p_unit,
            p_latitude,
            p_longitude,
            l_text
        );
    END attendance_entry;
    
    PROCEDURE update_attendance_activity (
        in_attendance_id        IN  NUMBER,
        in_latitude             IN  NUMBER,
        in_longitude            IN  NUMBER,
        in_attendance_loc       IN  VARCHAR2
    )
    IS
    BEGIN
        UPDATE attendance_activity
        SET attendance_loc = in_attendance_loc
        WHERE attendance_id = in_attendance_id
        AND longitude = in_longitude
        AND latitude = in_latitude;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
        -- This procedure is for inserting data in payroll breakbups datewise
    */
    
    PROCEDURE ins_salary_breakups_datewise (
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2,
        out_error_code          OUT VARCHAR2,
        out_error_text          OUT VARCHAR2
    )
    IS
        l_start_date DATE;
        l_end_date   DATE;
        
        CURSOR c1
        IS
        SELECT payroll_start,
               payroll_end
        FROM hr_company_periods
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND period_id = in_period_id
        AND closed = 'N';
        
        CURSOR c2
        IS
        WITH date_range AS (
        SELECT TO_DATE(l_start_date) AS start_date,
               TO_DATE(l_end_date) AS end_date
        FROM dual
        ),
        generated_dates AS (
        SELECT start_date + LEVEL - 1 AS generated_date
        FROM date_range
        CONNECT BY LEVEL <= (end_date - start_date + 1)
        )
        SELECT generated_date salary_date
        FROM generated_dates;
        
        CURSOR c3
        IS
        SELECT emp_id
        FROM hr_employees
        WHERE company_id = in_company_id
        AND branch_id = in_branch_id
        AND resign_date IS NULL;
        
        l_no_of_days NUMBER;
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_start_date, l_end_date;
        CLOSE c1;
        
        l_no_of_days := l_end_date - l_start_date + 1 ;
        
        FOR i IN c3 LOOP
            
            FOR j IN c2 LOOP
                FOR k IN (SELECT allowance_code,
                                 amount
                          FROM hr_emp_salary_breakups
                          WHERE emp_id = i.emp_id
                          ORDER BY allowance_code) 
                LOOP
                    INSERT INTO hr_emp_sal_breakups_datewise (
                        salary_date, 
                        emp_id, 
                        allowance_code, 
                        amount, 
                        posted,
                        period_id,
                        created_by, 
                        creation_date, 
                        last_updated_by, 
                        last_update_date
                    )
                    VALUES (
                        j.salary_date,
                        i.emp_id,
                        k.allowance_code,
                        k.amount / l_no_of_days,
                        'N',
                        in_period_id,
                        109,
                        SYSDATE,
                        NULL,
                        NULL
                    );
                END LOOP;
            END LOOP;
        END LOOP;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        out_error_code := SQLCODE;
        out_error_text := SQLERRM;
    END;
    
    PROCEDURE upd_salary_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    )
    IS
    BEGIN
        UPDATE hr_emp_sal_breakups_datewise
        SET amount = in_new_amount
        WHERE TRUNC(salary_date) >= TRUNC(in_effective_date)
        AND emp_id = in_emp_id
        AND allowance_code = in_tran_code
        AND period_id = in_period_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_sal_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    )
    IS
        l_start_date DATE;
        l_end_date   DATE;
        
        CURSOR c1
        IS
        WITH date_range AS (
        SELECT TO_DATE(l_start_date) AS start_date,
               TO_DATE(l_end_date) AS end_date
        FROM dual
        ),
        generated_dates AS (
        SELECT start_date + LEVEL - 1 AS generated_date
        FROM date_range
        CONNECT BY LEVEL <= (end_date - start_date + 1)
        )
        SELECT generated_date salary_date
        FROM generated_dates;
    BEGIN
        SELECT in_effective_date,
               payroll_end
        INTO l_start_date,
             l_end_date
        FROM hr_company_periods
        WHERE period_id = in_period_id
        AND company_id = in_company_id
        AND branch_id = in_branch_id;
        
        FOR i IN c1 LOOP
        
            INSERT INTO hr_emp_sal_breakups_datewise (
                salary_date, 
                emp_id, 
                allowance_code, 
                amount, 
                posted,
                period_id,
                created_by, 
                creation_date, 
                last_updated_by, 
                last_update_date
            )
            VALUES (
                i.salary_date,
                in_emp_id,
                in_tran_code,
                in_new_amount,
                'N',
                in_period_id,
                109,
                SYSDATE,
                NULL,
                NULL
            );
            
        END LOOP;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
 
    PROCEDURE del_sal_breakups_datewise (
        in_emp_id               IN  NUMBER,
        in_tran_code            IN  VARCHAR2,
        in_new_amount           IN  NUMBER,
        in_effective_date       IN  DATE,
        in_period_id            IN  NUMBER,
        in_company_id           IN  NUMBER,
        in_branch_id            IN  VARCHAR2
    )
    IS
    BEGIN
        DELETE FROM hr_emp_sal_breakups_datewise
        WHERE emp_id = in_emp_id
        AND period_id = in_period_id
        AND allowance_code = in_tran_code
        AND salary_date >= in_effective_date;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE del_sal_breakups_resign (
        in_emp_id               IN  NUMBER,
        in_date                 IN  DATE
    )
    IS
    BEGIN
        DELETE FROM hr_emp_sal_breakups_datewise
        WHERE emp_id = in_emp_id
        AND salary_date > in_date;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
END hrm_supp;
/
