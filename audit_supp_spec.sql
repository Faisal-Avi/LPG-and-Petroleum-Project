CREATE OR REPLACE PACKAGE LPG_TEST.audit_supp
IS
    PROCEDURE ins_gbl_audit(
        in_audit_action         IN      VARCHAR2, 
        in_audit_table          IN      VARCHAR2,
        in_pk_column_name       IN      VARCHAR2,
        in_pk_value             IN      VARCHAR2,
        out_audit_id            OUT     NUMBER
    );
    
    PROCEDURE ins_gbl_audit_dtl(
        in_audit_id             IN      NUMBER,
        in_audit_column         IN      VARCHAR2,
        in_old_value            IN      VARCHAR2,
        in_new_value            IN      VARCHAR2,
        in_audit_action         IN      VARCHAR2
    );
    
    PROCEDURE create_audit_trigger(
        in_trigger_name            IN        VARCHAR2,
        in_table_name            IN        VARCHAR2,
        in_pk_column_name        IN        VARCHAR2
    );
END audit_supp;
/
