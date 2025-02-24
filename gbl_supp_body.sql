CREATE OR REPLACE PACKAGE BODY gbl_supp
IS
   /*
   --
   */
    FUNCTION check_admin_access (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2
    IS  
        CURSOR cur_admin_access
        IS
        SELECT admin_access
        FROM sys_users
        WHERE user_id = in_user_id;
        l_admin_access sys_users.admin_access%TYPE;
    BEGIN
        OPEN cur_admin_access;
            FETCH cur_admin_access INTO l_admin_access; 
        CLOSE cur_admin_access;
        
        RETURN l_admin_access;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN 'N';
    END check_admin_access;
    
    /*
    -- This function is created to get user name by passing user id
    */
    
    FUNCTION get_user_name (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT user_name
        FROM sys_users
        WHERE user_id = in_user_id;
        
        l_user_name sys_users.user_name%TYPE;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_user_name;
        CLOSE c1;
        
        RETURN l_user_name;
        
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created to get employee name by passing user id
    */
    
    FUNCTION get_employee_name (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT e.emp_name
        FROM sys_users u,
             hr_employee_v e
        WHERE u.emp_id = e.emp_id
        AND u.user_id = in_user_id;
        
        l_emp_name VARCHAR2(50);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_emp_name;
        CLOSE c1;
        
        RETURN l_emp_name;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for checking supervisor
    */
    
    FUNCTION check_supervisor (
        in_emp_id                IN  NUMBER,
        in_supervisor_id         IN  NUMBER
    ) RETURN VARCHAR2
    IS 
        CURSOR c1
        IS
        SELECT COUNT(*)
        FROM (  
                SELECT supervisor_id
                FROM  hr_employees
                WHERE emp_id = in_emp_id
                AND resign_date IS NULL
                UNION
                SELECT supervisor_id
                FROM hr_employees
                WHERE emp_id = (SELECT supervisor_id FROM hr_employees WHERE emp_id = in_emp_id)
                AND resign_date IS NULL
                UNION
                SELECT supervisor_id
                FROM hr_employees
                WHERE emp_id = (
                                SELECT supervisor_id
                                FROM hr_employees
                                WHERE emp_id = (SELECT supervisor_id FROM hr_employees WHERE emp_id = in_emp_id)
                                AND resign_date IS NULL
                               )
                AND resign_date IS NULL
            )
        WHERE supervisor_id = in_supervisor_id;
        
        l_cnt NUMBER;
        l_chk_supervisor VARCHAR2(10);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_cnt;
        CLOSE c1;
        
        IF l_cnt > 0 THEN
            l_chk_supervisor := 'Y';
        ELSE 
            l_chk_supervisor := 'N';
        END IF;
        
        RETURN l_chk_supervisor;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for employee id for a user id
    */
    
    FUNCTION get_employee_id (
        in_user_id               IN  NUMBER
    ) RETURN NUMBER
    IS 
        CURSOR c1
        IS 
        SELECT emp_id
        FROM sys_users
        WHERE user_id = in_user_id;
        
        l_emp_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_emp_id;
        CLOSE c1;
        RETURN l_emp_id;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;    
    
    /*
    -- in_access_type values are A=Access, Q=Query, I=Insert, U=Update, D=Delete, E=Execute
    */
    FUNCTION check_object_access (
        in_user_id          IN  NUMBER,
        in_object_name      IN  gbl_sec_object.object_name%TYPE,
        in_access_type      IN  VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR objacc_cur
        IS
        SELECT soa.*
        FROM gbl_sec_objectaccess soa,
             gbl_sec_object so
        WHERE soa.object_id = so.object_id
        AND LOWER(so.object_name) = LOWER(in_object_name)
        AND soa.user_id = in_user_id
        AND soa.active_ind = 'Y';
        
        l_objacc gbl_sec_objectaccess%ROWTYPE;
        l_access VARCHAR2(1);
    BEGIN
        IF in_access_type NOT IN ('A', 'Q', 'I', 'U', 'D', 'E') THEN
            RETURN 'Invalid Access Type!';
        END IF;
        
        OPEN objacc_cur;
            FETCH objacc_cur INTO l_objacc;
            
            IF objacc_cur%FOUND THEN
                l_access := CASE in_access_type
                                WHEN 'A' THEN l_objacc.access_allowed
                                WHEN 'Q' THEN l_objacc.query_allowed
                                WHEN 'I' THEN l_objacc.insert_allowed
                                WHEN 'U' THEN l_objacc.update_allowed
                                WHEN 'D' THEN l_objacc.delete_allowed
                                WHEN 'E' THEN l_objacc.execute_allowed
                                ELSE 'No Access!'
                            END;
                            
                RETURN l_access;            
            END IF;
        CLOSE objacc_cur;
        
        RETURN 'No Access!';
        
    END check_object_access;
    
    /*
    -- This function is created for checking department head for a user id
    */
    
    FUNCTION check_dept_head (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT hod_chk
        FROM sys_users
        WHERE user_id = in_user_id;
        l_chk VARCHAR2(10);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        RETURN l_chk;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for checking management for a user id
    */
    
    FUNCTION check_management (
        in_user_id               IN  NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT mgt_check
        FROM sys_users
        WHERE user_id = in_user_id;
        l_chk VARCHAR2(10);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        RETURN l_chk;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This function is created for checking immediate supervisor
    */

    FUNCTION check_immediate_supervisor (
        in_emp_id                IN  NUMBER,
        in_supervisor_id         IN  NUMBER
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT 'Y'
        FROM hr_employee_v
        WHERE emp_id = in_emp_id
        AND supervisor_id = in_supervisor_id;
        l_chk VARCHAR2(1) := 'N';
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_chk;
        CLOSE c1;
        RETURN l_chk;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    /*
    -- This procedure is created for inserting in SMS outgoing table . Initial status
       is N. When sms will be sent then status will be set to Y
    */
    
    PROCEDURE ins_gbl_sms_outgoing (
        in_sms_text              IN  VARCHAR2,
        in_masking_name          IN  VARCHAR2,
        in_receiver_no           IN  VARCHAR2,
        in_created_by            IN  NUMBER,
        in_ip_address            IN  VARCHAR2,
        in_terminal              IN  VARCHAR2
    )
    IS
        l_sms_out_going_id NUMBER;
        l_sender_no VARCHAR2(20);
    BEGIN
        SELECT NVL(MAX(sms_outgoing_id),0)+1
        INTO l_sms_out_going_id
        FROM gbl_sms_outgoing;
        
        l_sender_no := NULL;
        
        INSERT INTO gbl_sms_outgoing (
            sms_outgoing_id,
            sms_text,
            sms_date,
            sender_no,
            masking_name,
            receiver_no,
            sms_status,
            status_date,
            created_by,
            created_date,
            ip_address,
            terminal
        )
        VALUES (
            l_sms_out_going_id,
            in_sms_text,
            SYSDATE,
            l_sender_no,
            in_masking_name,
            in_receiver_no,
            'N',
            NULL,
            in_created_by,
            SYSDATE,
            in_ip_address,
            in_terminal
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
    -- This procedure is for updating status of gbl_sms_outgoing table.    
    */
    
    PROCEDURE upd_gbl_sms_outgoing (
        in_sms_outgoing_id       IN  NUMBER
    )
    IS
    BEGIN
        UPDATE gbl_sms_outgoing
        SET sms_status = 'Y',
            status_date = SYSDATE
        WHERE sms_outgoing_id = in_sms_outgoing_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION generate_random_password ( 
        in_numbers      IN NUMBER, 
        in_specialchar  IN NUMBER, 
        in_lowercase    IN NUMBER, 
        in_uppercase    IN NUMBER
    ) RETURN VARCHAR2
    IS
      v_length         NUMBER := in_numbers + in_specialchar + in_lowercase + in_uppercase;
      v_password       VARCHAR2(200);
      v_iterations     NUMBER := 0;
      v_max_iterations NUMBER := 500;
    BEGIN
        LOOP
            v_password := dbms_random.string('p',v_length);
            v_iterations := v_iterations + 1;

               EXIT WHEN (regexp_count(v_password,'[a-z]') = in_lowercase
                     AND  regexp_count(v_password,'[A-Z]') = in_uppercase
                     AND  regexp_count(v_password,'[0-9]') = in_numbers ) 
                     OR v_iterations=v_max_iterations;

        END LOOP;

        IF v_iterations = v_max_iterations THEN
            v_password := '';
        END IF;

        RETURN (v_password);
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE ins_user_otp (
        in_user_name             IN  VARCHAR2
    )
    IS
        l_id NUMBER;
        l_otp VARCHAR2(50);
        l_encrypted_otp VARCHAR2(50);
    BEGIN
    
        SELECT NVL(MAX(id),0)+1
        INTO l_id
        FROM gbl_user_otp;
        
        /*
        l_otp := gbl_supp.generate_random_password ( 
                    in_numbers      => 1, 
                    in_specialchar  => 1, 
                    in_lowercase    => 2, 
                    in_uppercase    => 4
                );
        */
        
        --l_otp := DBMS_RANDOM.STRING ('x', 8); - x for alphanumeric
        --l_otp := DBMS_RANDOM.STRING ('p', 8); - p for alphanumeric with special character
        
        l_otp := TRUNC(dbms_random.value(100000,999999));
        
        l_encrypted_otp := datacrypt.encryptdata(l_otp);
        
        INSERT INTO gbl_user_otp (
            id,
            user_name,
            otp,
            encrypted_otp,
            is_active,
            valid_untill,
            created_by,
            created_date,
            last_updated_by,
            last_updated_date
        )
        VALUES (
            l_id,
            in_user_name,
            l_otp,
            l_encrypted_otp,
            'Y',
            SYSDATE + 1/24,
            NULL,
            SYSDATE,
            NULL,
            NULL
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE send_otp_to_user (
        in_user_name             IN  VARCHAR2,
        in_otp_type              IN  VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT off_mobile_phone , off_email
        FROM sys_users u,
             hr_employee_v e
        WHERE u.emp_id = e.emp_id
        AND UPPER(u.user_name) = UPPER(in_user_name)
        AND e.resign_date IS NULL;
        l_otp VARCHAR2(50);
        l_mobile_no VARCHAR2(50);
        l_email VARCHAR2(50);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_mobile_no , l_email;
        CLOSE c1;
        
        disable_user_otp(in_user_name);
        
        IF in_otp_type = 'S' THEN
            ins_user_otp (
                in_user_name             => in_user_name
            );
            
            SELECT otp
            INTO l_otp
            FROM gbl_user_otp
            WHERE user_name = in_user_name
            AND is_active = 'Y'
            AND valid_untill >= SYSDATE;
            
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Your OTP is -   '||l_otp||'   .It will remain valid for next one hour',
                in_masking_name          => 'BEXLPGMIS',
                in_receiver_no           => l_mobile_no,
                in_created_by            => NULL,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
        ELSIF in_otp_type = 'M' THEN
             ins_user_otp (
                in_user_name             => in_user_name
            );
                
            SELECT otp
            INTO l_otp
            FROM gbl_user_otp
            WHERE user_name = in_user_name
            AND is_active = 'Y'
            AND valid_untill >= SYSDATE;
            
            abz (l_email,'OTP From Beximco MIS','Your OTP is - '|| l_otp ||' .It will remain valid for next one hour');
            
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION check_otp_authentication (
        in_user_name             IN  VARCHAR2,
        in_otp                   IN  VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT 'Y'
        FROM gbl_user_otp
        WHERE UPPER(user_name) = UPPER(in_user_name)
        AND datacrypt.decryptdata(encrypted_otp) = in_otp
        AND is_active = 'Y'
        AND valid_untill >= SYSDATE;
        l_check VARCHAR2(1) := 'N';
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_check; 
        CLOSE c1;
        RETURN l_check;
    EXCEPTION
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE disable_user_otp (
        in_user_name             IN  VARCHAR2
    )
    IS
    BEGIN
       UPDATE gbl_user_otp 
       SET is_active = 'N'
       WHERE UPPER(user_name) = UPPER(in_user_name);
      
       COMMIT;
    EXCEPTION
       WHEN OTHERS THEN
       NULL;
    END;
    
    PROCEDURE send_sms_during_do (
        in_do_id                 IN  VARCHAR2
    )
    IS
        CURSOR c1
        IS
        SELECT he.emp_name,
               he.off_mobile_phone tsi_mobile_no,
               TRIM(SUBSTR(ac.customer_name,1,INSTR(ac.customer_name, ' ', -1))) customer_name,
               NVL(ac.concern_person, 'Mr.') concern_person,
               NVL(ac.concern_person_ph_no,'0') concern_person_ph_no,
               nvl(soa.amount,0) amount,
               so.po_no
        FROM inv_sales_orders so,
             hr_employees he,
             sys_users su,
             ar_customers ac,
             (
             SELECT sales_order_id,
                    SUM(do_amount) amount
             FROM sales_order_attachments
             GROUP BY sales_order_id
             ) soa
        WHERE so.created_by = su.user_id
        AND su.emp_id = he.emp_id
        AND so.customer_id = ac.customer_id
        AND so.sales_order_id = soa.sales_order_id
        AND so.sales_order_id = in_do_id;
        
        l_tsi_name VARCHAR2(50);
        l_tsi_mobile VARCHAR2(50);
        l_customer_name VARCHAR2(50);
        l_concern_person VARCHAR2(50);
        l_customer_mobile VARCHAR2(50);
        l_amount NUMBER;
        l_do_no VARCHAR2(50);
        l_mobile_hod_mis VARCHAR2(50) := '01730397888';
        l_mobile_cmo VARCHAR2(50) := '01714047234';
        l_mobile_finance VARCHAR2(50) := '01730397756';
        
    BEGIN
        OPEN c1;
            FETCH c1 INTO   l_tsi_name,
                            l_tsi_mobile,
                            l_customer_name,
                            l_concern_person,
                            l_customer_mobile,
                            l_amount,
                            l_do_no;
        CLOSE c1;

        IF NVL(l_amount,0) > 0 THEN

            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Mr. '|| INITCAP(l_tsi_name) || ', payment of '|| INITCAP(l_customer_name) || ' amount BDT '|| l_amount || '/= has been received against DO No. '|| l_do_no ,
                in_masking_name          => 'BEXIMCOLPG',
                in_receiver_no           => l_tsi_mobile,
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
            
            IF l_customer_mobile <> '0' THEN
                gbl_supp.ins_gbl_sms_outgoing (
                    in_sms_text              => 'Mr. '|| INITCAP(l_concern_person) || ', your payment of '|| INITCAP(l_customer_name) || ' amount BDT '|| l_amount || '/= has been received by Beximco LPG.' ,
                    in_masking_name          => 'BEXIMCOLPG',
                    in_receiver_no           => l_customer_mobile,
                    in_created_by            => 109,
                    in_ip_address            => NULL,
                    in_terminal              => NULL
                );
            END IF; 
                     
            /*
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Customer '|| INITCAP(l_customer_name) ||' has deposited '  ||'BDT '|| l_amount || '/= against DO No.'||l_do_no|| ' initiated by - '||l_tsi_name || ' which is received by Beximco LPG',
                in_masking_name          => 'BEXIMCOLPG',
                in_receiver_no           => l_mobile_hod_mis,
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
            
            
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Customer '|| INITCAP(l_customer_name) ||' has deposited '  ||'BDT '|| l_amount || '/= against DO No.'||l_do_no|| ' initiated by - '||l_tsi_name || ' which is received by Beximco LPG',
                in_masking_name          => 'BEXIMCOLPG',
                in_receiver_no           => l_mobile_finance,
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
            
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Customer '|| INITCAP(l_customer_name) ||' has deposited '  ||'BDT '|| l_amount || '/= against DO No.'||l_do_no|| ' initiated by - '||l_tsi_name || ' which is received by Beximco LPG',
                in_masking_name          => 'BEXIMCOLPG',
                in_receiver_no           => '01788740100',
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
            
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => 'Customer '|| INITCAP(l_customer_name) ||' has deposited '  ||'BDT '|| l_amount || '/= against DO No.'||l_do_no|| ' initiated by - '||l_tsi_name || ' which is received by Beximco LPG',
                in_masking_name          => 'BEXIMCOLPG',
                in_receiver_no           => l_mobile_cmo,
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
            */
        END IF;
     
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    /*
    -- This function is created for check admin access of a user 
    AUTHORE : 
    DATE    :
    Modified By:
    ===============
    NAME                    DATE        DESCRIPTION/COMMENTS
    Md. Rumman Alam         16/08/2023  Add a function named "fn_login" to authenticate valid user to login in APEX
    */
    
    FUNCTION login(p_username IN VARCHAR2
                        , p_password VARCHAR2) RETURN BOOLEAN
    IS
        l_boolean BOOLEAN := FALSE;
        l_count   NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_count
        FROM sys_users
        WHERE UPPER(USER_NAME) = UPPER(p_username)
        AND TRIM(pwd) = TRIM(DATACRYPT.ENCRYPTDATA(p_password))
        AND BLOCKED = 'N';
        
        IF l_count > 0 THEN
            l_boolean := TRUE;
        END IF;    
            
        RETURN l_boolean;
    END login;
    
    PROCEDURE send_sms_for_menu_update
    IS
        CURSOR c1
        IS
        SELECT sid,
               username,
               logon_time ,
               SUBSTR(client_identifier,22,30) emp_name, 
               SUBSTR(client_identifier,1,15), 
               module ,
               SUBSTR(client_identifier,17,3),
               SUBSTR(client_identifier,22), 
               c.off_mobile_phone,
               c.sex
        FROM sys.v_$session a, 
             sys_users b, 
             hr_employee_v c
        WHERE username ='LPG'
        AND SUBSTR(client_identifier,17,3) = TO_CHAR(b.user_id)
        AND b.emp_id = c.emp_id
        AND client_identifier IS NOT NULL;
        
        l_sex VARCHAR2(10);
        l_title VARCHAR2(10);
        l_msg VARCHAR2(300);
    BEGIN
        FOR m IN c1 LOOP
            l_sex := m.sex;
            IF l_sex = 'M' THEN
                l_title := 'Mr. ';
            ELSE
                l_title := 'Ms. ';
            END IF;
            l_msg := 'Dear '|| l_title ||m.emp_name|| ',Due to some critical patch updation ERP is going down for 5 minuts. Please exit from ERP.
Thanks,
Beximco MIS';
            gbl_supp.ins_gbl_sms_outgoing (
                in_sms_text              => l_msg ,
                in_masking_name          => 'BEXLPGMIS',
                in_receiver_no           => m.off_mobile_phone,
                in_created_by            => 109,
                in_ip_address            => NULL,
                in_terminal              => NULL
            );
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    FUNCTION get_nextval(p_seq_name IN VARCHAR2
                        , p_schema VARCHAR2
    ) RETURN NUMBER
    IS
                l_stmt  VARCHAR2(3000);
        l_seq   NUMBER;
    BEGIN
        l_stmt := 'SELECT '||p_schema||'.'||p_seq_name||'.nextval from dual';        
        execute immediate l_stmt into l_seq ;
        RETURN l_seq;
    END get_nextval;
    
    PROCEDURE upd_qrcode_generate (
        in_id                   IN   NUMBER,
        in_qr_code              IN   BLOB
    )
    IS
    BEGIN
        UPDATE gbl_qrcode_generate
        SET qr_code = in_qr_code,
            is_generated = 'Y'
        WHERE id = in_id;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    PROCEDURE send_email (
        in_mail_server IN      VARCHAR2,
        in_smtp_port   IN      VARCHAR2,
        in_subject     IN      VARCHAR2,
        in_to          IN      VARCHAR2,
        in_cc          IN      VARCHAR2,
        in_bcc         IN      VARCHAR2,
        in_message     IN      VARCHAR2
    )
    IS
        conn utl_smtp.connection;
        BOUNDARY  VARCHAR2 (256) := '-----090303020209010600070908';
        i         pls_integer;
        len       pls_integer;
        buff_size pls_integer := 57;
        l_raw     raw(57);
        p_image blob;
        MailServer  VARCHAR2(50) := 'mail.bexmis.com';
        l_message VARCHAR2(32767) :='<html>
                                        <body>
                                            <img src="cid:banner" alt="banner"/>
                                            <br>
                                            Test HTML with Embedded Image-chk latest
                                            <p>And here it is:</p>
                                            <p>The end.</p>
                                        </body>
                                    </html>';
    BEGIN
        SELECT qr_code  
        INTO p_image
        FROM gbl_qrcode_generate
        WHERE ID = 2;
        
        conn := utl_smtp.open_connection(MailServer, 25);
        utl_smtp.helo (conn, mailserver);
        utl_smtp.mail (conn, 'MIS@bexmis.com');
        utl_smtp.rcpt (conn, 'faisal.ahmed@beximco.net');
        utl_smtp.open_data  (conn);
        utl_smtp.write_data (conn, 'From' || ': ' || 'MIS@bexmis.com'|| utl_tcp.crlf);
        utl_smtp.write_data (conn, 'To' || ': ' || 'faisal.ahmed@beximco.net'|| utl_tcp.crlf);
        utl_smtp.write_data (conn, 'MIME-Version: 1.0' || utl_tcp.crlf);
        utl_smtp.write_data (conn, 'Subject: image inline testing' || utl_tcp.crlf) ;
        utl_smtp.write_data (conn, 'Content-Type: multipart/mixed; boundary="' || boundary || '"' || utl_tcp.crlf);
        utl_smtp.write_data (conn, utl_tcp.crlf);
        utl_smtp.write_data (conn,  '--' || boundary || utl_tcp.crlf );
        utl_smtp.write_data (conn,  'Content-Type: text/html; charset=US-ASCII'|| utl_tcp.crlf );
        utl_smtp.write_data (conn, utl_tcp.crlf);
        utl_smtp.write_data (conn, l_message);
        utl_smtp.write_data (conn, utl_tcp.crlf);
        utl_smtp.write_data (conn,  '--' || boundary || utl_tcp.crlf );
        utl_smtp.write_data (conn,  'Content-Type: image/jpg;'|| utl_tcp.crlf );
        utl_smtp.write_data (conn, 'Content-Disposition: inline; filename="banner.jpg"' || utl_tcp.crlf);
        utl_smtp.write_data (conn, 'Content-ID: <banner> ' || utl_tcp.crlf);   
        utl_smtp.write_data (conn, 'Content-Transfer-Encoding' || ': ' || 'base64' || utl_tcp.crlf);
        utl_smtp.write_data (conn, utl_tcp.crlf);
        i := 1;
        len := dbms_lob.getlength(p_image);
        WHILE i < len LOOP
            dbms_lob.read(p_image, buff_size, i, l_raw);
            utl_smtp.write_raw_data(conn, utl_encode.base64_encode(l_raw));
            utl_smtp.write_data(conn, utl_tcp.crlf);
            i := i + buff_size;
        END LOOP;
        utl_smtp.write_data(conn, utl_tcp.crlf);
        utl_smtp.write_data (conn, '--' || boundary || '--' || utl_tcp.crlf);
        utl_smtp.write_data (conn, utl_tcp.crlf);
        utl_smtp.close_data(conn);
        utl_smtp.quit(conn);
    
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END;
    
    FUNCTION get_branch_name (
        in_branch_id   IN      VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT branch_name
        FROM sys_branches
        WHERE branch_id = in_branch_id;
        l_branch_name VARCHAR2(100);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_branch_name;
        CLOSE c1;
        
        RETURN l_branch_name;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    
    FUNCTION get_company_name (
        in_branch_id   IN      VARCHAR2
    ) RETURN VARCHAR2
    IS
        CURSOR c1
        IS
        SELECT comp_name
        FROM sys_branches
        WHERE branch_id = in_branch_id;
        l_company_name VARCHAR2(100);
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_company_name;
        CLOSE c1;
        
        RETURN l_company_name;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    FUNCTION get_company_id   (
        in_branch_id   IN      VARCHAR2
    ) RETURN NUMBER
    IS
        CURSOR c1
        IS
        SELECT company_no
        FROM sys_branches
        WHERE branch_id = in_branch_id;
        l_company_id NUMBER;
    BEGIN
        OPEN c1;
            FETCH c1 INTO l_company_id;
        CLOSE c1;
        
        RETURN l_company_id;
    EXCEPTION 
        WHEN OTHERS THEN
        RETURN NULL;
    END;
    
    PROCEDURE send_email_event_wise (
        in_event_name  IN      VARCHAR2,
        in_pk_id       IN      NUMBER
    )
    IS
        CURSOR c1 
        IS 
        SELECT igp.indent_id,
               itm.item_id,
               itm.item_code,
               itm.item_desc, 
               itm.uom, 
               ind.indent_qty,
               igp.received_qty, 
               ind.created_by, 
               usr.user_name,
               ind.indent_no,
               (ship_qty - NVL (inv_po_item_shipments.received_qty, 0)) AS balance
        FROM inv_igp_items igp,
             inv_items itm,
             inv_indents ind,
             sys_users usr,
             inv_po_item_shipments
        WHERE igp.indent_id = ind.indent_id
        AND ind.item_id = itm.item_id
        AND inv_po_item_shipments.po_item_shipment_id = igp.po_item_shipment_id
        AND ind.created_by = usr.user_id
        AND igp.igp_id = in_pk_id;
               
        CURSOR C2 
        IS 
        SELECT COUNT (*) tot, 
               ind.created_by, 
               usr.user_name, 
               off_email email
        FROM inv_igp_items igp, 
             inv_items itm, 
             inv_indents ind, 
             sys_users usr , 
             hr_employee_v emp
        WHERE igp.indent_id = ind.indent_id
        AND ind.item_id = itm.item_id
        AND usr.EMP_ID = emp.EMP_ID
        AND ind.created_by = usr.user_id
        AND igp.igp_id = in_pk_id
        GROUP BY ind.created_by, 
                 usr.user_name,
                 off_email;
        
        l_location_id NUMBER;
        l_vendor_name VARCHAR2(200);
        l_location_name VARCHAR2(200);
        l_igp_no NUMBER;
        p_mailto VARCHAR2(255);
        p_subject VARCHAR2(10000);
        p_message VARCHAR2(10000);
        v_tot NUMBER;
        v_created_by NUMBER;
        msg VARCHAR2(10000) :=' ';
        msg_h VARCHAR2(10000) :=' ';
        msg_t VARCHAR2(10000) :=' ';
        loc_email VARCHAR2(100);
    BEGIN
        IF in_event_name = 'IGP' THEN
        
            SELECT location_id
            INTO l_location_id
            FROM inv_igps
            WHERE igp_id = in_pk_id;
            
            SELECT vendor_name
            INTO l_vendor_name
            FROM inv_vendors
            WHERE vendor_id = (SELECT vendor_id
                               FROM inv_igps
                               WHERE igp_id = in_pk_id);
                               
            SELECT location_name
            INTO l_location_name
            FROM inv_locations
            WHERE location_id = l_location_id;
            
            SELECT igp_no 
            INTO l_igp_no
            FROM inv_igps
            WHERE igp_id = in_pk_id;
            
            p_subject :='Arrival for material againt IGP# '||l_igp_no|| '  From : '|| l_vendor_name||' For Location '||l_location_name ;
           
            FOR j IN c2 LOOP
                v_tot:=j.tot;
                v_created_by:=j.created_by;
                p_mailto:= j.email;
                msg_H:='<br><l>Reference to the captioned subject this is to inform you that following items indented by you have 
arrived at your premises, You are requested to follow up for inspection <br></l><BR> ';
                msg_t:='<br><l>Regards</l><l> <B><BR> <BR>Beximco Information System </B><br></l>';
                msg:= '<table BORDER=1 cellspacing="1" cellpadding="0" width="100%">'; --'
                msg:=    msg||'<tr align="CENTER" valign="BASELINE">';            
                msg:=msg||    '<td face="B"><B>Indent #</B></td><td><B>Item Description</B></td><Td><B>UOM</TD><Td><B>PO Qty</TD><Td><B>IGP Qty</TD><Td><B>PO Balance</TD></TR>';
                
                FOR i IN c1 LOOP            
                    IF i.created_by=j.created_by THEN
                        msg:=    msg||'<tr align="CENTER" valign="BASELINE">';            
                        msg:=msg||    '<td>'||i.indent_no||'  </td>'||'<td align="LEFT">'||i.item_desc||'</td><Td>'||' '||i.uom||'</td><Td>'||i.indent_qty||'</td><Td>'||i.received_qty ||'</td><Td>'||i.balance || '</td></TR>';
                    END IF;
                END LOOP;
                            
                msg:=msg||'</Table>';
                p_message:=msg;    
                abz(p_mailto,P_Subject ,msg_h||P_Message||msg_t );    
                    
                FOR e IN (
                            SELECT email_add loc_email
                            FROM inv_locations_emails
                            WHERE location_id = l_location_id
                            AND is_active = 'Y'
                         ) LOOP   
                          
                    IF NVL(e.loc_email,'##') IS NOT NULL THEN
                        abz(e.loc_email,P_Subject ,msg_h||P_Message||msg_t );
                    END IF;
                    
                END LOOP;
                
                msg:=' ';
                   
            END LOOP;  
            
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
        NULL;
    END; 
    
END gbl_supp;
/
