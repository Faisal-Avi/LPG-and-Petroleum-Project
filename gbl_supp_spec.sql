CREATE OR REPLACE PACKAGE gbl_supp
IS  
    
    FUNCTION check_admin_access (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_user_name (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_employee_name (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION check_supervisor (
        in_emp_id                IN  NUMBER,
        in_supervisor_id         IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION get_employee_id (
        in_user_id               IN  NUMBER
    ) RETURN NUMBER;
 
    FUNCTION check_object_access (
        in_user_id          IN  NUMBER,
        in_object_name      IN  gbl_sec_object.object_name%TYPE,
        in_access_type      IN  VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION check_dept_head (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2; 
    
    FUNCTION check_management (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION check_immediate_supervisor (
        in_emp_id                IN  NUMBER,
        in_supervisor_id         IN  NUMBER
    ) RETURN VARCHAR2;
    
    PROCEDURE ins_gbl_sms_outgoing (
        in_sms_text              IN  VARCHAR2,
        in_masking_name          IN  VARCHAR2,
        in_receiver_no           IN  VARCHAR2,
        in_created_by            IN  NUMBER,
        in_ip_address            IN  VARCHAR2,
        in_terminal              IN  VARCHAR2
    );
    
    PROCEDURE upd_gbl_sms_outgoing (
        in_sms_outgoing_id       IN  NUMBER
    );
    
    FUNCTION generate_random_password ( 
        in_numbers      IN NUMBER, 
        in_specialchar  IN NUMBER, 
        in_lowercase    IN NUMBER, 
        in_uppercase    IN NUMBER
    ) RETURN VARCHAR2;
    
    PROCEDURE ins_user_otp (
        in_user_name             IN  VARCHAR2
    );
    
    PROCEDURE send_otp_to_user (
        in_user_name             IN  VARCHAR2,
        in_otp_type              IN  VARCHAR2
    ); 

    FUNCTION check_otp_authentication (
        in_user_name             IN  VARCHAR2,
        in_otp                   IN  VARCHAR2
    ) RETURN VARCHAR2;
      
    PROCEDURE disable_user_otp (
        in_user_name             IN  VARCHAR2
    );
    
    PROCEDURE send_sms_during_do (
        in_do_id                 IN  VARCHAR2
    );
    
    FUNCTION login(p_username IN VARCHAR2
                   , p_password VARCHAR2
    ) RETURN BOOLEAN;
    
    PROCEDURE send_sms_for_menu_update;
    
    FUNCTION get_nextval(p_seq_name IN VARCHAR2
                        , p_schema VARCHAR2
    ) RETURN NUMBER;
    
    PROCEDURE upd_qrcode_generate (
        in_id                   IN   NUMBER,
        in_qr_code              IN   BLOB
    );
    
    PROCEDURE send_email (
        in_mail_server IN      VARCHAR2,
        in_smtp_port   IN      VARCHAR2,
        in_subject     IN      VARCHAR2,
        in_to          IN      VARCHAR2,
        in_cc          IN      VARCHAR2,
        in_bcc         IN      VARCHAR2,
        in_message     IN      VARCHAR2
    );
    
    FUNCTION get_branch_name (
        in_branch_id   IN      VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_company_name (
        in_branch_id   IN      VARCHAR2
    ) RETURN VARCHAR2;
    
    FUNCTION get_company_id   (
        in_branch_id   IN      VARCHAR2
    ) RETURN NUMBER;
    
    PROCEDURE send_email_event_wise (
        in_event_name  IN      VARCHAR2,
        in_pk_id       IN      NUMBER
    );
    
END gbl_supp;
/
