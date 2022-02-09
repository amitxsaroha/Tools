--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++--
--                                                                 
-- File name:   etrc.sql                                                  
-- Type:    	SQL Script                                                      
-- Purpose:     List the SQL trace type statements available on Oracle Database, for making session trace easy.
--
-- Usage:     	@tracesid <sid>
-- Author:                                                       
-- Version:   	v1.0
-- Modified:
--                                                                  
-- Parameters:  
--                                                                  
--                                                                  
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++--

ACCEPT sid     char prompt 'Enter sid for tracing? '
PROMPT

DEFINE _br=chr(10)
DEFINE _trcsid_session_id=&sid
DEFINE _trcsid_session_serial="NA"

COLUMN trcsid_session_serial NEW_VALUE _trcsid_session_serial

DEFINE _trcsid_session_serial="NA"

SET TERMOUT OFF

SELECT TRIM(serial#) trcsid_session_serial from v$session where sid=&sid;

SET TERMOUT ON 

PROMPT Session Information -

SELECT
   	'    INST# ............ ' || RPAD(userenv('INSTANCE')	, 50, ' ') ||   'SID   ............ ' || s.sid               || &_br ||
   	'    SERIAL# .......... ' || RPAD(s.serial#          	, 50, ' ') ||   'USERNAME ......... ' || s.username          || &_br ||
   	'    SPID  ............ ' || RPAD(p.spid             	, 50, ' ') ||   'OPID ............. ' || p.pid               || &_br ||
   	'    PADDR  ........... ' || RPAD(s.paddr            	, 50, ' ') ||   'SADDR  ........... ' || s.saddr             || &_br ||
   	'    AUDSID  .......... ' || RPAD(s.audsid           	, 50, ' ') ||   'OSUSER  .......... ' || s.osuser            || &_br ||
   	'    PROCESS  ......... ' || RPAD(s.process          	, 50, ' ') ||   'PROGRAM  ......... ' || s.program           || &_br ||
   	'    MACHINE  ......... ' || RPAD(s.machine          	, 50, ' ') ||   'MODULE  .......... ' || s.module            || &_br ||
   	'    HASH_VALUE. ...... ' || RPAD(s.sql_hash_value   	, 50, ' ') ||   'PREV_HASH_VALUE .. ' || s.prev_hash_value   || &_br ||
   	'    SQL_ID ........... ' || rpad(s.sql_id           	, 50, ' ') ||   'CHILD_NUMBER# .... ' || s.sql_child_number  || &_br ||
   	'    PREV_SQL_ID ...... ' || rpad(s.prev_sql_id      	, 50, ' ') ||   'PREV_CHILD# ...... ' || s.prev_child_number 
FROM v$session s, v$session_wait w, v$process p
WHERE s.sid IN (&sid)
AND s.paddr = p.addr
AND s.sid = w.sid
/

PROMPT =========== DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION ===========
PROMPT 
PROMPT .       [1]*    SQL> EXEC SYS.DBMS_SYSTEM.SET_EV( SI=> &_trcsid_session_id, SE=> &_trcsid_session_serial, EV=> 10046, LE=> 12, NM=>'''');    (12 = binds, waits)       
PROMPT .       [2]     SQL> EXEC SYS.DBMS_SYSTEM.SET_EV( SI=> &_trcsid_session_id, SE=> &_trcsid_session_serial, EV=> 10046, LE=> 8,  NM=>'''');    (8  = no binds, waits)    
PROMPT .       [3]     SQL> EXEC SYS.DBMS_SYSTEM.SET_EV( SI=> &_trcsid_session_id, SE=> &_trcsid_session_serial, EV=> 10046, LE=> 4,  NM=>'''');    (4  = binds, no waits)    
PROMPT .       [4]     SQL> EXEC SYS.DBMS_SYSTEM.SET_EV( SI=> &_trcsid_session_id, SE=> &_trcsid_session_serial, EV=> 10046, LE=> 1,  NM=>'''');    (1  = no binds, no waits) 
PROMPT
PROMPT
PROMPT=========== DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION ===========
PROMPT 
PROMPT .       [5]     SQL> EXEC SYS.DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION( &_trcsid_session_id, &_trcsid_session_serial, true);;
PROMPT
PROMPT
PROMPT=========== DBMS_MONITOR_SESSION_TRACE_ENABLE ===========
PROMPT 
PROMPT .       [6]     SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID=> &_trcsid_session_id, SERIAL_NUM => &_trcsid_session_serial, WAITS => TRUE  , BINDS => TRUE);;
PROMPT .       [7]     SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID=> &_trcsid_session_id, SERIAL_NUM => &_trcsid_session_serial, WAITS => FALSE , BINDS => TRUE);;
PROMPT .       [8]     SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID=> &_trcsid_session_id, SERIAL_NUM => &_trcsid_session_serial, WAITS => TRUE  , BINDS => FALSE);;
PROMPT .       [9]     SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID=> &_trcsid_session_id, SERIAL_NUM => &_trcsid_session_serial, WAITS => FALSE , BINDS => FALSE);;
PROMPT
PROMPT

ACCEPT _trcsid_session_v PROMPT '>>>>>>> Enter for the value of the trace type. [ ZERO to cancel]: ' DEFAULT 1
PROMPT 


SELECT
	CASE
		WHEN &_trcsid_session_v = 0 THEN
			'PROMPT Process was Canceled!'
		WHEN &_trcsid_session_v = 2 THEN
			'PROMPT SQL> EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 8, NM => '''');' || &_br ||
			'EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 8, NM => '''');' 			
		WHEN &_trcsid_session_v = 3 THEN
			'PROMPT SQL> EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 4, NM => '''');' || &_br ||
			'EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 4, NM => '''');' 			
		WHEN &_trcsid_session_v = 4 THEN
			'PROMPT SQL> EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 1, NM => '''');' || &_br ||
			'EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 1, NM => '''');' 			
		WHEN &_trcsid_session_v = 5 THEN
			'PROMPT SQL> EXEC SYS.DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION( ' || &_trcsid_session_id || ' ,' || &_trcsid_session_serial || ', true);' 	|| &_br ||
			'EXEC SYS.DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION( ' || &_trcsid_session_id || ' ,' || &_trcsid_session_serial || ', true);' 
		WHEN &_trcsid_session_v = 6 THEN
			'PROMPT SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => TRUE  , BINDS => TRUE);' 	|| &_br ||
			'EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => TRUE  , BINDS => TRUE);'
		WHEN &_trcsid_session_v = 7 THEN
			'PROMPT SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => FALSE , BINDS => TRUE);' 	|| &_br ||
			'EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => FALSE , BINDS => TRUE);' 				
		WHEN &_trcsid_session_v = 8 THEN
			'PROMPT EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => TRUE  , BINDS => FALSE);' 	|| &_br ||
			'EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => TRUE  , BINDS => FALSE);'
		WHEN &_trcsid_session_v = 9 THEN
			'PROMPT SQL> EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => FALSE  , BINDS => FALSE);' 	|| &_br ||
			'EXEC SYS.DBMS_MONITOR.SESSION_TRACE_ENABLE( SESSION_ID => ' || &_trcsid_session_id || ', SERIAL_NUM => ' || &_trcsid_session_serial || ', WAITS => FALSE  , BINDS => FALSE);'
		ELSE
			'PROMPT SQL> EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 12, NM=>'''');' 	|| &_br ||
			'EXEC SYS.DBMS_SYSTEM.SET_EV(SI =>' || &_trcsid_session_id || ', SE =>' || &_trcsid_session_serial ||', EV => 10046, LE => 12, NM=>'''');' 
	END CASE
FROM dual 
UNION
SELECT  
	CASE WHEN &_trcsid_session_v <> 0 THEN
		'SELECT tracefile as TRACE_FILE ' ||
		'FROM   v$process   pro, v$session   se ' ||
		'WHERE  se.sid   	= 	&_trcsid_session_id ' ||
		'AND 	se.serial# 	= 	&_trcsid_session_serial ' ||
		'AND 	pro.addr 	= 	se.paddr;' 
	ELSE '' END case
FROM dual ORDER BY 1
/

--@sql_fsx_tracesid.tmp1

UNDEFINE _trcsid_session_v
UNDEFINE _trcsid_session_id
UNDEFINE _trcsid_session_serial