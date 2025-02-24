CREATE OR REPLACE PACKAGE BODY audit_supp
IS
    PROCEDURE ins_gbl_audit(
        in_audit_action         IN      VARCHAR2, 
        in_audit_table          IN      VARCHAR2,
        in_pk_column_name       IN      VARCHAR2,
        in_pk_value             IN      VARCHAR2,
        out_audit_id            OUT     NUMBER
    )
    IS
        CURSOR hst
        IS
        SELECT SYS_CONTEXT('USERENV','HOST') host_name,
               SYS_CONTEXT('USERENV','IP_ADDRESS') ip_address,
               SYS_CONTEXT('USERENV','MODULE') module_name 
        FROM sys.v_$session where sid = userenv('SID');

        l_host_name VARCHAR2(100);
        l_ip_address VARCHAR2(100);
        l_module_name VARCHAR2(100);
        l_user_id NUMBER;
        
      /*  CURSOR lg
        IS
        SELECT user_id,
               login_id
        FROM login_tbl
        WHERE (sid, serial#) = (SELECT sid, serial# FROM v$session WHERE audsid = sys_context('userenv', 'sessionid'))
        ORDER BY in_time DESC;
        */
        
        l_login_id NUMBER;
        l_next_val NUMBER;
        v_prog VARCHAR2(100);
        v_module VARCHAR2(100);
        v_os_user VARCHAR2(100);        
        v_terminal VARCHAR2(100);
        v_ip VARCHAR2(50);
        v_db_user VARCHAR2(30); 
        v_erp_user VARCHAR2(10); 
    BEGIN
        OPEN hst;
            FETCH hst INTO l_host_name,l_ip_address,l_module_name;
        CLOSE hst;

        SELECT UPPER (program)
        INTO v_prog
        FROM sys.v_$session
        WHERE sid = USERENV ('SID');
               
        
        IF SUBSTR(UPPER(v_prog),1,6) = 'FRMWEB' THEN 
            SELECT username,
                   SUBSTR (CLIENT_IDENTIFIER, 22, 30),
                   SYS_CONTEXT ('USERENV', 'HOST'),
                   SUBSTR (CLIENT_IDENTIFIER, 1, 15),
                   SUBSTR (CLIENT_IDENTIFIER, 17, 3)
            INTO v_db_user,
                 v_os_user,
                 v_terminal,
                 v_ip,
                 l_user_id
            FROM sys.v_$session
            WHERE sid = USERENV ('SID');
        ELSE
            SELECT username,
                   osuser,
                   terminal,
                   SYS_CONTEXT ('userenv', 'ip_address'),
                   program
            INTO v_db_user,
                 v_os_user,
                 v_terminal,
                 v_ip,
                 v_prog
            FROM sys.v_$session
            WHERE sid = USERENV ('SID'); 
        END IF;
        
        SELECT NVL(MAX(audit_id),0)+1
        INTO l_next_val
        FROM gbl_audit;
        
        INSERT INTO gbl_audit(
            audit_id,
            audit_dttm,
            audit_action,
            audit_table,
            audit_host,
            audit_ip_address,
            audit_login_id,
            audit_user_id,
            connection_type,
            pk_column_name,
            pk_value
        )
        VALUES(
            l_next_val,
            SYSDATE,
            in_audit_action,
            in_audit_table,
            l_host_name,
            v_ip,
            l_login_id,
            l_user_id,
            l_module_name,
            in_pk_column_name,
            in_pk_value
        );
        
        out_audit_id := l_next_val;
    END ins_gbl_audit;
    
    PROCEDURE ins_gbl_audit_dtl(
        in_audit_id             IN      NUMBER,
        in_audit_column         IN      VARCHAR2,
        in_old_value            IN      VARCHAR2,
        in_new_value            IN      VARCHAR2,
        in_audit_action         IN      VARCHAR2
    )
    IS
        
    BEGIN
        IF (in_audit_action = 'U' AND NVL(in_old_value,'~~~~~') <> NVL(in_new_value,'~~~~~')) OR in_audit_action='D' THEN
            INSERT INTO gbl_audit_dtl (
                audit_id, 
                audit_column, 
                old_value, 
                new_value
            )
            VALUES (
                in_audit_id,
                in_audit_column,
                in_old_value,
                in_new_value
            );
        END IF;
    END ins_gbl_audit_dtl;
    
    PROCEDURE create_audit_trigger(
        in_trigger_name            IN        VARCHAR2,
        in_table_name            IN        VARCHAR2,
        in_pk_column_name        IN        VARCHAR2
    )
    IS
        CURSOR col
        IS
        SELECT column_name,
               data_type 
        FROM user_tab_columns 
        WHERE UPPER(table_name) =UPPER(in_table_name);
        l_column_name VARCHAR2(30);
        l_data_type VARCHAR2(30);
        l_column_sql VARCHAR2(3999) := '';
    BEGIN
        
         dbms_output.put_line('CREATE OR REPLACE TRIGGER '||in_trigger_name||'
                            AFTER UPDATE OR DELETE ON '||in_table_name||'
                            FOR EACH ROW
                            DECLARE
                                l_in_audit_action VARCHAR2(1) := ''U'';
                                l_audit_id GBL_AUDIT.AUDIT_ID%TYPE;
                            BEGIN
                                IF UPDATING THEN
                                    l_in_audit_action := ''U'';
                                ELSIF DELETING THEN
                                    l_in_audit_action := ''D'';
                                END IF;');
                                
        dbms_output.put_line('audit_supp.ins_gbl_audit(
                                    in_audit_action         =>      l_in_audit_action, 
                                    in_audit_table          =>      '''||UPPER(in_table_name)||''',
                                    in_pk_column_name       =>      '''||UPPER(in_pk_column_name)||''',
                                    in_pk_value             =>      '||':'||'OLD.'||UPPER(in_pk_column_name)||',
                                    out_audit_id            =>      l_audit_id
                                );');
                                
                                FOR i IN col
                                LOOP
                                    dbms_output.put_line('audit_supp.ins_gbl_audit_dtl(l_audit_id, '''||i.column_name||''','||':OLD.'||i.column_name||','||':NEW.'||i.column_name||', l_in_audit_action);');
                                END LOOP;
                                
        dbms_output.put_line('END;');
    EXCEPTION WHEN OTHERS THEN 
        dbms_output.put_line(sqlerrm);
    END create_audit_trigger;
    /*
    set serveroutput on size 1000000
    BEGIN
        audit_supp.create_audit_trigger(
            in_trigger_name   => 'TRI_AUDIT_ON_BANK',
            in_table_name     => 'BANK',
            in_pk_column_name => 'PID'
        );
    END;
    */
END audit_supp;
/
