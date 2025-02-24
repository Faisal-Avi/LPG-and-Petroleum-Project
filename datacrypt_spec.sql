CREATE OR REPLACE PACKAGE DATACRYPT is
	Function encryptdata( p_data IN VARCHAR2 ) Return RAW DETERMINISTIC;
	Function decryptdata( p_data IN RAW ) Return VARCHAR2 DETERMINISTIC;
	Function decryptkey Return VARCHAR2;
End datacrypt;
/
