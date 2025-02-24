CREATE OR REPLACE PACKAGE BODY DATACRYPT is

  dkey RAW(128) := UTL_RAW.cast_to_raw(decryptkey);

  Function encryptdata( p_data IN VARCHAR2 ) Return RAW DETERMINISTIC  IS
   l_data RAW(2048) := utl_raw.cast_to_raw(p_data);
   l_encrypted RAW(2048);
  BEGIN
    l_encrypted := dbms_crypto.encrypt                        -- Algorithm
    ( src => l_data,
      typ => DBMS_CRYPTO.DES_CBC_PKCS5,
      key => dkey);
      Return l_encrypted;
  END encryptdata;

  Function decryptdata( p_data IN RAW ) Return VARCHAR2 DETERMINISTIC  IS
   l_decrypted RAW(2048);
  BEGIN
   l_decrypted := dbms_crypto.decrypt
   ( src => p_data,
   typ => DBMS_CRYPTO.DES_CBC_PKCS5,
   key => dkey );
   Return utl_raw.cast_to_varchar2(l_decrypted);
  END decryptdata;

  Function decryptkey return varchar2 is
    ed_key varchar2(25):='Pakistan786';
  begin
   return(ed_key);
  exception when no_data_found then
    
    return(ed_key);
    when others then
    
    return(ed_key);
  end decryptkey;
 

End datacrypt;
/
