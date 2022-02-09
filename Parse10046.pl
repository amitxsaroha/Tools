#!/bin/sh
#
# trace_report
#
# Creates a report ($1.lst) of a specific Oracle trace dump file.
#
# INSTRUCTIONS:
#
# trace_report is a Unix shell script, which when executed with a trace
# file name as its only parameter, will create a report of the trace file,
# somewhat similar to a normal tkprof report, but much more detailed with
# lots of embedded analysis.
#
# If the trace file was created by using event 10046 level 4, 8, 12 or
# DBMS_SUPPORT, wait and/or bind statistics will be included in the output
# report.
#
# To analyze the generated output file, start at the bottom and work your
# way back towards the top:
#
# 1) Examine the GRAND TOTAL SECS on the last 2 lines.  If the times are
#    very short, you can stop working with this trace file, as it does not
#    take a excessively long period of time to execute.
#
# 2) Examine the ORACLE TIMING ANALYSIS section right above the grand totals.
#    This shows where all of the time was spent while running the traced SQL.
#    This section may cause you to investigate system tuning events and/or
#    latches, if that is where the majority of the time is being spent.
#    (If the ORACLE TIMING ANALYSIS section is missing, this indicates that
#    all operations were completed in less than .01 seconds).
#
# 3) If most of the time was spent in events related to the actual SQL being
#    traced, then examine the SUMMARY OF TOTAL CPU TIME, ELAPSED TIME, WAITS,
#    AND I/O PER CURSOR (SORTED BY DESCENDING ELAPSED TIME) section.  This
#    sorts the individual cursors, in descending order of their total
#    contribution of elapsed time to the total time for the entire trace.
#    Usually, one or two of the cursors are disproportinately large, showing
#    that the majority of time is spent during one of those cursors.  For
#    each cursor ID (listed in the first column), go back and look at the
#    detail for that cursor, as listed earlier in the report.  The rest of
#    the report lists each of the cursors, in ascending order of cursor ID.
#    (A quick way to locate a specific cursor is to search for a pound sign
#    (#) followed by the cursor ID number.  For example, if Cursor ID 12 is
#    the one taking the most time, then search for "#12" to locate the
#    detail for that specific cursor.
#
# 4) For each cursor ID, the trace file will include the actual SQL executed
#    for that cursor, any bind values that were passed, and counts and times
#    for all parses, executes, and fetches.  This lets you see how much work
#    that cursor performed, and how much time that took.
#
#    For disk I/O operations, an average time to read one block, in
#    milliseconds, is printed.
#
#    A summary list of any wait events is given, showing the length of time per
#    wait, along with any relevant data file number and block number.  As of
#    Oracle 10gR2, if present, wait event summaries are also further summarized
#    by each unique object ID.
#
#    For disk I/O operations, a disk read time histogram report is printed.
#    This shows the number of reads and blocks, for different time buckets.
#    This easily lets you see if the disk I/O is being performed quickly or
#    slowly, and where most of the disk I/O time is being spent.
#
#    Assuming the cursor is closed, the rows source operations and row counts
#    will also be listed.
#
#    As of Oracle 9iR2, if present, segment-level statistics are also listed in
#    the report, so you can measure the counts and times for each individual
#    segment.  
#
# The above analysis enables you to easily, quickly, and accurately pinpoint
# the cause of any excessive time spent while executing a SQL statement (or
# PL/SQL package, procedure, or function).
#
# This script is very efficient - It can processes 10 or more megabytes of
# trace file data per minute (depending on the number of cursors and the
# number of wait events in the trace file).  (It has been tested with up to a
# 1000 MB trace dump file).
#
# NOTES:
#
# Bug 7522002 in Oracle 11.1.0.7 can invalidate most/all of the trace timings:
# 1) Timestamps repeat across multiple lines, excluding WAITs.  Non-wait lines
#    list e=0 until tim= changes, then account for all elapsed time on one line.
#    This problem occurs on Solaris, Linux, and Windows, but it may be generic
#    across all platforms.
# 2) Timestamps on WAIT lines convert ns to us as gethrtime()/1024 while
#    timestamps on all other lines use gethrtime()/1000.  This appears to make
#    the time jump forward and backward by large amounts.
#    This problem has been verified on HP/UX, AIX, Solaris, and some Linux
#    platforms.  As of Oracle 11.2, it appears that microseconds are used on all
#    platforms.
# 3) As of Oracle version 11, the execution plan (STAT lines) has been amended
#    so that they are not aggregated across all executions but are dumped after
#    each execution.  This has been done to address cases where the cursor is
#    not closed and the STAT information is therefore not dumped.  This change
#    guarantees that STAT information will be included, even if the cursor is
#    not closed.
# 4) As of Oracle version 11, the execution plan (STAT lines) are only written
#    to the trace file only for the first execution.  Two new levels have been
#    added to allow you to change this behavior:
#      Level 16 prints STAT lines for all executions (instead of only for the
#	 first execution), as printing only the first execution may be
#	 misleading.  (This event can also be set by using the "alter session
#	 set events 'sql_trace wait=true, bind=true, plan_stat=all_executions';"
#	 command.)
#      Level 32 will cause STAT lines to never be written to the trace file.
# 5) As of version 11.2.0.2, a level of 64 will print STAT lines for every
#    minute of dbtime per shared cursor, thereby giving information for the
#    more expensive SQLs and for different executions of such SQLs.  This event
#    was added to address an overly-large trace file, in the event that level
#    16 was specified (especially useful when tracing PL/SQL cursors).  (This
#    event can also be set by using the "alter session set events 'sql_trace
#    wait=true, bind=true, plan_stat=adaptive';" command.)
#
# Bug 13004894 in Oracle 11.2.0.3 can cause wrong results with SQL_TRACE/10046
# if the SQL contains expressions.  The problem can actually occur if statistics
# collection row sources are used in the plan so there may be some additional
# cases where these are present without explicit tracing.  Workaround: Disable
# the 10046 or sql_trace.  Fixed in 12.1.
#
# Bug 8342329 in Oracle 11.1.0.7 can invalidate trace timings on HP/UX, Solaris,
# and AIX.
#
# Bug 3009359 in Oracle 9.2.0.3 and 9.2.0.4: Setting SQL_TRACE to TRUE (or
# using the 10046 event) causes excessive CPU utilization when row source
# statistics are collected.  Caused by the fix for Oracle bug 2228280 in
# 9.2.0.3.  Fixed in 9.2.0.5, 10.1.0.2.
#
# The TIMED_STATISTICS init.ora parameter should be set to TRUE.  Without
# this, all of the critically important timing data will be omitted from the
# resulting trace file.  (This is a dynamic parameter, which can be set via
# ALTER SESSION or ALTER SYSTEM).
#
# The MAX_DUMP_FILE_SIZE parameter limits the maximum size of a trace dump
# file.  As database intensive operations can generate up to 1meg of trace
# data per second, this parameter must set be high enough, so that the trace
# file is not truncated.  (This is also a dynamic parameter, which can be set
# via ALTER SESSION or ALTER SYSTEM).
#
# To perform an actual trace, after ensuring that the preceding two init.ora
# parameters have been set, issue the following command for the session that
# is to be traced:
#
#	ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';
#
# Then, execute the SQL (or package, procedure, or function) to be traced.
#
# When the SQL finishes, stop the trace by issuing the following command (or
# terminate the SQL session):
#
#	ALTER SESSION SET EVENTS '10046 trace name context off';
#
# The resulting trace file will be found in the 'user_dump_dest' directory.
# Typically, it's the last file in that directory (when sorted by date).
# This is the input file name to be used with this script.
#
# Note:  If a session has an open 10046 trace file, you can force it to be
#        closed by typing:
#		sqlplus "/ as sysdba"
#		oradebug setospid <pid>
#			(where <pid> is the operating system PID of the process
#			 which has the open trace file)
#		oradebug flush
#		oradebug close_trace
#
# Parameters:
# $1 = Oracle Trace Dump File to to analyzed.
# $2 = (optional) Specify any value to enable debug mode.
#
# This script has been tested on the following Oracle and O/S versions:
#
#	Oracle 8.1.5, 8.1.7.4, 9.2.0.4, 9.2.0.5, 9.2.0.6, 10.1.0.2, 10.2.0.1,
#	11.1.0.6, 11.1.0.7, 11.2.0.1, 11.2.0.2, 12.1.0.1, 12.1.0.2
#
#	AIX 5.2, 6
#	HP-UX 11.11, 11.23
#	Linux 2.6.12, 2.6.16, 2.6.18.8-0.7, 2.6.21, 2.6.24-19, 2.6.27-17,
#	      2.6.32, 3.2.0-57, 3.2.0-74
#	Solaris 9, 10
#
#	(This script should be O/S-independent.  Its only dependency is
#	 the version of awk or nawk that is being used.  Different O/S
#	 implementations may limit your process address space to a
#	 different amount.  If there is insufficient process memory
#	 available, this script may run much slower than on other O/S
#	 platforms.  Ensure that your 'ulimit' parameters are as high
#	 as possible.)
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015 by
# Brian Lomasky, DBA Solutions, Inc.  All rights reserved.
#
# The latest version of trace_report can always be found on the web site:
# http://www.dbasolutionsinc.com
#
# The author can be contacted at: lomasky@dbasolutionsinc.com
#
# <<<<<<<<<< MODIFICATION HISTORY >>>>>>>>>>
# 04/15/15	Brian Lomasky	Fix printing of segment-level statistics.
#				  Fix PARSE ERROR processing.
#				  Handle "VM name" and blank lines.
# 04/10/15	Brian Lomasky	Handle CLIENT DRIVER line in 12.1.0.2.
# 03/04/15	Brian Lomasky	Add LOBAPPEND, LOBARRREAD, LOBARRTMPFRE,
#				  LOBARRWRITE, LOBTMPFRE operations.  Do not
#				  check for delimiters for parameters and sql
#				  text.  Add Top 5 statements per event.  Fix
#				  XCTEND cursor and hash_value assignment.w
#				  Combine all files with same hash value into
#				  one file.  Fix optimizer goal printing.  Apply
#				  all waits to prior parsed cursor (if
#				  possible).  Print all different execution
#				  plans.  Print wait events lasting less than
#				  1ms.  Handle wait events that occur before and
#				  after a cursor.  Document new level numbers.
# 08/20/14	Brian Lomasky	Process LOBGETLEN.  Fix PARSE ERROR processing.
#				  Fix bind variable value printing.
# 07/30/14	Brian Lomasky	Skip close/open of same cursor.  Fix to include
#				  "Trace file" syntax.
# 07/27/14	Brian Lomasky	Fix cursor id in total wait events by cursor.
#				  Ensure all curno are alphanumeric type.
#				  Remove recursive/uid from total waits, as
#				  these do not appear in WAIT lines.
# 12/06/13	Brian Lomasky	Include container id.
# 08/27/13	Brian Lomasky	Remove escape chars within awk text.
# 03/12/13	Brian Lomasky	Fix find_cursor to check from last cursor to
#				  first, so we find the most recent PARSING IN
#				  CURSOR match.  Do not separate wait event
#				  processing, as there is no way to match a
#				  wait event to the prior cursor (when the
#				  cursor number is being reused).  Include
#				  percent sign in disk read histogram percents.
# 12/13/12	Brian Lomasky	Move "next" out of find_cursor into body.
# 11/29/12	Brian Lomasky	Change "on line" to "near line", due to extract
#				  of wait events from original trace file.  Skip
#				  toid pointer.  Process LOBREAD, LOBPGSIZE,
#				  LOBWRITE.  Keep cursor numbers as a character.
#				  Do not replace large cursor numbers.
# 06/25/12	Brian Lomasky	Summarize total/min/avg/max wait events for
#				  SQL*Net message from client,
#				  SQL*Net message to client,
#				  SQL*Net break/reset to client,
#				  read by other session.
# 03/22/12	Brian Lomasky	Document Oracle 11.2.0.3 bug.
# 03/19/12	Brian Lomasky	Add option to display all line numbers.  Handle
#				  large cursor numbers in 11.2.0.2.  Do not
#				  error if duplicate service names.  Add trap
#				  to cleanup temp directory. Omit elapsed wall
#				  clock time.
# 11/16/11	Brian Lomasky	Print any warning messages in trace file.
#				  Handle very large values in event histograms
#				  and segment-level statistics by converting
#				  them to K/M/G.
# 10/25/11	Brian Lomasky	Fix Grand Total Non-Idle Waits calculation.  Add
#				  Grand Total Table Scans to make it easier to
#				  find trace files having queries that might
#				  have missing indexes.
# 06/09/11	Brian Lomasky	Print timing gap message if > 5% gap time.
# 03/21/11	Brian Lomasky	Attempt to process LOBREAD (Oracle 11.2[.0.2?]).
# 03/03/10	Brian Lomasky	Document additional 11.1.0.7 bug.
# 11/18/09	Brian Lomasky	Skip "An invalid number has been seen".
# 06/14/09	Brian Lomasky	Print information at end of timing analysis if
#				  unaccounted-for time is more than 10%.
# 04/13/09	Brian Lomasky	Retry input file read via "strings" if awk fails
#				  with an error.
# 03/09/09	Brian Lomasky	Document oradebug flush, 11.1.0.7 trace bugs.
# 02/09/09	Brian Lomasky	Include module and action detail and subtotals.
#				  Add missing cursor total.  Do not round
#				  cursor wait event totals.
# 12/10/08	Brian Lomasky	Handle 11.1.0.7 trace file format (CLOSE #n,
#				  plh).  As of 11g, traces have started to
#				  replace P1, P2, and P3 with more meaningful
#				  phrases related to the actual event in
#				  question (See Note 39817.1).
# 10/15/08	Brian Lomasky	Reformat "n more wait events..." lines to not
#				  wrap.  Change Disk Read Histogram heading and
#				  calculation to use ms/reads instead of
#				  ms/block.
# 07/16/08	Brian Lomasky	Skip dupl header warning when finding a hint.
# 06/02/08	Brian Lomasky	Fix error when ordering rowsource STAT lines.
# 04/29/08	Brian Lomasky	Skip "us" after time parameter in STAT line.
# 11/14/07	Brian Lomasky	Print same GRAND TOTAL SECS:, even if zero secs.
#				  Change "Cursor ID" in report to "ID".
#				  Accum waits with no following cursor to the
#				  previous matching cursor.  Add warning and
#				  ignore timing gaps when trace file header is
#				  duplicated.  Adjust grand total secs if
#				  multiple headers found.
# 10/23/07	Brian Lomasky	Fix for missing heading for wait time by cursor
#				  totals.  Reformat segment-level statistics
#				  detail line.
# 10/12/07	Brian Lomasky	Handle 11.1.0.6 Client ID, SQL ID, Segment stats
#				  cost, size, and cardinality.
# 08/08/07	Brian Lomasky	Handle all null bind values.
# 07/04/07	Brian Lomasky	Print total number of bind values found in the
#				  trace file.  Include any null bind values.
#				  Wrap long bind values.
# 12/07/06	Brian Lomasky	Handle onlined undo segments.  Rename timing gap
#				  variables for debugging.
# 12/06/06	Brian Lomasky	Fix File Number/Block Number calculation.  Add
#				  total wait events by cursor totals.  Include
#				  cursor ID 0.
# 11/16/06	Brian Lomasky	Include Partition Start and Partition End stats.
#				  Fix line percentage calculation.
#				  Print text if TRACE DUMP CONTINUES IN FILE or
#				  TRACE DUMP CONTINUED FROM FILE found.
# 09/27/06	Brian Lomasky	Include SQL hash values.  Handle RPC CALL,
#				  RPC BIND, RPC EXEC for Oracle Forms clients.
#				  Cleanup /tmp files.  Limit cursor debug to
#				  every 10 cursors.  Include automatic DOS->Unix
#				  file conversion.  Fix bind value extraction.
# 09/19/06	Brian Lomasky	Handle embedded "no oacdef" for bind variables.
# 08/02/06	Brian Lomasky	Fix max cursor number debug info.  Fixed line
#				  counter.
# 07/20/06	Brian Lomasky	Optimize performance for pending wait lookups
#				  and large directories.  Enhance debugging.
# 07/10/06	Brian Lomasky	Certify for AIX 5.2.
# 06/22/06	Brian Lomasky	Include summary of block revisits by file numb.
# 05/18/06	Brian Lomasky	Include oradebug info in comments.
# 04/17/06	Brian Lomasky	Workaround for HP-UX awk restriction of more
#				  than 199 columns:  Replace embedded spaces
#				  around any "." and before any ",".
# 03/20/06	Brian Lomasky	Include summary of block revisits, explanation
#				  of why scattered read blocks may be less than
#				  db_file_multiblock_read_count.  Include 10.2
#				  object numbers.  Certify for Oracle versions
#				  8.1.5, 8.1.7.4, 9.2.0.5, 10.1.0.2.  Embedded
#				  instructions.
# 03/15/06	Brian Lomasky	Skip any embedded memory dumps.  Skip any
#				  wrapped bind values.  Handle new format of
#				  10.2 wait event parameters.
# 03/05/06	Brian Lomasky	Modify WAIT parameter parsing.  Convert
#				  microsecond times to centiseconds to
#				  avoid 32-bit limitations and scientific
#				  notation conversion.
# 03/03/06	Brian Lomasky	Added grand total debug info.  Fixed unwanted
#				  scientific notation format for large total
#				  elapsed times.  Rewrite grand totals.
#				  Certified for Linux 2.6.12.
# 02/07/06	Brian Lomasky	Document TRACE DUMP CONTINUES IN FILE text.
#				  Ensure parsing values are treated as numerics.
# 10/26/05	Brian Lomasky	Change heading for Disk Read Histogram Summary
#				  to indicate read time in secs is for blocks.
#				  Skip XCTEND and STAT if no hash value found.
# 08/31/05	Brian Lomasky	Support 10.2 modified bind syntax.
# 08/15/05	Brian Lomasky	Read /etc/profile instead of /etc/passwd, in
#				  case /etc/passwd is read-protected.
# 07/19/05	Brian Lomasky	Print additional status messages.
# 07/12/05	Brian Lomasky	Handle appended trace files.
# 06/13/05	Brian Lomasky	Summarize significant wait events.
# 06/05/05	Brian Lomasky	Accum wait events by P3 param.  Include
#				  disk read histogram throughput.  Fix bug
#				  for skipped wait times < 1ms.  Add max and
#				  avg ms per wait event.  Add wait event hist.
# 06/01/05	Brian Lomasky	Fix total lines counter.  Print only one
#				  truncate warning.  Handle 10.1 ACTION NAME, 
#				  MODULE NAME, SERVICE NAME, QUERY, bind
#				  peeking, optimizer parameters, Column usage
#				  monitoring, QUERY BLOCK SIGNAGE,
#				  BASE STATISTICAL INFORMATION, COLUMN, Size,
#				  Histogram, SINGLE TABLE ACCESS PATH, STAT
#				  pr= and pw= values, "Oracle Database" header.
#				  Skip non-10046 trace files.  Include any PQO
#				  waits in Oracle Timing Events.  Include count
#				  of waits and avg ms per wait to subtotals.
# 03/12/05	Brian Lomasky	Fix wait order bug, bind order bug, double-
#				  counted recursive totals.  Add unaccounted-for
#				  time, timing gap errors, gap processing,
#				  bind variable reporting format, timing
#				  summary.
# 02/08/05	Brian Lomasky	Added subtotals and percents to grand total.
#				  Handle bind variables with embedded blanks.
#				  Print 2 lines for very long bind values.
# 01/25/05	Brian Lomasky	Include unaccounted for waits or errors (in the
#				  event a trace was started in the middle of a
#				  session).  Include avg time to read a block.
#				  Include read time histogram summary per
#				  cursor.
# 08/10/04	Brian Lomasky	Added warning about truncated dump file.
# 08/02/04	Brian Lomasky	Added additional debug mode info.  Ignore error
#				  time, since it may be more than 2gig.  Fix
#				  for no recursive depth for cursor zero.
# 06/01/04	Brian Lomasky	Fix next error within do_parse.  Add missing
#				  percent and comma in elapsed time total.
# 01/30/04	Brian Lomasky	Include cursor 0.  Added debug mode.  Skip
#				  lines which have a non-existent cursor,
#				  except for cursor #0 (to handle a partial
#				  trace file).
# 11/23/03	Brian Lomasky	Change filtering and format of wait events.
# 11/20/03	Brian Lomasky	Handle embedded tilde in object name.  Handle
#				  out of order bind values.  Fix error in grand
#				  total time calc.  Fix too long awk command.
#				  Omit SQL*Net message from client from grand
#				  total non-idle wait events.
# 10/29/03	Brian Lomasky	Include Oracle 9.2 segment-level statistics.
# 06/24/03	Brian Lomasky	Include parse error values.  Handle zero hv.
#				  Accum duplicate waits into one line.  Skip
#				  waits for cursor 0.
# 06/11/03	Brian Lomasky	Include bind values.  Skip waits for 0 time.
#				  Add descending sort by elapsed fetch times.
# 04/02/03	Brian Lomasky	Add sub total by wait events per cursor.
# 03/17/03	Brian Lomasky	Optimize speed.  Calc proper divisor for Oracle
#				  9.0+ timings.  Use nawk instead of awk, if
#				  available.  Add grand total elapsed times.
#				  Add sorted elapsed time summary.  Include
#				  non-idle wait event detail and summary, latch
#				  detail, enqueue detail.  Handle truncated
#				  trace files.  Check for gap.  Check for
#				  unexpected lines.
# 07/12/01	Brian Lomasky	Original
#
# Note: If the input trace file contains:
#	*** TRACE DUMP CONTINUES IN FILE /file ***
#	*** TRACE DUMP CONTINUED FROM FILE /file ***
# this usually means that an "ALTER SESSION SET TRACEFILE_IDENTIFIER = 'xxx';"
# command was issued.  The file names listed reference the prior and/or next
# file which contains the contents of the trace.
#
# This is also caused by using MTS shared servers.  As the traces are performed
# by the server processes, you can get a piece of the trace in each of the
# background processes which execute your SQL.  To create a valid file for
# trace_report to process, you should combine the multiple pieces into a single
# trace file, or use the trcsess utility (as of Oracle 10.1).
#
# If the same file is listed in "TRACE DUMP CONTINUES IN FILE" and "TRACE DUMP
# CONTINUED FROM FILE", this is usually caused by trying to set a
# tracefile_identifier while using MTS.  Since setting a tracefile_identifier
# does not work under MTS, it is possible that these messages are due to
# someone attempting to set a tracefile identifier, and Oracle calling the
# "TRACE DUMP CONTINUES IN FILE" and "TRACE DUMP CONTINUED FROM FILE" routines
# without actually changing the filename.
#
cleanup() {
	echo "Cleaning up..."
	rm -Rf $tmpf
	trap - QUIT INT KILL TERM
	exit 0
}
if [ $# -eq 0 ]
then
	echo "Error - You must specify the trace dump file as a parameter" \
		"- Aborting..."
	exit 2
fi
if [ ! -r $1 ]
then
	echo "Error - Can't find file: $1 - Aborting..."
	exit 2
fi
grep 'PARSING IN CURSOR' $1 > /dev/null 2>&1
if [ $? -ne 0 ]
then
	echo "Error - File $1 is not from a 10046 trace - Skipping..."
	exit 2
fi

if [ $# -eq 2 ]
then
	debug=1
	if [ "$2" = "T" ]
	then
		trace_lines=1		# Display all line numbers
	else
		trace_lines=0
	fi
else
	debug=0
	trace_lines=0
fi
#
# See if nawk should be used instead of awk
#
(nawk '{ print ; exit }' /etc/profile) > /dev/null 2>&1
if [ ${?} -eq 0 ]
then
	cmd=nawk
else
	cmd=awk
fi
# Execute whoami in a subshell so as not to display a "not found" error message
( whoami ) > /dev/null 2>&1
if [ $? -eq 0 ]
then
	tmpf="/tmp/`whoami`$$"
else
	( /usr/ucb/whoami ) > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		tmpf="/tmp/`/usr/ucb/whoami`$$"
	else
		if [ -z "$LOGNAME" ]
		then
			tmpf="/tmp/`logname`$$"
		else
			tmpf="/tmp/${LOGNAME}$$"
		fi
	fi
fi
outf=`basename $1 .trc`.lst
cat /dev/null > $outf
rm -Rf $tmpf
mkdir $tmpf
trap cleanup QUIT INT KILL TERM
mkdir $tmpf/binds
mkdir $tmpf/rpcbinds
mkdir $tmpf/rpccpu
mkdir $tmpf/params
cat /dev/null > $tmpf/cmdtypes
cat /dev/null > $tmpf/cursors
cat /dev/null > $tmpf/init
cat /dev/null > $tmpf/eof
cat /dev/null > $tmpf/elap
cat /dev/null > $tmpf/fetch
cat /dev/null > $tmpf/duplheader
cat /dev/null > $tmpf/modules
cat /dev/null > $tmpf/actions
echo 0 > $tmpf/truncated
cat /dev/null > $tmpf/waitsela
cat /dev/null > $tmpf/waitst
cat /dev/null > $tmpf/waitstotcur
cat /dev/null > $tmpf/waitstotmod
cat /dev/null > $tmpf/waitstotact
mkdir $tmpf/xctend
now=`date +'%H:%M:%S'`
echo "Processing trace file at ${now}..."
cat <<EOF > trace_report.awk
BEGIN {
	abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	all_cursors = 0
	eof_cursors = 0
	module = " "
	action = " "
	all_wait_tot = 0
	parsing = 0
	binds = 0
	found_first_stat = 0
	header = 0
	offset_time = 0
	rpc_binds = 0
	peeked = "    "
	oacdef = 0
	found9999 = 0
	hv = 0
	linctr = 0
	zerondx = 0
	abort_me = 0
	gap_time = 0
	gap_cnt = 0
	prev_time = 0
	parameters = 0
	printed_head = 0
	skip_to_equal = 0
	skip_dump = 0
	skip_to_nonquo = 0
	stat_ndx = 0
	toid = 0
	rpc_call = 0
	rpcndx = 0
	rpc_zero = ""
	cpu_timing_parse = 0
	cpu_timing_exec = 0
	cpu_timing_rpcexec = 0
	cpu_timing_fetch = 0
	cpu_timing_unmap = 0
	cpu_timing_sort = 0
	cpu_timing_close = 0
	cpu_timing_lobread = 0
	cpu_timing_lobgetlen = 0
	cpu_timing_lobpgsize = 0
	cpu_timing_lobwrite = 0
	cpu_timing_lobappend = 0
	cpu_timing_lobarrread = 0
	cpu_timing_lobarrtmpfre = 0
	cpu_timing_lobarrwrite = 0
	cpu_timing_lobtmpfre = 0
	cpu_timing_parse_cnt = 0
	cpu_timing_exec_cnt = 0
	cpu_timing_rpcexec_cnt = 0
	cpu_timing_fetch_cnt = 0
	cpu_timing_unmap_cnt = 0
	cpu_timing_sort_cnt = 0
	cpu_timing_close_cnt = 0
	cpu_timing_lobread_cnt = 0
	cpu_timing_lobgetlen_cnt = 0
	cpu_timing_lobpgsize_cnt = 0
	cpu_timing_lobwrite_cnt = 0
	cpu_timing_lobappend_cnt = 0
	cpu_timing_lobarrread_cnt = 0
	cpu_timing_lobarrtmpfre_cnt = 0
	cpu_timing_lobarrwrite_cnt = 0
	cpu_timing_lobtmpfre_cnt = 0
	multi_line_value = 0
	ncur = 0
	next_line_bind_value = 0
	parse_ncur = 0
	parse_curno = 0
	parse_hv = 0
	prevdep = 999
	reccpu = 0
	recela = 0
	hash_ndx = 0
	divisor = 1				# Centiseconds
	uid = ""
	oct = ""
	dmi[1] = 31
	dmi[2] = 31
	dmi[3] = 30
	dmi[4] = 31
	dmi[5] = 31
	dmi[6] = 30
	dmi[7] = 31
	dmi[8] = 31
	dmi[9] = 30
	dmi[10] = 31
	dmi[11] = 30
	dmi[12] = 31
	first_time = 0
	prev_tim = 0
	last_tim = 0
	pct = 0
	print_trunc = 0
} function ymdhms(oratim) {
	nyy = yy + 0
	nmm = mm + 0
	ndd = dd + 0
	nhh = hh + 0
	nmi = mi + 0
	nss = ss + int((oratim - first_time) / 100)
	while (nss > 59) {
		nss = nss - 60
		nmi = nmi + 1
	}
	while (nmi > 59) {
		nmi = nmi - 60
		nhh = nhh + 1
	}
	while (nhh > 23) {
		nhh = nhh - 24
		ndd = ndd + 1
	}
	if (nmm == 2) {
		if (nyy == 4 * int(nyy / 4)) {
			if (nyy == 100 * int(nyy / 100)) {
				if (nyy == 400 * int(nyy / 400)) {
					dmi[2] = 29
				} else {
					dmi[2] = 28
				}
			} else {
				dmi[2] = 29
			}
		} else {
			dmi[2] = 28
		}
	}
	while (ndd > dmi[nmm]) {
		ndd = ndd - dmi[nmm]
		nmm = nmm + 1
	}
	while (nmm > 12) {
		nmm = nmm - 12
		nyy = nyy + 1
	}
	return sprintf("%2.2d/%2.2d/%2.2d %2.2d:%2.2d:%2.2d", \\
		nmm, ndd, nyy, nhh, nmi, nss)
} function find_cursor() {
	if (trace_lines > 0) print "  find cursor " curno
	# Locate the hash value index for this cursor (starting with the last)
	xx = all_cursors
	mtch = 0
	while (xx > 0) {
		if (allcurs[xx] == curno) {
			mtch = xx
			xx = 0
		}
		--xx
	}
	if (mtch == 0) {
		if (curno == "0") {
			if (zerondx == 0) {
				++ncur
				zerondx = ncur
				hashvals[ncur] = 0
				curnos[ncur] = "0"
				octs[ncur] = "0"
				sqlids[ncur] = "."
				uids[ncur] = "x"
				deps[ncur] = 0
				gap_tims[ncur] = 0
				if (debug != 0) print "  Storing cursor #0" \\
					" in array " ncur
				printf \\
			      "%4d %18d %12d  0 %s %s %s %s %s %s %s %s %s\n",\\
					ncur, 0, 0, "x", "x", 0, 0, 0, "x", \\
					0, ".", 0 >> cursors
			}
			hv = 0
			oct = "0"
			uid = "x"
			cpu = 0
			elapsed = 0
			disk = 0
			query = 0
			current = 0
			rows = 0
			misses = 0
			op_goal = 0
			sqlid = "."
			tim = 0
		} else {
			#
			# Init array elements for "unaccounted for" time
			#
			hashvals[9999] = 1
			curnos[9999] = "0"
			octs[9999] = "0"
			sqlids[9999] = "."
			uids[9999] = "x"
			deps[9999] = 0
			gap_tims[9999] = 0
			if (found9999 == 0) {
				if (debug != 0) print "  Storing cursor #9999"
				printf \\
			      "%4d %18d %12d  0 %s %s %s %s %s %s %s %s %s\n",\\
					9999, curno, 1, "x", "x", 0, 0, \\
					0, "x", 0, ".", 0 >> cursors
				found9999 = 1
			}
			hv = 1
			oct = "0"
			uid = "x"
			xx = 9999
			++all_cursors
			allcurs[all_cursors] = "9999"
			allindxs[all_cursors] = 0
			if (debug != 0) print "Storing cursor 9999 for" \\
				" unaccounted time on line " NR
		}
		#skip_to_equal = 1
		return -1
	} else {
		# Return array index (ncur) that holds the data for this cursor
		xx = allindxs[mtch]
		# print "  Line " NR ": Cursor " curno " hash index is " xx \\
		#	" hash=" hv
		if (xx == 0) {
			if (curno == "0") {
				xx = zerondx
			} else {
				xx = 9999
			}
		}
		hv = hashvals[xx]
		oct = octs[xx]
		sqlid = sqlids[xx]
		uid = uids[xx]
		gap_tim = gap_tims[xx]
		return xx
	}
} function check_lins() {
	lins = lins + 1
	if (10 * lins > totlins) {
		if (debug != 0) print "  lins=" lins " totlins=" totlins
		pct = pct + 10
		print "Processed " pct "% of all trace file data..."
		lins = 1
	}
} function do_parse() {
	if (trace_lines > 0) print "do parse " NR
	# Check for null bind value
	if (next_line_bind_value == 1) {
		next_line_bind_value = 0
		if (binds == 1) {
			if (oacdef == 1) {
				if (trace_lines > 0) print "write oacdef=1" NR
				fil = tmpf "/binds/" cur
				printf "%4s %11d    %-44s %10d\n", \\
					peeked, varno + 1, "<null>", NR >> fil
				close(fil)
				# Incr number of binds
				++bindvars[cur]
			}
		}
	}
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	binds = 0
	rpc_binds = 0
	peeked = "    "
	dep = 0
	oacdef = 0
	multi_line_value = 0
	# Use prior cursor if not reading/writing LOBs
	if (\$1 != "LOBREAD:" && \$1 != "LOBPGSIZE:" && \$1 != "LOBWRITE:" \\
		&& \$1 != "LOBAPPEND:" && \$1 != "LOBARRREAD:" && \\
		\$1 != "LOBARRTMPFRE:" && \$1 != "LOBARRWRITE:" && \\
		\$1 != "LOBTMPFRE:") {
		pound = index(\$2, "#")
		colon = index(\$2, ":")
		curno = substr(\$2, pound + 1, colon - pound - 1) ""
		orig_curno = curno
	}
	if (trace_lines > 0) print "  checking cursor " curno " ncur " ncur
	if (curno == "0" || ncur != 0) {
		cur = find_cursor()
		if (cur > 0) {
			op = \$1
			if (debug != 0) print "  op=" op
			if (\$1 == "PARSE") op = "1"
			if (\$1 == "EXEC") op = "2"
			if (\$1 == "FETCH") op = "3"
			if (\$1 == "UNMAP") op = "4"
			if (\$1 == "SORT UNMAP") op = "5"
			if (\$1 == "CLOSE") op = "6"
			if (\$1 == "LOBREAD:") {
				op = "7"
				#print "DEBUG>Found LOBREAD near line " NR
			}
			if (\$1 == "LOBPGSIZE:") {
				op = "8"
				#print "DEBUG>Found LOBPGSIZE near line " NR
			}
			if (\$1 == "LOBWRITE:") {
				op = "9"
				#print "DEBUG>Found LOBWRITE near line " NR
			}
			if (\$1 == "LOBGETLEN:") {
				op = "10"
				#print "DEBUG>Found LOBGETLEN near line " NR
			}
			if (\$1 == "LOBAPPEND:") {
				op = "11"
				#print "DEBUG>Found LOBAPPEND near line " NR
			}
			if (\$1 == "LOBARRREAD:") {
				op = "12"
				#print "DEBUG>Found LOBARRREAD near line " NR
			}
			if (\$1 == "LOBARRTMPFRE:") {
				op = "13"
				#print "DEBUG>Found LOBARRTMPFRE near line " NR
			}
			if (\$1 == "LOBARRWRITE:") {
				op = "14"
				#print "DEBUG>Found LOBARRWRITE near line " NR
			}
			if (\$1 == "LOBTMPFRE:") {
				op = "15"
				#print "DEBUG>Found LOBTMPFRE near line " NR
			}
			if (op == \$1) {
				print "Unexpected parameter for parse (" \$1 \\
					") found near line " NR
			} else {
				if (debug != 0) print "   Storing " \$1 \\
					" for curno " curno " in " cur \\
					", NR=" NR
				cpu = 0
				elapsed = 0
				disk = 0
				query = 0
				current = 0
				misses = 0
				rows = 0
				dep = 0
				op_goal = 0
				plh = 0
				type = 0
				tim = 0
				sqlid = "."
				two = substr(\$2, index(\$2, ":") + 1)
				a = split(two, arr, ",")
				for (x=1;x<=a;x++) {
					equals = index(arr[x], "=")
					key = substr(arr[x], 1, equals - 1)
					if (debug != 0) print "     Process" \\
						" key " key ", NR=" NR
					if (key == "c") {
						if (divisor == 1) {
							# Already in
							# centiseconds
							cpu = substr(arr[x], \\
								equals + 1)
						} else {
							# Convert microseconds
							# to centiseconds
							l = length(arr[x])
							if (l - equals > 4) {
								cpu = substr(\\
								  arr[x], \\
								  equals + 1, \\
								  (l - \\
								  equals) \\
								  - 4) "." \\
								  substr(\\
								  arr[x], \\
								  (l - \\
								  equals) - 1)
							} else {
								# Less than .01
								# sec
								cpu = "0." \\
								  substr(\\
								  substr(\\
								  arr[x], 1, \\
								  2) "00000" \\
								  substr(\\
								  arr[x], 3), \\
								  (l - \\
								  equals) + 4)
							}
						}
						continue
					}
					# A database call e is approx equal to
					# its total CPU time plus the sum of
					# its wait event times
					if (key == "e") {
						if (divisor == 1) {
							elapsed = substr(\\
								arr[x], \\
								equals + 1)
						} else {
							# Convert microseconds
							# to centiseconds
							l = length(arr[x])
							if (l - equals > 4) {
								elapsed = \\
								  substr(\\
								  arr[x], \\
								  equals + 1, \\
								  (l - \\
								  equals) \\
								  - 4) "." \\
								  substr(\\
								  arr[x], \\
								  (l - \\
								  equals) - 1)
							} else {
								elapsed = \\
								  "0." \\
								  substr(\\
								  substr(\\
								  arr[x], 1, \\
								  2) "00000" \\
								  substr(\\
								  arr[x], 3), \\
								  (l - \\
								  equals) + 4)
							}
						}
						if (index(elapsed, "+") != 0) {
							print "ERROR:" \\
								" SCIENTIFIC" \\
								" NOTATION" \\
								" FOR " elapsed
						}
						continue
					}
					if (key == "p") {
						disk = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "cr") {
						query = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "cu") {
						current = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "mis") {
						misses = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "r") {
						rows = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "dep") {
						dep = substr(arr[x], \\
							equals + 1)
						if (dep > deps[cur]) \\
							deps[cur] = dep
						continue
					}
					if (key == "og") {
						op_goal = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "plh") {
						plh = substr(arr[x], equals + 1)
						continue
					}
					if (key == "type") {
						type = substr(arr[x], \\
							equals + 1)
						continue
					}
					if (key == "tim") {
						if (divisor == 1) {
							tim = substr(\\
								arr[x], \\
								equals + 1)
						} else {
							l = length(arr[x])
							if (l - equals > 4) {
								tim = substr(\\
								  arr[x], \\
								  equals + 1, \\
								  (l - \\
								  equals) \\
								  - 4) "." \\
								  substr(\\
								  arr[x], \\
								  (l - \\
								  equals) + 1)
							} else {
								tim = "0." \\
								  substr(\\
								  substr(\\
								  arr[x], 1, \\
								  4) "00000" \\
								  substr(\\
								  arr[x], 5), \\
								  (l - \\
								  equals) + 7)
							}
						}
						if (debug != 0) {
							print "do_parse:" \\
								" Read tim= " \\
								tim
						}
						if (tim > last_tim) {
						    if (offset_time > 0) {
							if (debug != 0) {
							  print "do_parse:" \\
								" offset_time"\\
								tim - last_tim
							}
							first_time = \\
								first_time + \\
								tim - last_tim
							if (debug != 0) {
							  printf \\
							    "%s%s%12.4f\n", \\
							    "do_parse:", \\
							    " first_time: ", \\
							    first_time
							}
							offset_time = 0
						    }
						    if (debug != 0) {
							print "do_parse:" \\
								" last_tim= " \\
								last_tim \\
								" NR=" NR
						    }
						    last_tim = tim
						}
						continue
					}
					if (key == "sqlid") {
						sqlid = substr(arr[x], \\
							equals + 1)
						gsub(q,"",sqlid)
						continue
					}
					print "Unexpected parameter for parse"\\
						" found near line " NR ": " \\
						arr[x]
				}
				# Calculate any timing gaps
				if (op == "1") {
					gap_tim = gap_tims[cur]
					gap_tims[cur] = 0
				} else {
					gap_tim = 0
				}
				if (prev_time > 0) {
					gap_tim = sprintf("%d", gap_tim + \\
						tim - (prev_time + \\
						elapsed + all_wait_tot))
				}
				# Zero if within timing degree of precision
				if (gap_tim < 2) gap_tim = 0
				if (gap_tim != 0) {
					if (debug != 0) {
						print "Gap Time err>tim=" tim \\
							", prev_time=" \\
							prev_time
						print "             " \\
							"elapsed=" elapsed \\
							", gap_tim=" gap_tim \\
							", all_wait_tot=" \\
							all_wait_tot ", NR=" NR
					}
					# Accum grand total timing gap
					gap_time = gap_time + gap_tim
					++gap_cnt
				}
				prev_time = tim
				# Accum total CPU timings
				if (op == "1") {
					cpu_timing_parse = cpu_timing_parse + \\
						cpu
					++cpu_timing_parse_cnt
				}
				if (op == "2") {
					cpu_timing_exec = cpu_timing_exec + \\
						cpu
					++cpu_timing_exec_cnt
				}
				if (op == "3") {
					cpu_timing_fetch = cpu_timing_fetch + \\
						cpu
					++cpu_timing_fetch_cnt
				}
				if (op == "4") {
					cpu_timing_unmap = cpu_timing_unmap + \\
						cpu
					++cpu_timing_unmap_cnt
				}
				if (op == "5") {
					cpu_timing_sort = cpu_timing_sort + \\
						cpu
					++cpu_timing_sort_cnt
				}
				if (op == "6") {
					cpu_timing_close = cpu_timing_close + \\
						cpu
					++cpu_timing_close_cnt
				}
				if (op == "7") {
					cpu_timing_lobread = \\
						cpu_timing_lobread + cpu
					++cpu_timing_lobread_cnt
				}
				if (op == "8") {
					cpu_timing_lobpgsize = \\
						cpu_timing_lobpgsize + cpu
					++cpu_timing_lobpgsize_cnt
				}
				if (op == "9") {
					cpu_timing_lobwrite = \\
						cpu_timing_lobwrite + cpu
					++cpu_timing_lobwrite_cnt
				}
				if (op == "10") {
					cpu_timing_lobgetlen = \\
						cpu_timing_lobgetlen + cpu
					++cpu_timing_lobgetlen_cnt
				}
				if (op == "11") {
					cpu_timing_lobappend = \\
						cpu_timing_lobappend + cpu
					++cpu_timing_lobappend_cnt
				}
				if (op == "12") {
					cpu_timing_lobarrread = \\
						cpu_timing_lobarrread + cpu
					++cpu_timing_lobarrread_cnt
				}
				if (op == "13") {
					cpu_timing_lobarrtmpfre = \\
						cpu_timing_lobarrtmpfre + cpu
					++cpu_timing_lobarrtmpfre_cnt
				}
				if (op == "14") {
					cpu_timing_lobarrwrite = \\
						cpu_timing_lobarrwrite + cpu
					++cpu_timing_lobarrwrite_cnt
				}
				if (op == "15") {
					cpu_timing_lobtmpfre = \\
						cpu_timing_lobtmpfre + cpu
					++cpu_timing_lobtmpfre_cnt
				}
				if (prevdep == dep || prevdep == 999) {
					# Accum cpu and elapsed times for all
					# recursive operations
					if (dep > 0) {
						if (cpu > 0 || elapsed > 0) {
							# Store cpu + elapsed
							# time for this
							# recursive call
							reccpu = reccpu + cpu
							recela = sprintf(\\
								"%d", \\
								recela + \\
								elapsed)
						}
					}
				} else {
					# Remove any double-counted recursive
					# times
					if (reccpu > 0 || recela > 0) {
						if (cpu >= reccpu) \\
							cpu = cpu - reccpu
						if (elapsed >= recela) \\
							elapsed = sprintf(\\
								"%d", \\
								elapsed - \\
								recela)
						reccpu = 0
						recela = 0
					}
				}
				prevdep = dep
				printf "%4d %18d %12d  3 %s\n", \\
					cur, curno, hv, op " " cpu " " \\
					elapsed " " disk " " query " " \\
					current " " rows " " misses " " \\
					op_goal " " tim " " gap_tim " " \\
					sqlid " " NR >> cursors
				print oct " " cpu " " elapsed " " disk " " \\
					query " " current " " rows " " uid \\
					" " deps[cur] " " NR >> filcmdtypes
				if (module != " ") {
					print module "~" cpu "~" elapsed "~" \\
						disk "~" query "~" current \\
						"~" rows "~" uid "~" \\
						deps[cur] "~" NR >> filmodules
				}
				if (action != " ") {
					print action "~" cpu "~" elapsed "~" \\
						disk "~" query "~" current \\
						"~" rows "~" uid "~" \\
						deps[cur] "~" NR >> filactions
				}
			}
		}
	}
	all_wait_tot = 0
} function do_parse_cursor() {
	if (trace_lines > 0) print "do parse cursor " NR
	found_first_stat = 0
	skip_dump = 0
	skip_to_nonquo = 0
	binds = 0
	rpc_binds = 0
	peeked = "    "
	oacdef = 0
	multi_line_value = 0
	dep = 0					# Recursive depth
	uid = ""				# User ID
	oct = ""				# Oracle command type
	parsing_tim = 0				# Current Time
	hv = 0					# SQL hash value
	err = "x"				# Oracle error
	sqlid = "."
	wait_sub_total = 0
	for (x=first_field;x<=NF;x++) {
		if (trace_lines > 0) print "  process field " x
		equals = index(\$x, "=")
		if (equals > 0) {
			key = substr(\$x, 1, equals - 1)
			if (key == "len") continue
			if (key == "dep") {
				dep = substr(\$x, equals + 1)
				continue
			}
			if (key == "uid") {
				uid = substr(\$x, equals + 1)
				continue
			}
			if (key == "oct") {
				oct = substr(\$x, equals + 1)
				continue
			}
			if (key == "lid") continue
			if (key == "tim") {
				if (divisor == 1) {
					parsing_tim = substr(\$x, equals + 1)
				} else {
					l = length(\$x)
					if (l - equals > 4) {
						parsing_tim = substr(\$x, \\
							equals + 1, \\
							(l - equals) - 4) "." \\
							substr(\$x, (l - \\
							equals) + 1)
					} else {
						parsing_tim = "0." substr(\\
							substr(\$x, 1, 4) \\
							"00000" \\
							substr(\$x, 5), \\
							(l - equals) + 7)
					}
				}
				if (index(parsing_tim, "+") != 0) {
					print "ERROR: SCIENTIFIC NOTATION" \\
						" FOR PARSING TIME " parsing_tim
				}
				if (debug != 0) {
					print "do_parse_cursor: Read tim= " \\
						parsing_tim
				}
				if (parsing_tim > last_tim) {
				    if (offset_time > 0) {
					if (debug != 0) {
						  print "do_parse_cursor:" \\
							" offset_time: " \\
							parsing_tim - last_tim
					}
					first_time = first_time + parsing_tim \\
						- last_tim
					if (debug != 0) {
						printf "%s%s%12.4f\n", \\
							"do_parse_cursor:", \\
							" first_time: ", \\
							first_time
					}
					offset_time = 0
				    }
				    if (debug != 0) {
						print "do_parse_cursor:" \\
							" last_tim= " \\
							last_tim " NR=" NR
				    }
				    last_tim = parsing_tim
				}
				if (first_time == 0) {
					if (debug != 0) {
						print "store first_time: " \\
							parsing_tim " NR=" NR
					}
					first_time = parsing_tim
				}
				continue
			}
			if (key == "hv") {
				hv = substr(\$x, equals + 1)
				# Use parsing time if no hash value (Bug?)
				if (hv == 0) hv = parsing_tim
				continue
			}
			if (key == "ad") continue
			if (key == "err") {
				err = substr(\$x, equals + 1)
				continue
			}
			if (key == "sqlid") {
				sqlid = substr(\$x, equals + 1)
				gsub(q,"",sqlid)
				continue
			}
			print "Unexpected keyword of " key " in " \$0 \\
				" (line" NR ")"
		}
	}
	gap_tim = 0
	if (prev_time > 0) {
		# Calculate timing gap errors
		if (debug != 0) print "   Curr tim=" parsing_tim \\
			", last tim=" prev_time ", waits=" all_wait_tot \\
			" at NR=" NR
		gap_tim = parsing_tim - (prev_time + all_wait_tot)
		# Zero if within timing degree of precision
		if (gap_tim < 2) gap_tim = 0
		if (gap_tim != 0) {
			if (debug != 0) print "   Found Timing Gap " gap_tim
		}
	}
	if (prev_tim == 0) {
		elapsed_time = 0
	} else {
		elapsed_time = sprintf("%d", parsing_tim - prev_tim)
	}
	prev_tim = parsing_tim
	prev_time = parsing_tim
	all_wait_tot = 0
	# Accum cursors by cursor number and hash value (as there can be many
	#		SQL statements for a single cursor number/hash value)
	x = 0
	hash_ndx = 0
	while (x < ncur) {
		if (trace_lines > 0) print "  check cursor " x " of " ncur
		++x
		if (curnos[x] == curno && hashvals[x] == hv) {
			hash_ndx = x
			x = ncur
		}
	}
	if (hash_ndx == 0) {
		++ncur
		if (trace_lines > 0) print "  store new cursor " curno
		if (debug != 0) print "do_parse_cursor: WRITE CURSOR #" \\
			curno " in " ncur
		cur = ncur
		hashvals[cur] = hv
		octs[cur] = oct
		sqlids[cur] = sqlid
		curnos[cur] = curno ""
		uids[cur] = uid
		deps[cur] = dep
		errs[cur] = err
		gap_tims[cur] = gap_tim
		bindvars[cur] = 0
		rpcbindvars[cur] = 0
		printf "%4d %18d %12d  0 %s %s %s %s %s %s %s %s %s\n", \\
			ncur, curno, hv, oct, uid, dep, elapsed_time, \\
			parsing_tim, err, NR, sqlid, orig_curno >> cursors
		if (module != " ") {
			if (debug != 0) print "do_parse_cursor: Store" \\
				" Module for CURSOR #" curno ": " module
			printf "%4d %18d %12d  8 %s\n",\\
				ncur, curno, hv, module >> cursors
		}
		if (action != " ") {
			if (debug != 0) print "do_parse_cursor: Store" \\
				" Action for CURSOR #" curno ": " action
			printf "%4d %18d %12d  9 %s\n",\\
				0, 0, 0, action >> cursors
		}
		# See if there are any pending waits that match this new cursor
		newpend = 0
		match_cur = 0
		while (getline < pendwaits > 0) {
			if (debug != 0) print "  Read pendwaits : " \$0
			the_wait = substr(\$0, 27)
			elem = split(the_wait, arr, "~")
			if (elem != 7) {
				print "Unexpected number of columns (" elem \\
					") in pending waits wait line #" NR ":"
				print \$5
				continue
			}
			w_curno = \$2
			code = \$4
			nam = arr[1]
			p1 = arr[2]
			p2 = arr[3]
			p3 = arr[4]
			ela = arr[5]
			recnum = arr[6]
			objn = arr[7]
			if (w_curno == curno) {
				if (debug != 0) print "    Write pending wait"
				if (w_code == 4) {
					printf "%4d %18d %12d  4 %s\n",\\
						ncur, curno, hv, \\
						nam "~" p1 "~" p2 "~" p3 \\
						"~" ela "~" recnum "~" objn \\
						>> cursors
				}
				if (w_code == 6) {
					printf "%4d %18d %12d  6 %s\n",\\
						ncur, curno, hv, \\
						nam "~" objn "~" p1 "~" \\
						p2 "~" p3 "~" ela "~" recnum \\
						>> cursors
				}
				match_cur = 1
			} else {
				if (debug != 0) print "    Xfer non-matching" \\
					" pending wait"
				printf "%4d %18d %12d %2d %s\n",\\
					0, w_curno, 0, code, nam "~" p1 "~" \\
					p2 "~" p3 "~" ela "~" recnum "~" objn \\
					>> newpendwaits
				newpend = 1
			}
		}
		close(pendwaits)
		if (newpend == 0) {
			if (match_cur > 0) {
				system("rm -f " pendwaits)
			}
		} else {
			close(newpendwaits)
			if (match_cur == 0) {
				system("rm -f " newpendwaits)
			} else {
				# Transfer all newpendwaits back into pendwaits
				system("mv -f " newpendwaits " " pendwaits)
			}
		}
		parse_ncur = ncur
		parse_curno = curno
		parse_hv = hv
	} else {
		cur = hash_ndx
		if (debug != 0) print "do_parse_cursor: Use CURSOR #" \\
			curno " from " cur
		gap_tims[cur] = gap_tims[cur] + gap_tim
		parse_ncur = cur
		parse_curno = curnos[cur]
		parse_hv = hashvals[cur]
	}
	# print "  Store Cursor " curno " hash " hv " index of " cur \\
	#	" on line " NR
	if (trace_lines > 0) print "  Store Cursor " curno
	++all_cursors
	allcurs[all_cursors] = curno ""
	allindxs[all_cursors] = cur
	allhvs[all_cursors] = hv
	return 0
} /^\/[A-Za-z]/ {
	if (trace_lines > 0) print "A-Z " NR
	if (abort_me == 2) next
	if (header == 0) {
		totlins = 10 * int((totlins + 9) / 10)
	}
	if (printed_head == 0) {
		print "Oracle Trace Dump File Report" >> outf
		print "" >> outf
		print "NOTE:  SEE THE TEXT AT THE TOP OF THE TRACE_REPORT" \\
			" SCRIPT FOR INSTRUCTIONS" >> outf
		print "       REGARDING HOW TO INTERPRET THIS REPORT!" >> outf
		print "" >> outf
		print "count       = Number of times OCI procedure was" \\
			" executed" >> outf
		print "cpu         = CPU time executing, in seconds" >> outf
		print "elapsed     = Elapsed time executing, in seconds" >> outf
		print "disk        = Number of physical reads of buffers" \\
			" from disk" >> outf
		print "query       = Number of buffers gotten for consistent" \\
			" read" >> outf
		print "current     = Number of buffers gotten in current" \\
			" mode (usually for update)" >> outf
		print "rows        = Number of rows processed by the fetch" \\
			" or execute call" >> outf
		print "" >> outf
		print "Trace File  = " \$1 >> outf
		printed_head = 1
	} else {
		print ""
		print "*** Warning: Multiple trace file headings are in the" \\
			" trace file!"
		print ""
		print "             The extra trace header starts on trace" \\
			" line " NR
		print ""
		# Zero previous time, so no timing gap will be calculated
		prev_time = 0
		# Zero time, so no elapsed time will be printed
		prev_tim = 0
		# Set flag to offset new first_time after new header
		if (first_time == 0) {
			offset_time = 0
		} else {
			offset_time = 1
		}
		fil = tmpf "/duplheader"
		print NR >> fil
		close(fil)
	}
	lins = 1
	next
} /^Trace file/ {
	if (trace_lines > 0) print "dump file " NR
	if (abort_me == 2) next
	totlins = 10 * int((totlins + 9) / 10)
	if (printed_head == 0) {
		print "Oracle Trace Dump File Report" >> outf
		print "" >> outf
		print "NOTE:  SEE THE TEXT AT THE TOP OF THE TRACE_REPORT" \\
			" SCRIPT FOR INSTRUCTIONS" >> outf
		print "       REGARDING HOW TO INTERPRET THIS REPORT!" >> outf
		print "" >> outf
		print "count       = Number of times OCI procedure was" \\
			" executed" >> outf
		print "cpu         = CPU time executing, in seconds" >> outf
		print "elapsed     = Elapsed time executing, in seconds" >> outf
		print "disk        = Number of physical reads of buffers" \\
			" from disk" >> outf
		print "query       = Number of buffers gotten for consistent" \\
			" read" >> outf
		print "current     = Number of buffers gotten in current" \\
			" mode (usually for update)" >> outf
		print "rows        = Number of rows processed by the fetch" \\
			" or execute call" >> outf
		print "" >> outf
		print "Trace File  = " \$3 >> outf
		printed_head = 1
	}
	lins = 1
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Dump file/ {
	if (trace_lines > 0) print "dump file " NR
	if (abort_me == 2) next
	totlins = 10 * int((totlins + 9) / 10)
	if (printed_head == 0) {
		print "Oracle Trace Dump File Report" >> outf
		print "" >> outf
		print "NOTE:  SEE THE TEXT AT THE TOP OF THE TRACE_REPORT" \\
			" SCRIPT FOR INSTRUCTIONS" >> outf
		print "       REGARDING HOW TO INTERPRET THIS REPORT!" >> outf
		print "" >> outf
		print "count       = Number of times OCI procedure was" \\
			" executed" >> outf
		print "cpu         = CPU time executing, in seconds" >> outf
		print "elapsed     = Elapsed time executing, in seconds" >> outf
		print "disk        = Number of physical reads of buffers" \\
			" from disk" >> outf
		print "query       = Number of buffers gotten for consistent" \\
			" read" >> outf
		print "current     = Number of buffers gotten in current" \\
			" mode (usually for update)" >> outf
		print "rows        = Number of rows processed by the fetch" \\
			" or execute call" >> outf
		print "" >> outf
		print "Trace File  = " \$3 >> outf
		printed_head = 1
	}
	lins = 1
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Oracle9/ {
	xx = check_lins()
	divisor = 10000				# Convert Microseconds to Centi
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Oracle1/ {
	xx = check_lins()
	divisor = 10000				# Convert Microseconds to Centi
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Oracle Database 9/ {
	xx = check_lins()
	divisor = 10000				# Convert Microseconds to Centi
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Oracle Database 1/ {
	xx = check_lins()
	divisor = 10000				# Convert Microseconds to Centi
	cursors = tmpf "/cursors"
	pendwaits = tmpf "/pendwaits"
	newpendwaits = tmpf "/newpendwaits"
	filwaitsela = tmpf "/waitsela"
	filcmdtypes = tmpf "/cmdtypes"
	filmodules = tmpf "/modules"
	filactions = tmpf "/actions"
	filwaitst = tmpf "/waitst"
	filwaitsmod = tmpf "/waitstotmod"
	filwaitsact = tmpf "/waitstotact"
	next
} /^Node name:/ {
	if (abort_me == 2) next
	xx = check_lins()
	if (header == 0) print "Node Name   = " \$3 >> outf
	next
} /^Instance name:/ {
	if (abort_me == 2) next
	xx = check_lins()
	if (header == 0) print "Instance    = " \$3 >> outf
	next
} /^Unix process pid:/ {
	if (abort_me == 2) next
	xx = check_lins()
	x = \$6
	for(i=7;i<=NF;i++) x = x " " \$i
	print "Image       = " x >> outf
	next
} /^\*\*\*\*\*\*/ {
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	next
} /^==============/ {
	if (trace_lines > 0) print "equals " NR
	xx = check_lins()
	header = 1
	skip_to_equal = 0
	skip_dump = 0
	skip_to_nonquo = 0
	if (next_line_bind_value == 1) {
		next_line_bind_value = 0
		if (binds == 0) {
			print "Error - Found kxsbbbfp but no Bind# on trace" \\
				" line " NR ": " \$0
		} else {
			if (oacdef == 1) {
				if (trace_lines > 0) print "write oacdef=1" NR
				fil = tmpf "/binds/" cur
				printf "%4s %11d    %-44s %10d\n", \\
					peeked, varno + 1, "<null>", NR >> fil
				close(fil)
				# Incr number of binds
				++bindvars[cur]
			}
		}
	}
	next
} /^Dump of memory/ {
	xx = check_lins()
	skip_dump = 1
	skip_to_nonquo = 0
	next
} /^\*\*\* ACTION NAME:/ {
	if (trace_lines > 0) print "action name " NR
	if (abort_me == 2) next
	xx = check_lins()
	x = index(\$0, "(")
	y = 0
	yx = 1
	while (yx > 0) {
		yx = index(substr(\$0, y + 1), ")")
		if (yx > 0) {
			y = yx + y
		}
	}
	if (header == 0) {
		if (y > x + 1) {
			print "Action      = " substr(\$0,x+1,y-x-1) >> outf
		}
	}
	if (y > x + 1) {
		action = substr(\$0,x+1,y-x-1)
		if (debug != 0) print "***** Found Action " action \\
			" on line " NR "..."
	}
	next
} /^\*\*\* CLIENT DRIVER:/ {
	xx = check_lins()
	next
} /^\*\*\* CONTAINER ID:/ {
	if (trace_lines > 0) print "container id " NR
	if (abort_me == 2) next
	xx = check_lins()
	x = index(\$0, "(")
	y = 0
	yx = 1
	while (yx > 0) {
		yx = index(substr(\$0, y + 1), ")")
		if (yx > 0) {
			y = yx + y
		}
	}
	if (header == 0) {
		if (y > x + 1) {
			print "Container   = " substr(\$0,x+1,y-x-1) >> outf
		}
	}
	next
} /^\*\*\* MODULE NAME:/ {
	if (trace_lines > 0) print "module name " NR
	if (abort_me == 2) next
	xx = check_lins()
	x = index(\$0, "(")
	y = 0
	yx = 1
	while (yx > 0) {
		yx = index(substr(\$0, y + 1), ")")
		if (yx > 0) {
			y = yx + y
		}
	}
	if (header == 0) {
		if (y > x + 1) {
			print "Module      = " substr(\$0,x+1,y-x-1) >> outf
		}
	}
	if (y > x + 1) {
		module = substr(\$0,x+1,y-x-1)
		if (debug != 0) print "***** Found Module " module \\
			" on line " NR "..."
	}
	next
} /^\*\*\* SERVICE NAME:/ {
	if (trace_lines > 0) print "service name " NR
	#if (abort_me == 2) next
	#if (abort_me == 1) {
	#	print ""
	#	print "THIS TRACE FILE WAS APPENDED TO AN EARLIER CREATED" \\
	#		" TRACE FILE!"
	#	print ""
	#	print "MANUALLY EDIT THE TRACE FILE AND REMOVE THE EARLIER" \\
	#		" SECTION!"
	#	print ""
	#	next
	#}
	#++abort_me
	xx = check_lins()
	if (header == 0) {
		x = index(\$3, "(")
		y = index(\$3, ")")
		if (y > x + 1) print "Service     = " substr(\$3,x+1,y-x-1) \\
			>> outf
	}
	next
} /^\*\*\* SESSION ID:/ {
	if (trace_lines > 0) print "session id " NR
	if (abort_me == 2) next
	xx = check_lins()
	if (header == 0) {
		x = index(\$3, "(")
		y = index(\$3, ")")
		print "Session ID  = " substr(\$3,x+1,y-x-1) >> outf
		print "Date/Time   = " \$4 " " \$5 >> outf
		start_date = \$4			# yyyy-mm-dd
		yy = substr(start_date, 1, 4)
		mm = substr(start_date, 6, 2)
		dd = substr(start_date, 9, 2)
		start_time = \$5			# hh:mm:ss.ccc
		hh = substr(start_time, 1, 2)
		mi = substr(start_time, 4, 2)
		ss = substr(start_time, 7, 2)
	}
	next
} /^\*\*\* CLIENT ID:/ {
	if (abort_me == 2) next
	xx = check_lins()
	if (header == 0) {
		x = index(\$3, "(")
		y = index(\$3, ")")
		print "Client ID  = " substr(\$3,x+1,y-x-1) >> outf
	}
	next
} /^APPNAME/ {
	if (abort_me == 2) next
	xx = check_lins()
	if (header == 0) {
		x = index(\$0, q)
		y = index(substr(\$0,x+1), q) + x
		if (y > x + 1) print "Application = " substr(\$0,x+1,y-x-1) \\
			>> outf
		zero = substr(\$0, y + 1)
		x = index(zero, q)
		y = index(substr(zero,x+1), q) + x
		if (y > x + 1) print "Action      = " substr(\$0,x+1,y-x-1) \\
			>> outf
	}
	next
} /^PARSING IN CURSOR/ {
	if (trace_lines > 0) print "parsing in cursor " NR
	if (abort_me == 2) next
	xx = check_lins()
	peeked = "    "
	parameters = 0
	parsing = 1
	curno = \$4 ""
	gsub("#","",curno)			# Cursor number
	orig_curno = curno
	if (debug != 0) print "***** Processing cursor #" curno " on line " \\
		NR "..."
	first_field = 5
	x = do_parse_cursor() \$0
	next
} /^QUERY/ {
	if (trace_lines > 0) print "query " NR
	if (abort_me == 2) next
	xx = check_lins()
	# Try appending the query block to the end of the prior
	# PARSING IN CURSOR?
	skip_dump = 0
	skip_to_nonquo = 0
	parsing = 1
	next
} /^Column Usage Monitoring/ {
	if (trace_lines > 0) print "column usage monitoring " NR
	if (abort_me == 2) next
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	skip_to_equal = 1
	next
} /^QUERY BLOCK SIGNAGE/ {
	if (trace_lines > 0) print "query block signage " NR
	if (abort_me == 2) next
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	skip_to_equal = 1
	next
} /^BASE STATISTICAL INFORMATION/ {
	if (trace_lines > 0) print "base statistical information " NR
	if (abort_me == 2) next
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	skip_to_equal = 1
	next
} /^SINGLE TABLE ACCESS PATH/ {
	if (trace_lines > 0) print "single table access path " NR
	if (abort_me == 2) next
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	skip_to_equal = 1
	next
} /^Peeked values/ {
	if (trace_lines > 0) print "peeked values " NR
	if (abort_me == 2) next
	xx = check_lins()
	if (debug != 0) print "  Processing bind peek #" curno " (cur " cur \\
		") on line " NR "..."
	binds = 1
	peeked = "Peek"
	oacdef = 0
	next_line_bind_value = 0
	multi_line_value = 0
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^PARAMETERS/ {
	if (trace_lines > 0) print "parameters " NR
	if (abort_me == 2) next
	xx = check_lins()
	parameters = 1
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^RPC CALL:/ {
	if (trace_lines > 0) print "rpc call " NR
	if (abort_me == 2) next
	xx = check_lins()
	cur = find_cursor()
	if (skip_to_equal == 1) next
	if (debug != 0) print "  Processing rpc call #" curno " (hash index " \\
		cur ") on line " NR "..."
	rpc_zero = substr(\$0, 10)
	rpc_call = 1
	next
} /^RPC BINDS:/ {
	if (trace_lines > 0) print "rpc binds " NR
	x = 0
	rpcndx = 0
	fil = tmpf "/rpccalls"
	while (getline < fil > 0) {
		++x
		if (\$0 == rpc_zero) rpcndx = x
	}
	close(fil)
	if (rpcndx == 0) {
		print rpc_zero >> fil
		close(fil)
		rpcndx = x + 1
	}
	rpc_call = 0
	if (abort_me == 2) next
	xx = check_lins()
	cur = find_cursor()
	if (skip_to_equal == 1) next
	if (debug != 0) print "  Processing rpc bind #" curno " (cur " cur \\
		") on line " NR "..."
	rpc_binds = 1
	peeked = "    "
	next_line_bind_value = 0
	oacdef = 0
	multi_line_value = 0
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^BINDS/ {
	if (trace_lines > 0) print "binds " NR
	if (abort_me == 2) next
	rpc_call = 0
	rpc_binds = 0
	xx = check_lins()
	curno = \$2 ""
	gsub("#","",curno)
	gsub(":","",curno)
	orig_curno = curno
	cur = find_cursor()
	if (skip_to_equal == 1) next
	if (debug != 0) print "  Processing bind #" curno " (cur " cur \\
		") on line " NR "..."
	binds = 1
	peeked = "    "
	dty = -1
	next_line_bind_value = 0
	oacdef = 0
	multi_line_value = 0
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^ bind / {
	if (trace_lines > 0) print "bind " NR
	if (abort_me == 2) next
	xx = check_lins()
	if (rpc_binds != 0) {
		varno = \$2
		gsub(":","",varno)		# Bind variable number
		equals = index(\$3, "=")
		# Data type(1=VARCHAR2,2=NUMBER,12=DATE)
		dty = substr(\$3, equals + 1)
		oacdef = 0
		skip_dump = 0
		skip_to_nonquo = 0
		if (index(\$0, "(No oacdef for this bind)") != 0) {
			# "No oacdef for this bind" indicates binding by name
			fil = tmpf "/rpcbinds/" rpcndx
			printf "%4s%s%4d%-38s%s%8d\n", \\
				" ", "Bind Number: ", varno + 1, \\
				"   (No separate bind buffer exists)", \\
				" Trace line: ", NR >> fil
			close(fil)
			oacdef = 1
			next
		}
		equals = index(\$0, "val=") + 3
		if (equals == 3) {
			print "No rpc bind value found on trace line " \\
				NR ": " \$0
			next
		}
		if (equals == length(\$0)) {
			multi_line_value = 1
		} else {
			if (substr(\$0, length(\$0) - 1) == "=\\"") {
				multi_line_value = 2
			} else {
				val = substr(\$0, equals + 1)
				if (debug != 0) print \\
					"  Bind value " val " on " NR
				if (substr(val, 1, 1) == "\\"") {
					quote = index(substr(val, 2), "\\"")
					if (quote != 0) {
						val = substr(val, 2, quote - 1)
					} else {
						skip_to_nonquo = 1
					}
				}
				if (skip_to_nonquo == 0) {
					if (debug != 0) print \\
						"  Store rpc bind[" varno \\
						"] value: " val \\
						" for rpcndx " rpcndx
					fil = tmpf "/rpcbinds/" rpcndx
					printf "%4s%s%4d%s%-25s%s%8d\n", \\
						" ", "Bind Number: ", \\
						varno + 1, \\
						" Bind Value: ", \\
						substr(val, 1, 25), \\
						" Trace line: ", NR >> fil
					if (length(val) > 25) {
						printf "%34s%-25s\n", " ", \\
							substr(\$0, 26, 25) \\
							>> fil
					}
					if (length(val) > 50) {
						printf "%34s%-25s\n", " ", \\
							substr(\$0, 51, 25) \\
							>> fil
					}
					close(fil)
					# Incr number of rpc binds
					++rpcbindvars[rpcndx]
				}
			}
		}
		next
	}
	if (binds == 0) {
		print "Unprocessed bind line near trace line " NR ": " \$0
		next
	}
	varno = \$2
	gsub(":","",varno)			# Bind variable number
	equals = index(\$3, "=")
	dty = substr(\$3, equals + 1)		# Data type(1=VARCHAR2,2=NUMBER)
	oacdef = 0
	if (index(\$0, "(No oacdef for this bind)") != 0) {
		# "No oacdef for this bind" indicates binding by name
		if (trace_lines > 0) print "write oacdef=1" NR
		fil = tmpf "/binds/" cur
		printf "     %11d    %44s %10d\n", varno + 1, \\
			"(No separate bind buffer exists)", NR >> fil
		close(fil)
		oacdef = 1
	}
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^   bfp/ {
	if (trace_lines > 0) print "bfp " NR
	if (abort_me == 2) next
	xx = check_lins()
	if (binds == 0) {
		print "Unprocessed bfp line near trace line " NR ": " \$0
		next
	}
	#if (oacdef == 0) {
	#	equals = index(\$0, "avl=") + 3
	#	space = index(substr(\$0, equals), " ")
	#	avl = substr(\$0, equals + 1, space - 2) + 0
	#}
	skip_dump = 0
	skip_to_nonquo = 0
	next
} /^ Bind#/ {
	if (trace_lines > 0) print "bind# " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	# Check for null bind value
	if (next_line_bind_value == 1) next_line_bind_value = 0
	if (binds == 1) {
		if (oacdef == 1) {
			if (trace_lines > 0) print "write oacdef=1" NR
			fil = tmpf "/binds/" cur
			printf "%4s %11d    %-44s %10d\n", \\
				peeked, varno + 1, "<null>", NR >> fil
			close(fil)
			# Incr number of binds
			++bindvars[cur]
		}
	}
	xx = check_lins()
	if (rpc_binds != 0) {
		pound = index(\$1, "#")
		varno = substr(\$1, pound + 1)	# Bind variable number
		next
	}
	if (binds == 0) {
		print "Unprocessed Bind# line near trace line " NR ": " \$0
		next
	}
	pound = index(\$1, "#")
	varno = substr(\$1, pound + 1)		# Bind variable number
	if (trace_lines > 0) print "bind variable " varno
	next
} /^  No oacdef for this bind./ {
	if (trace_lines > 0) print "no oacdef  " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (rpc_binds != 0) {
		# "No oacdef for this bind" indicates binding by name
		fil = tmpf "/rpcbinds/" rpcndx
		printf "%4s%s%4d%-38s%s%8d\n", \\
			" ", "Bind Number: ", varno + 1, \\
			"   (No separate bind buffer exists)", \\
			" Trace line: ", NR >> fil
		close(fil)
		oacdef = 1
		next
	}
	if (binds == 0) {
		print "Unprocessed no oacdef line near trace line " NR ": " \$0
		next
	}
	# "No oacdef for this bind" indicates binding by name
	if (trace_lines > 0) print "write oacdef=1" NR
	fil = tmpf "/binds/" cur
	printf "     %11d    %44s %10d\n", varno + 1, \\
		"(No separate bind buffer exists)", NR >> fil
	close(fil)
	oacdef = 1
	next
} /^  oacdty=/ {
	if (trace_lines > 0) print "oacdty " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (rpc_binds != 0) {
		#equals = index(\$1, "=")
		# Data type(1=VARCHAR2,2=NUM,12=DATE)
		#dty = substr(\$1, equals + 1) + 0
		next
	}
	if (binds == 0) {
		print "Unprocessed oacdty line near trace line " NR ": " \$0
		next
	}
	if (dty < 0) {
		equals = index(\$1, "=")
		# Data type(1=VARCHAR2,2=NUMBER,12=DATE)
		dty = substr(\$1, equals + 1) + 0
		if (trace_lines > 0) print "bind datatype " dty
	}
	next
} /^  oacflg=/ {
	if (trace_lines > 0) print "oacflg " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (rpc_binds != 0) next
	if (binds == 0) {
		print "Unprocessed oacflg line near trace line " NR ": " \$0
		next
	}
	next
} /^toid ptr/ {
	toid = 1
	xx = check_lins()
	next
} /^  kxsbbbfp=/ {
	if (trace_lines > 0) print "kxsbbbfp " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	next_line_bind_value = 1
	xx = check_lins()
	if (rpc_binds != 0) next
	if (binds == 0) {
		print "Unprocessed kxsbbbfp line near trace line " NR ": " \$0
		next
	}
	next
} /^PARSE ERROR #/ {
	if (trace_lines > 0) print "parse error " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	peeked = "    "
	parameters = 0
	parsing = 1
	if (debug != 0) print "  PARSE ERROR: " \$0 " on " NR
	curno = \$3 ""
	gsub("#","",curno)
	colon = index(curno, ":")
	if (colon > 0) curno = substr(curno, 1, colon - 1)
	orig_curno = curno
	if (debug != 0) print "***** Processing cursor #" curno \\
		" error on line " NR "..."
	first_field = 4
	x = do_parse_cursor() \$0
	next
} /^==/ {
	if (trace_lines > 0) print "equal " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	parsing = 0
	parameters = 0
	next
} /^END OF STMT/ {
	if (trace_lines > 0) print "end of statement " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	parsing = 0
	parameters = 0
	next
} /^PARSE #/ {
	if (trace_lines > 0) print "parse " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^EXEC #/ {
	if (trace_lines > 0) print "exec " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^RPC EXEC:/ {
	if (trace_lines > 0) print "rpc exec " NR
	if (abort_me == 2) next
	xx = check_lins()
	skip_dump = 0
	skip_to_nonquo = 0
	binds = 0
	rpc_binds = 0
	rpc_call = 0
	peeked = "    "
	oacdef = 0
	multi_line_value = 0
	if (curno == "0" || ncur != 0) {
		cur = find_cursor()
		if (skip_to_equal == 1) next
		if (cur > 0) {
			if (debug != 0) print "   Using curno " curno ", NR=" NR
			cpu = 0
			elapsed = 0
			two = substr(\$2, index(\$2, ":") + 1)
			a = split(two, arr, ",")
			for (x=1;x<=a;x++) {
				equals = index(arr[x], "=")
				key = substr(arr[x], 1, equals - 1)
				if (key == "c") {
					if (divisor == 1) {
						# Already in centiseconds
						cpu = substr(arr[x], \\
							equals + 1)
					} else {
						# Convert microseconds
						# to centiseconds
						l = length(arr[x])
						if (l - equals > 4) {
							cpu = substr(arr[x], \\
							  equals + 1, \\
							  (l - equals) - 4) \\
							  "." substr(arr[x], \\
							  (l - equals) - 1)
						} else {
							# Less than .01 sec
							cpu = "0." substr(\\
							  substr(arr[x], 1, \\
							  2) "00000" \\
							  substr(arr[x], 3), \\
							  (l - equals) + 4)
						}
					}
					continue
				}
				# A database call e is approx equal to
				# its total CPU time plus the sum of
				# its wait event times
				if (key == "e") {
					if (divisor == 1) {
						elapsed = substr(arr[x], \\
							equals + 1)
					} else {
						l = length(arr[x])
						if (l - equals > 4) {
							elapsed = \\
							  substr(arr[x], \\
							  equals + 1, \\
							  (l - equals) \\
							  - 4) "." \\
							  substr(arr[x], \\
							  (l - equals) - 1)
						} else {
							elapsed = "0." \\
							  substr(substr(\\
							  arr[x], 1, 2) \\
							  "00000" \\
							  substr(arr[x], 3), \\
							  (l - equals) + 4)
						}
					}
					if (index(elapsed, "+") != 0) {
						print "RPC ERROR: SCIENTIFIC" \\
							" NOTATION FOR " elapsed
					}
					continue
				}
				print "Unexpected parameter for rpc exec"\\
					" found near line " NR ": " arr[x]
			}
			# Accum total RPC CPU timings
			cpu_timing_rpcexec = cpu_timing_rpcexec + cpu
			++cpu_timing_rpcexec_cnt
			fil = tmpf "/rpccpu/" rpcndx
			print cpu " " elapsed >> fil
			close(fil)
		}
	}
	next
} /^FETCH #/ {
	if (trace_lines > 0) print "fetch " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^UNMAP #/ {
	if (trace_lines > 0) print "unmap " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^SORT UNMAP #/ {
	if (trace_lines > 0) print "sort unmap " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^CLOSE #/ {
	if (trace_lines > 0) print "close " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBREAD/ {
	if (trace_lines > 0) print "lobread " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBGETLEN/ {
	if (trace_lines > 0) print "lobgetlen " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBPGSIZE/ {
	if (trace_lines > 0) print "lobpgsize " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBWRITE/ {
	if (trace_lines > 0) print "lobwrite " NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBAPPEND/ {
	if (trace_lines > 0) print "lobappend" NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBARRREAD/ {
	if (trace_lines > 0) print "lobarrread" NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBARRTMPFRE/ {
	if (trace_lines > 0) print "lobarrtmpfre" NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBARRWRITE/ {
	if (trace_lines > 0) print "lobarrwrite" NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^LOBTMPFRE/ {
	if (trace_lines > 0) print "lobtmpfre" NR
	if (abort_me == 2) next
	x = do_parse() \$0
	next
} /^ERROR #/ {
	if (trace_lines > 0) print "error " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	pound = index(\$2, "#")
	colon = index(\$2, ":")
	curno = substr(\$2, pound + 1, colon - pound - 1) ""
	orig_curno = curno
	cur = find_cursor()
	if (skip_to_equal == 1) next
	if (cur > 0) {
		zero = \$0
		gsub("= ","=",zero)
		errpos = index(zero, "err=")
		timpos = index(zero, "tim=")
		err = substr(zero, errpos + 4, timpos - 5 - errpos)
		if (divisor == 1) {
			# Already in centiseconds
			errti = substr(zero, timpos + 4)
		} else {
			# Convert microseconds to centiseconds
			l = length(zero)
			if (l - timpos > 7) {
				errti = substr(zero, timpos + 4, \\
					(l - timpos) - 7) "." \\
					substr(zero, l - 3)
			} else {
				errti = "0." substr(\\
					substr(zero, 1, 4) "00000" \\
					substr(zero, 5), (l - timpos) + 3)
			}
		}
		tim = parsing_tim + errti
		printf "%4d %18d %12d  7 %s\n",\\
			cur, curno, hv, err "~" NR "~" tim >> cursors
		if (debug != 0) print "    Write Error: " err " " \\
			NR " " tim " parsing_tim=" parsing_tim " errti=" errti
	}
	next
} /^WAIT/ {
	if (trace_lines > 0) print "wait " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	pound = index(\$2, "#")
	colon = index(\$2, ":")
	curno = substr(\$2, pound + 1, colon - pound - 1) ""
	orig_curno = curno
	if (curno == "0") {
		if (zerondx == 0) {
			++ncur
			zerondx = ncur
			hashvals[ncur] = 0
			curnos[ncur] = "0"
			octs[ncur] = "0"
			sqlids[ncur] = "."
			uids[ncur] = "x"
			deps[ncur] = 0
			gap_tims[ncur] = 0
			if (debug != 0) print "  Storing cursor #0 in array " \\
				ncur
			printf \\
			      "%4d %18d %12d  0 %s %s %s %s %s %s %s %s %s\n",\\
				ncur, 0, 0, "x", "x", 0, 0, 0, "x", 0, ".", 0 \
				>> cursors
			if (module != " ") {
				printf "%4d %18d %12d  8 %s\n",\\
					ncur, 0, 0, module >> cursors
			}
			if (action != " ") {
				printf "%4d %18d %12d  9 %s\n",\\
					ncur, 0, 0, action >> cursors
			}
			hv = 0
			oct = "0"
			uid = "x"
			cpu = 0
			elapsed = 0
			disk = 0
			query = 0
			current = 0
			rows = 0
			misses = 0
			op_goal = 0
			sqlid = "."
			tim = 0
			cur = ncur
		}
	}
	cur = find_cursor()
	zero = \$0
	if (debug != 0) print "  " NR " Read Wait Event: " \$0
	gsub("= ","=",zero)
	nampos = index(zero, "nam=")
	elapos = index(zero, "ela=")
	if (debug != 0) print "  elapos=" elapos
	nam = substr(zero, nampos + 5, elapos - 7 - nampos)
	ela = 0
	p1 = 0
	p2 = 0
	p3 = 0
	objn = 0
	wtim = 0
	fx = 0
	xx = 3
	parm = " "
	pno = 0
	while (xx < NF) {
		++xx
		if (fx == 1) {
			fx = 0
			if (parm == "ela") {
				if (divisor == 1) {
					ela = \$xx
				} else {
					l = length(\$xx)
					if (l > 4) {
						ela = substr(\$xx, 1, \\
							l - 4) "." \\
							substr(\$xx, l - 3)
					} else {
						ela = "0." substr("00000" \\
							\$xx, l + 2)
					}
				}
			} else {
				pno = pno + 1
				if (pno == 1) p1 = val
				if (pno == 2) p2 = val
				if (pno == 3) p3 = val
				if (substr(\$xx,1,5) == "obj#=") \\
					objn = substr(\$xx, 6)
				if (substr(\$xx,1,4) == "tim=") {
					if (divisor == 1) {
						wtim = substr(\$xx, 5)
					} else {
						l = length(\$xx)
						if (l > 8) {
							wtim = substr(\$xx, \\
							    5, l - 8) "." \\
							    substr(\$xx, l - 3)
						} else {
							wtim = "0." substr(\\
							    "00000" \$xx, l + 2)
						}
					}
				}
			}
			if (parm == " ") {
				print "Unexpected WAIT parameter(" \\
					parm ") found on line " NR ": " \$0
			}
			continue
		}
		equals = index(\$xx, "=")
		if (equals == 0) continue
		parm = substr(\$xx, 1, equals - 1)
		if (equals == length(\$xx)) {
			fx = 1
			continue
		}
		val = substr(\$xx, equals + 1)
		if (parm == "ela") {
			if (divisor == 1) {
				ela = val
			} else {
				l = length(val)
				if (l > 4) {
					ela = substr(val, 1, l - 4) \\
						"." substr(val, l - 3)
				} else {
					ela = "0." substr("00000" val, l + 2)
				}
			}
		} else {
			pno = pno + 1
			if (pno == 1) p1 = val
			if (pno == 2) p2 = val
			if (pno == 3) p3 = val
			if (substr(\$xx,1,5) == "obj#=") objn = substr(\$xx, 6)
			if (substr(\$xx,1,4) == "tim=") {
				if (divisor == 1) {
					wtim = substr(\$xx, 5)
				} else {
					l = length(\$xx)
					if (l > 8) {
						wtim = substr(\$xx, 5, l - 8) \\
							"." substr(\$xx, l - 3)
					} else {
						wtim = "0." substr("00000" \\
							\$xx, l + 2)
					}
				}
			}
		}
		fx = 0
	}
	if (debug != 0) {
		if (ela == 0) {
			print "  Skipping wait event ela=0: " nam
		} else {
			print "  Storing wait event: " nam ", ela=" ela \\
				", p1=" p1 ", p2=" p2 ", p3=" p3 ", objn=" \\
				objn ", wtim=" wtim ", NR=" NR
		}
	}
	if (nam == "buffer busy waits") nam = nam " (code=" p3 ")"
	if (nam == "db file scattered read") nam = nam " (blocks=" p3 ")"
	if (nam == "latch activity") nam = nam " (latch#=" p2 ")"
	if (nam == "latch free") nam = nam " (latch#=" p2 ")"
	if (nam == "latch wait") nam = nam " (latch#=" p2 ")"
	if (nam == "enqueue") {
		# Convert P1 to hex
		if (p1 > 15) {
			val = p1
			v_mod = ""
			while (val > 15) {
				v_hex_mod = sprintf("%x", val % 16)
				v_mod = v_hex_mod v_mod
				val = int(val/16)
			}
			v_hex = sprintf("%x", val) v_mod
		} else {
			v_hex = sprintf("%x", p1)
		}
		c1 = (substr(v_hex,1,1) * 16 + substr(v_hex,2,1)) - 64
		c2 = (substr(v_hex,3,1) * 16 + substr(v_hex,4,1)) - 64
		name = substr(abc, c1, 1) substr(abc, c2, 1)
		mod = substr(v_hex, 5) + 0
		mode = "null"
		if (mod == 1) mode = "Null"
		if (mod == 2) mode = "RowS"
		if (mod == 3) mode = "RowX"
		if (mod == 4) mode = "Share"
		if (mod == 5) mode = "SRowX"
		if (mod == 6) mode = "Excl"
		nam = nam " (Name=" name " Mode=" mode ")"
	}
	if (ela != 0) {
		if (curno == "0") {
			if (debug != 0) print "  Storing wait event for curno 0"
			printf "%4d %18d %12d  4 %s\n",\\
				zerondx, 0, 0, nam "~" p1 "~" p2 "~" p3 \\
				"~" ela "~" NR "~" objn >> cursors
			if (objn > 0) printf "%4d %18d %12d  6 %s\n",\\
				zerondx, 0, 0, nam "~" objn "~" p1 "~" p2 "~" \\
				3 "~" ela "~" NR >> cursors
		} else {
			# Store pending wait if processing a wait with no prior
			# cursor number
			if (cur < 0) {
				if (debug != 0) print "No matching cursor " \\
					curno " for wait on line " NR \\
					" - Store pending wait..."
				printf "%4d %18d %12d  4 %s\n",\\
					0, curno, 0, nam "~" p1 "~" p2 "~" p3 \\
					"~" ela "~" NR "~" objn >> pendwaits
				if (objn > 0) printf "%4d %18d %12d  6 %s\n",\\
					0, curno, 0, nam "~" objn "~" p1 "~" \\
					p2 "~" p3 "~" ela "~" NR >> pendwaits
				close(pendwaits)
			} else {
				if (debug != 0) {
					print "  " NR ") Storing waits for" \\
						" cur=" cur " curno=" curno \\
						" nam=" nam " ela=" ela
				}
				wait_sub_total = wait_sub_total + ela
				printf "%4d %18d %12d  4 %s\n", \\
					cur, curno, hv, nam "~" p1 "~" p2 "~" \\
					p3 "~" ela "~" NR "~" objn >> cursors
				if (objn > 0) printf "%4d %18d %12d  6 %s\n", \\
					cur, curno, hv, nam "~" objn "~" \\
						p1 "~" p2 "~" p3 "~" ela "~" \\
						NR >> cursors
			}
		}
		all_wait_tot = all_wait_tot + ela
		print nam "~" p1 "~" p2 "~" ela >> filwaitst
		if (module != " ") {
			print module "~" nam "~" p1 "~" p2 "~" ela \
				>> filwaitsmod
		}
		if (action != " ") {
			print action "~" nam "~" p1 "~" p2 "~" ela \
				>> filwaitsact
		}
	}
	next
} /^XCTEND/ {
	if (trace_lines > 0) print "xctend " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (parse_hv == 0) {
		print "No hash value found for XCTEND on line " NR
		next
	}
	parsing = 0
	parameters = 0
	xx = ymdhms(parsing_tim)
	xctrans = "transaction on trace line " NR " at " xx
	cflg = 0
	for (x=2;x<=NF;x++) {
		equals = index(\$x, "=")
		key = substr(\$x, 1, equals - 1)
		val = substr(\$x, equals + 1)
		if (key == "rlbk") {
			if (val != "0,") cflg = 1
		}
		if (key == "rd_only") {
			if (val != "0") {
				xctrans = "READ-ONLY " xctrans
			} else {
				xctrans = "UPDATE " xctrans
			}
		}
	}
	if (cflg == 0) {
		xctrans = "COMMIT " xctrans
	} else {
		xctrans = "ROLLBACK " xctrans
	}
	printf "%4d %18d %12d 10 %s\n", parse_ncur, parse_curno, parse_hv, \\
		xctrans >> cursors
	next
} /^\*\*\*/ {
	if (trace_lines > 0) print "asterisks " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (substr(\$0, 1, 6) == "*** DU") {
		fil = tmpf "/truncated"
		print 1 > fil
		close(fil)
		truncated = 1
		next
	}
	if (substr(\$0, 1, 5) == "*** 2") {
		#yy = substr(\$2, 1, 4)
		#mm = substr(\$2, 6, 2)
		#dd = substr(\$2, 9, 2)
		#hh = substr(\$3, 1, 2)
		#mi = substr(\$3, 4, 2)
		#ss = substr(\$3, 7, 2)
		# This line shows the completion date of the gap.
		# The gap duration is measured by the difference between the
		# prior tim= value and the next tim= value.
		# (Nothing seems to be needed, cause there is no missing time in
		#  the trace files I have seen)
		#print "******************* GAP found on trace line " NR
		#print \$0
		next
	}
	if (\$1 == "Undo" && \$2 == "Segment") next
	print "Unprocessed *** line near trace line " NR ": " \$0
	if (index(\$0, "TRACE DUMP CONTINUES IN FILE") > 0 || \\
		index(\$0, "TRACE DUMP CONTINUED FROM FILE") > 0) {
		print ">>> See the comments within trace_report for details!"
	}
} /^STAT/ {
	if (trace_lines > 0) print "stat " NR
	if (abort_me == 2) next
	skip_dump = 0
	skip_to_nonquo = 0
	xx = check_lins()
	if (hv == 0) next
	binds = 0
	rpc_binds = 0
	rpc_call = 0
	peeked = "    "
	multi_line_value = 0
	if (found_first_stat == 0) {
		++stat_ndx
		stat_sort = 0
		found_first_stat = 1
	}
	++stat_sort
	curno = \$2 ""
	gsub("#","",curno)
	orig_curno = curno
	if (curno != "0" && ncur == 0) next
	cur = find_cursor()
	if (skip_to_equal == 1) next
	if (cur > 0) {
		parsing = 0
		parameters = 0
		row = 9999999999
		id = 0
		pid = 0
		desc = ""
		seg_cr = 0
		seg_r = 0
		seg_w = 0
		seg_time = 0
		part_start = 0
		part_stop = 0
		obj = "0"
		cost="."
		size="."
		card="."
		f = 0
		for (x=3;x<=NF;x++) {
			if (f == 1) {
				gsub(q,"",\$x)
				equals = index(\$x, "=")
				if (equals == 0) {
					if (\$x == "us") continue
					if (\$x == "us)") continue
					desc = desc " " \$x
				} else {
					if (obj != 0) {
						key = substr(\$x, 1, equals - 1)
						val = substr(\$x, equals + 1)
						if (key == "(cr") {
							seg_cr = val
							continue
						}
						if (key == "r" || key == "pr") {
							seg_r = val
							continue
						}
						if (key == "w" || key == "pw") {
							seg_w = val
							continue
						}
						if (key == "time") {
							seg_time = val
							continue
						}
						if (key == "START") {
							part_start = val
							continue
						}
						if (key == "STOP") {
							part_stop = val
							continue
						}
						if (key == "cost") {
							cost = int(val)
							continue
						}
						if (key == "size") {
							size = int(val)
							continue
						}
						if (key == "card") {
							card = int(val)
							continue
						}
						print "Unexpected parameter" \\
							" for stat found" \\
							" near line " NR ": " \\
							\$x
					}
				}
				continue
			}
			equals = index(\$x, "=")
			key = substr(\$x, 1, equals - 1)
			val = substr(\$x, equals + 1)
			if (key == "id") {
				id = val
				continue
			}
			if (key == "cnt") {
				row = val
				continue
			}
			if (key == "pid") {
				pid = val
				continue
			}
			if (key == "pos") continue
			if (key == "obj") {
				obj = val
				continue
			}
			if (key == "op") {
				f = 1
				desc = val
				gsub(q,"",desc)
				continue
			}
			print "Unexpected parameter for stat found near" \\
				" line " NR ": " \$x
		}
		if (obj != 0) desc = desc " (object id " obj ")"
		if (row != "9999999999") {
			# Replace any tildes, since I use them as delimiters
			gsub("~","!@#",desc)
			printf "%4d %18d %12d 11 %5d %5d %s\n", \\
				cur, curno, hv, stat_ndx, stat_sort, \\
				row "~" id "~" \\
				pid "~" obj "~" seg_cr "~" seg_r "~" seg_w \\
				"~" seg_time "~" part_start "~" part_stop "~" \\
				desc "~" cost "~" size "~" card "~" NR \\
				>> cursors
			# See if Oracle 9.2 segment-level statistics
			if (seg_cr != 0 || seg_time != 0) {
				printf "%4d %18d %12d 12 %5d %5d %s\n", \\
					cur, curno, hv, stat_ndx, stat_sort, \\
					row "~" \\
					id "~" pid "~" obj "~" seg_cr "~" \\
					seg_r "~" seg_w "~" seg_time "~" \\
					part_start "~" part_stop "~" desc "~" \\
					cost "~" size "~" card >> cursors
			}
		}
	}
	next
} {
	if (NF == 0) next
	if (trace_lines > 0) print "rest " NR
	if (abort_me == 2) next
	xx = check_lins()
	if (skip_dump == 1) {
		if (substr(\$NF, length(\$NF)) == "]") next
		if (\$1 == "Repeat" && \$3 == "times") next
		skip_dump = 0
	}
	if (toid > 0) {
		--toid
		next
	}
	if (skip_to_equal != 0) next
	if (skip_to_nonquo != 0) {
		quote = index(\$0, "\\"")
		if (quote == 0) {
			val = val \$0
		} else {
			if (quote != 1) val = val substr(\$0, 1, quote - 1)
			skip_to_nonquo = 0
			if (rpc_binds != 0) {
				if (debug != 0) print \\
					"  Store rpc bind[" \\
					varno "] multi value: " val \\
					" for rpcndx " rpcndx
				fil = tmpf "/rpcbinds/" rpcndx
				printf "%4s%s%4d%s%-25s%s%8d\n", " ", \\
					"Bind Number: ", varno + 1, \\
					" Bind Value: ", val \\
					" Trace line: ", NR >> fil
				close(fil)
				# Incr number of rpc binds
				++rpcbindvars[rpcndx]
			} else {
				if (debug != 0) print "  Store bind[" \\
					varno "] multi value: " val \\
					" for curno " curno \\
					" bind #" varno
				# Skip avl comparison, since the avl buffer may
				# be much larger than the actual bind var
				#if (debug != 0) print "   Bind var len=" \\
				#	length(val) ", avl=" avl " on " NR
				#if (length(val) != avl && dty == 1) {
				#	print "  Truncated bind variable" \\
				#		" on line " NR ", length=" \\
				#		length(val) ", avl=" avl
				#	val = val " (Truncated)"
				#}
				fil = tmpf "/binds/" cur
				printf "%4s %11d    %-44s %10d\n", \\
					peeked, varno + 1, val, NR >> fil
				close(fil)
				# Incr number of binds
				++bindvars[cur]
			}
		}
		next
	}
	if (rpc_call == 1) {
		rpc_zero = rpc_zero \$0
		next
	}
	if (substr(\$1, 1, 6) == "value=") {
		if (trace_lines > 0) print "bind value " NR
		next_line_bind_value = 0
		if (abort_me == 2) next
		skip_dump = 0
		skip_to_nonquo = 0
		if (binds == 0) {
			print "Unprocessed value line near trace line " NR \\
				": " \$0
			next
		}
		if (oacdef == 0) {
			equals = index(\$0, "value=") + 5
			if (equals == 5) {
				print "No bind value found on trace line " NR \\
					": " \$0
				next
			}
			if (equals == length(\$0)) {
				multi_line_value = 1
			} else {
				if (substr(\$0, length(\$0) - 1) == "=\\"") {
					multi_line_value = 2
				} else {
					val = substr(\$0, equals + 1)
					if (debug != 0) print \\
						"  Bind value " val " on " NR
					if (substr(val, 1, 1) == "\\"") {
						quote = index(substr(\\
							val, 2), "\\"")
						if (quote != 0) {
							val = substr(val, 2, \\
								quote - 1)
						} else {
							skip_to_nonquo = 1
						}
					}
					if (skip_to_nonquo == 0) {
						if (debug != 0) print \\
							"  Store bind[" \\
							varno "] value: " val \\
							" for curno " curno \\
							" bind #" varno
						# Skip avl comparison,
						# since the avl buffer
						# may be much larger
						# than the actual bind var
						fil = tmpf "/binds/" cur
						printf \\
						  "%4s %11d    %-44s %10d\n", \\
							peeked, varno + 1, \\
							val, NR >> fil
						close(fil)
						# Incr number of binds
						++bindvars[cur]
					}
				}
			}
		}
		next
	}
	if (\$1 == "kkscoacd") next
	if (\$1 == "COLUMN:") next
	if (\$1 == "Size:") next
	if (\$1 == "Histogram:") next
	if (\$1 == "No" && \$2 == "bind" && \$3 == "buffers") next
	if (parameters == 1) {
		++linctr
		printf "%4d %18d %12d  1 %5d %s\n", \\
			ncur, curno, hv, linctr, substr(\$0, 1, 80) >> cursors
		if (length(\$0) < 81) {
			zero = ""
		} else {
			zero = substr(\$0, 81)
		}
		while (length(zero) > 0) {
			++linctr
			printf "%4d %18d %12d  1 %5d %s\n", \\
				ncur, curno, hv, linctr, \\
				substr(zero, 1, 80) >> cursors
			if (length(zero) < 81) {
				zero = ""
			} else {
				zero = substr(zero, 81)
			}
		}
		next
	}
	# See if we are PARSING IN CURSOR or PARSE ERROR and found a new Cursor
	# Number/Hash Val
	if (parsing == 1 && hash_ndx == 0) {
		++linctr
		printf "%4d %18d %12d  2 %5d %s\n", \\
			ncur, curno, hv, linctr, substr(\$0, 1, 80) >> cursors
		if (length(\$0) < 81) {
			zero = ""
		} else {
			zero = substr(\$0, 81)
		}
		while (length(zero) > 0) {
			++linctr
			printf "%4d %18d %12d  2 %5d %s\n", \\
				ncur, curno, hv, linctr, \\
				substr(zero, 1, 80) >> cursors
			if (length(zero) < 81) {
				zero = ""
			} else {
				zero = substr(zero, 81)
			}
		}
		next
	} else {
		# See if processing a multi-line bind value
		if (rpc_binds != 0) {
			if (multi_line_value == 9) next
			if (multi_line_value > 0) {
				if (multi_line_value == 1) {
					bval = substr(\$0, 1, 25)
				} else {
					bval = "\\"" substr(\$0, 1, 23)
				}
				fil = tmpf "/rpcbinds/" rpcndx
				printf "%4s%s%4d%s%-25s%s%8d\n", \\
					" ", "Bind Number: ", \\
					varno + 1, \\
					" Bind Value: ", bval, \\
					" Trace line: ", NR >> fil
				if (length(\$0) > 25) {
					if (multi_line_value == 1) {
						bval = substr(\$0, 26, 25)
					} else {
						bval = "\\"" substr(\$0, 26, 23)
					}
					printf "%34s%-25s\n", " ", bval >> fil
				}
				if (length(\$0) > 50) {
					if (multi_line_value == 1) {
						bval = substr(\$0, 51, 25)
					} else {
						bval = "\\"" substr(\$0, 51, 23)
					}
					printf "%34s%-25s\n", " ", bval >> fil
				}
				close(fil)
				++rpcbindvars[rpcndx]
				multi_line_value = 9
			}
			next
		}
		if (binds == 1) {
			if (multi_line_value == 9) next
			if (multi_line_value > 0) {
				if (trace_lines > 0) print \
					"write multi-line bind" NR
				if (multi_line_value == 1) {
					bval = substr(\$0, 1, 44)
				} else {
					bval = "\\"" substr(\$0, 1, 43)
				}
				fil = tmpf "/binds/" cur
				printf "     %11d    %-44s %10d\n", \\
					varno + 1, bval, NR >> fil
				if (length(\$0) > 44) {
					if (multi_line_value == 1) {
						bval = substr(\$0, 45)
					} else {
						bval = "\\"" substr(\$0, 44)
					}
					printf "     %11d    %-44s %10d\n", \\
						varno + 1, bval, NR >> fil
				}
				close(fil)
				++bindvars[cur]
				multi_line_value = 9
				next
			}
		}
		# Skip if we already found this SQL
		if (parsing == 1) next
		# Skip header
		if (NR < 10) next
		if (\$1 == "adbdrv:") next
		if (\$1 == "With") next
		if (\$1 == "ORACLE_HOME") next
		if (\$1 == "System") next
		if (\$1 == "Release:") next
		if (\$1 == "Version:") next
		if (\$1 == "Machine:") next
		if (\$1 == "VM") next
		if (\$1 == "Redo") next
		if (\$1 == "Oracle") next
		if (\$1 == "JServer") next
		if (\$1 == "An" && \$2 == "invalid" && \$3 == "number" && \\
			\$4 == "has" && \$5 == "been") next
		if (substr(\$1,1,8) == "WARNING:") {
			print ""
			print "The following warning message is in the" \\
				" trace file:"
			print \$0
			print ""
			next
		}
		print "Unprocessed line on trace line " NR ": " \$0
		if (print_trunc == 0) {
			print ""
			print "Ensure that the dump file has not been " \\
				"truncated!!!!"
			print "Set MAX_DUMP_FILE_SIZE=UNLIMITED to avoid " \\
				"truncation."
			print ""
			print_trunc = 1
		}
	}
} END {
	# Store all remaining pending waits as unaccounted time
	while (getline < pendwaits > 0) {
		if (debug != 0) print "      Read pendwaits : " \$0
		the_wait = substr(\$0, 27)
		elem = split(the_wait, arr, "~")
		if (elem != 7) {
			print "Unexpected number of columns (" elem \\
				") in pending waits wait line #" NR ":"
			print the_wait
			continue
		}
		# Skip object waits
		if (\$4 != 4) continue
		curno = \$2
		nam = arr[1]
		p1 = arr[2]
		p2 = arr[3]
		p3 = arr[4]
		ela = arr[5]
		recnum = arr[6]
		objn = arr[7]
		if (debug != 0) print "      Storing non-matching" \\
			" cursor " curno " in array 9999"
		if (found9999 == 0) {
			printf \\
			      "%4d %18d %12d  0 %s %s %s %s %s %s %s %s %s\n",\\
				9999, curno, 1, "x", "x", 0, 0, 0, "x", 0, \\
				".", recnum >> cursors
			found9999 = 1
		}
		# Store wait time without a matching cursor
		print ela >> filwaitsela
		# Not sure if this is accurate:
		gap_time = gap_time - ela
	}
	close(pendwaits)
	system("rm -f " pendwaits)
	if (trace_lines > 0) print "end"
	if (gap_time < 0) gap_time = 0
	fil = tmpf "/eof"
	if (debug != 0) {
		print "last_tim=   " last_tim
		printf "%s%12.4f\n", "first_time= ", first_time
		print "Write grand_elapsed= " last_tim - first_time
	}
	print int(last_tim - first_time) > fil
	close(fil)
	fil = tmpf "/init"
	print mm " " dd " " yy " " hh " " mi " " ss " " divisor " " \\
		first_time " " gap_time " " gap_cnt " " cpu_timing_parse \\
		" " cpu_timing_exec " " cpu_timing_fetch " " cpu_timing_unmap \\
		" " cpu_timing_sort " " cpu_timing_parse_cnt " " \\
		cpu_timing_exec_cnt " " cpu_timing_fetch_cnt " " \\
		cpu_timing_unmap_cnt " " cpu_timing_sort_cnt " " \\
		ncur " " cpu_timing_rpcexec " " \\
		cpu_timing_rpcexec_cnt " " cpu_timing_close " " \\
		cpu_timing_close_cnt " " cpu_timing_lobread " " \\
		cpu_timing_lobread_cnt " " cpu_timing_lobpgsize " " \\
		cpu_timing_lobpgsize_cnt " " cpu_timing_lobwrite " " \\
		cpu_timing_lobwrite_cnt " " cpu_timing_lobgetlen " " \\
		cpu_timing_lobgetlen_cnt " " cpu_timing_lobappend " " \\
		cpu_timing_lobappend_cnt " " cpu_timing_lobarrread " " \\
		cpu_timing_lobarrread_cnt " " cpu_timing_lobarrtmpfre " " \\
		cpu_timing_lobarrtmpfre_cnt " " cpu_timing_lobarrwrite " " \\
		cpu_timing_lobarrwrite_cnt " " cpu_timing_lobtmpfre " " \\
		cpu_timing_lobtmpfre_cnt > fil
	close(fil)
	close(cursors)
	close(filwaitsela)
	close(filcmdtypes)
	close(filmodules)
	close(filactions)
	close(filwaitst)
	close(filwaitsmod)
	close(filwaitsact)
}
EOF
if [ `file $1 | awk '{ print index($0, " CRLF ") }'` -eq 0 ]
then
	cat $1 | sed -e "s/ \. /./g" -e "s/ ,/,/g" | \
		$cmd -f trace_report.awk outf=$outf q="'" tmpf="$tmpf" \
		debug="$debug" totlins="`wc -l $1 | awk '{ print $1 }' -`" \
		trace_lines="$trace_lines"
	if [ $? -ne 0 ]
	then
		echo "Unexpected error from awk"
		echo "Retrying trace_report by using \"strings\" on input" \
			"file ..."
		strings $1 | sed -e "s/ \. /./g" -e "s/ ,/,/g" | \
			$cmd -f trace_report.awk outf=$outf q="'" tmpf="$tmpf" \
			debug="$debug" totlins="`wc -l $1 | awk '{
			print $1 }' -`"
		if [ $? -ne 0 ]
		then
			echo "Unexpected error from awk - Aborting..."
			rm -f trace_report.awk
			trap - QUIT INT KILL TERM
			exit 2
		fi
	fi
else
	# Convert DOS (CR/LF) text file to Unix (LF) format
	echo "Processing DOS-formatted trace file..."
	tr -d \\015 < $1 | sed -e "s/ \. /./g" -e "s/ ,/,/g" | \
		$cmd -f trace_report.awk outf=$outf q="'" tmpf="$tmpf" \
		debug="$debug" totlins="`wc -l $1 | awk '{ print $1 }' -`"
	if [ $? -ne 0 ]
	then
		echo "unexpected error from awk - aborting..."
		rm -f trace_report.awk
		trap - QUIT INT KILL TERM
		exit 2
	fi
fi
rm -f trace_report.awk
echo "Sorting temp files..."
if [ "$debug" = "1" ]
then
	echo "Sort cursors..."
fi
sort $tmpf/cursors > $tmpf/srt.tmp
mv -f $tmpf/srt.tmp $tmpf/cursors
if [ "$debug" = "1" ]
then
	echo "Sort cmdtypes..."
fi
sort $tmpf/cmdtypes > $tmpf/srt.tmp
mv -f $tmpf/srt.tmp $tmpf/cmdtypes
if [ "$debug" = "1" ]
then
	echo "Sort modules..."
fi
sort $tmpf/modules > $tmpf/srt.tmp
mv -f $tmpf/srt.tmp $tmpf/modules
if [ "$debug" = "1" ]
then
	echo "Sort actions..."
fi
sort $tmpf/actions > $tmpf/srt.tmp
mv -f $tmpf/srt.tmp $tmpf/actions
if [ "$debug" = "1" ]
then
	echo "Sort waits..."
fi
sort $tmpf/waitst > $tmpf/waitssrt.tmp
mv -f $tmpf/waitssrt.tmp $tmpf/waitst
if [ "$debug" = "1" ]
then
	echo "Sort total waits by module..."
fi
sort $tmpf/waitstotmod > $tmpf/waitssrt.tmp
mv -f $tmpf/waitssrt.tmp $tmpf/waitstotmod
if [ "$debug" = "1" ]
then
	echo "Sort total waits by action..."
fi
sort $tmpf/waitstotact > $tmpf/waitssrt.tmp
mv -f $tmpf/waitssrt.tmp $tmpf/waitstotact
if [ "$debug" = "1" ]
then
	echo "List of all temp files..."
	ls -l $tmpf
fi
if [ "$debug" = "1" ]
then
	echo "Contents of $tmpf/cursors:"
	cat $tmpf/cursors
fi
cat <<EOF > trace_report.awk
BEGIN {
	dmi[1] = 31
	dmi[2] = 31
	dmi[3] = 30
	dmi[4] = 31
	dmi[5] = 31
	dmi[6] = 30
	dmi[7] = 31
	dmi[8] = 31
	dmi[9] = 30
	dmi[10] = 31
	dmi[11] = 30
	dmi[12] = 31
	totn = 0
	totnr = 0
	blanks = "                                                       "
	offst = "                    "
} function lpad(inv, tlen) {
	cinv = int(inv) ""
	return substr("                              ", 1, \\
		tlen - length(cinv)) cinv
} function kmc(inval, thelen) {
	cval = int(inval) ""
	cvalk = int(inval / 1024) ""
	cvalm = int(inval / 1048576) ""
	cvalg = int(inval / 1073741824) ""
	if (length(cval) <= thelen) {
		return substr(sprintf("%27d", inval), 28 - thelen)
	} else {
		if (int(inval / 1024) >= 100 && int(inval / 1024) <= 999 && \\
			thelen == 3) {
			return "." int(inval / 102400) "M"
		} else {
		if (int(inval / 1024) <= 9999 && length(cvalk) < thelen) {
			return lpad(inval / 1024, thelen - 1) "K"
		} else {
		if (int(inval / 1048576) >= 100 && \\
			int(inval / 1048576) <= 999 && thelen == 3) {
			return "." int(inval / 104857600) "G"
		} else {
		if (int(inval / 1048576) <= 9999 && length(cvalm) < thelen) {
			return lpad(inval / 1048576, thelen - 1) "M"
		} else {
		if (int(inval / 1073741824) <= 9999 && length(cvalg) < thelen) {
			return lpad(inval / 1073741824, thelen - 1) "G"
		} else {
			tmplen = thelen - 1
			vpower = 1
			while (tmplen > 0) {
				vpower = vpower * 10
				--tmplen
			}
		if (int(inval / 1099511627776) < vpower) {
			return lpad(inval / 1099511627776, thelen - 1) "T"
		} else {
			return substr("*******************************", 1, \\
				thelen)
		}
		}
		}
		}
		}
		}
	}
} function print_prev_command_type() {
	printcmd = cmdtypstrs[prev_cmd]
	printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
		substr(printcmd, 1, 7), stcount, stcpu / 100, \\
		stelapsed / 100, stdisk, stquery, stcurrent, strows >> outf
	j = 8
	while (length(printcmd) >= j) {
		print substr(printcmd, j, 7) >> outf
		j = j + 7
	}
	tcount = tcount + stcount
	tcpu = tcpu + stcpu
	telapsed = telapsed + stelapsed
	tdisk = tdisk + stdisk
	tquery = tquery + stquery
	tcurrent = tcurrent + stcurrent
	trows = trows + strows
} function print_prev_curwait() {
	if (namela < 1) return
	if (found == 0) {
		print "" >> outf
		print "####################################" \\
			"############################################" >> outf
		print "" >> outf
		print "                          TOTAL WAIT EVENTS BY CURSOR" \\
			>> outf
		print "" >> outf
		print "                    " \\
			"                                                " \\
			"     Wait" >> outf
		print "Cursor              " \\
			" Wait Event                                     " \\
			"    Seconds" >> outf
		print "--------------------" \\
			" -----------------------------------------------" \\
			" ----------" >> outf
		found = 1
	}
	printf "%20s %-47s %10.4f\n", \\
		prev_cur, substr(prev_nam, 1, 47), namela / 100 >> outf
	if (length(prev_nam) > 47) \\
		print "                     " substr(prev_nam, 48, 47) >> outf
	namela = 0
} function print_prev_modwait() {
	if (namela < 1) return
	if (print_module == 1) {
		print "" >> outf
		print "####################################" \\
			"############################################" >> outf
		print "" >> outf
		print "                          TOTAL WAIT EVENTS BY MODULE" \\
			>> outf
		print "" >> outf
		print "Module                          " \\
			" Wait Event                       Wait Seconds" >> outf
		print "--------------------------------" \\
			" ------------------------------ --------------" >> outf
		printf "%-32s %-30s %14.4f\n", \\
			substr(prev_module, 1, 32), substr(prev_nam, 1, 30), \\
			namela / 100 >> outf
		if (length(prev_module) > 32) {
			if (length(prev_nam) > 30) {
				printf "%-32s %-30s\n", \\
					substr(prev_module, 33, 32), \\
					substr(prev_nam, 31, 30) >> outf
			} else {
				printf "%-32s\n", substr(prev_module, 33, 32) \\
					>> outf
			}
		} else {
			if (length(prev_nam) > 30) {
				printf "%-32s %-30s\n", " ", \\
					substr(prev_nam, 31, 30) >> outf
			}
		}
		print_module = 0
		found = 1
	} else {
		printf "%-32s %-30s %14.4f\n", \\
			" ", substr(prev_nam, 1, 30), namela / 100 >> outf
		if (length(prev_nam) > 30) {
			printf "%-32s %-30s\n", " ", substr(prev_nam, 31, 30) \\
				>> outf
		}
	}
	namela = 0
} function print_prev_actwait() {
	if (namela < 1) return
	if (print_action == 1) {
		print "" >> outf
		print "####################################" \\
			"############################################" >> outf
		print "" >> outf
		print "                          TOTAL WAIT EVENTS BY ACTION" \\
			>> outf
		print "" >> outf
		print "Action                          " \\
			" Wait Event                       Wait Seconds" >> outf
		print "--------------------------------" \\
			" ------------------------------ --------------" >> outf
		printf "%-32s %-30s %14.4f\n", \\
			substr(prev_action, 1, 32), substr(prev_nam, 1, 30), \\
			namela / 100 >> outf
		if (length(prev_action) > 32) {
			if (length(prev_nam) > 30) {
				printf "%-32s %-30s\n", \\
					substr(prev_action, 33, 32), \\
					substr(prev_nam, 31, 30) >> outf
			} else {
				printf "%-32s\n", substr(prev_action, 33, 32) \\
					>> outf
			}
		} else {
			if (length(prev_nam) > 30) {
				printf "%-32s %-30s\n", " ", \\
					substr(prev_nam, 31, 30) >> outf
			}
		}
		print_action = 0
		found = 1
	} else {
		printf "%-32s %-30s %14.4f\n", \\
			" ", substr(prev_nam, 1, 30), namela / 100 >> outf
		if (length(prev_nam) > 30) {
			printf "%-32s %-30s\n", " ", substr(prev_nam, 31, 30) \\
				>> outf
		}
	}
	namela = 0
} function print_prev_wait() {
	if (totwts == 0) return
	if (totela < 1) return
	if (found == 0) {
		print "" >> outf
		print "####################################" \\
			"############################################" >> outf
		print "" >> outf
		if (wait_head == 1) {
			print "                    WAIT EVENTS FOR ALL" \\
				" STATEMENTS FOR USERS" >> outf
		}
		if (wait_head == 2) {
			print "                   **** GRAND TOTAL NON-IDLE" \\
				" WAIT EVENTS ****" >> outf
		}
		if (wait_head == 3) {
			print "                         *** ORACLE TIMING" \\
				" ANALYSIS ***" >> outf
		}
		print "" >> outf
		print "                                   " \\
			"                 Elapsed             Seconds" >> outf
		if (wait_head == 3) {
			print "Oracle Process/Wait Event          " \\
				"                 Seconds  Pct  Calls  /Call" \\
				>> outf
		} else {
			print "Oracle Wait Event Name             " \\
				"                 Seconds  Pct  Calls  /Call" \\
				>> outf
		}
		print "-----------------------------------" \\
			"--------------- -------- ---- ------ -------" >> outf
		found = 1
	}
	printf "%-50s %8.2f %3d%s %6d %7.2f\n", \\
		substr(print_nam, 1, 50), totela / 100, \\
		int(1000 * (totela + .0000001) / (totwait + .0000001)) / 10, \\
		"%", totwts, totela / (totwts * 100 + .0000001) >> outf
	if (length(print_nam) > 50) print "  " substr(print_nam, 51) >> outf
	if (wait_head != 3) {
		if (substr(print_nam,1,17) == "buffer busy waits" || \\
			substr(print_nam,1,16) == "direct path read" || \\
			substr(print_nam,1,17) == "direct path write" || \\
			print_nam == "free buffer waits" || \\
			print_nam == "write complete waits" || \\
			substr(print_nam,1,12) == "db file scat" || \\
			substr(print_nam,1,11) == "db file seq") filblk = 1
	}
	gtotwts = gtotwts + totwts
	gtotela = gtotela + totela
} function ymdhms(oratim) {
	nyy = yy + 0
	nmm = mm + 0
	ndd = dd + 0
	nhh = hh + 0
	nmi = mi + 0
	nss = ss + int((oratim - first_time) / 100)
	while (nss > 59) {
		nss = nss - 60
		nmi = nmi + 1
	}
	while (nmi > 59) {
		nmi = nmi - 60
		nhh = nhh + 1
	}
	while (nhh > 23) {
		nhh = nhh - 24
		ndd = ndd + 1
	}
	if (nmm == 2) {
		if (nyy == 4 * int(nyy / 4)) {
			if (nyy == 100 * int(nyy / 100)) {
				if (nyy == 400 * int(nyy / 400)) {
					dmi[2] = 29
				} else {
					dmi[2] = 28
				}
			} else {
				dmi[2] = 29
			}
		} else {
			dmi[2] = 28
		}
	}
	while (ndd > dmi[nmm]) {
		ndd = ndd - dmi[nmm]
		nmm = nmm + 1
	}
	while (nmm > 12) {
		nmm = nmm - 12
		nyy = nyy + 1
	}
	return sprintf("%2.2d/%2.2d/%2.2d %2.2d:%2.2d:%2.2d", \\
		nmm, ndd, nyy, nhh, nmi, nss)
} function print_prev_operation() {
	printop = prev_op
	if (prev_op == "1") printop = "Parse"
	if (prev_op == "2") printop = "Execute"
	if (prev_op == "3") printop = "Fetch"
	if (prev_op == "4") printop = "Unmap"
	if (prev_op == "5") printop = "Srt Unm"
	if (prev_op == "6") printop = "Close"
	if (prev_op == "7") printop = "Lobread"
	if (prev_op == "8") printop = "Lobpgsiz"
	if (prev_op == "9") printop = "Lobwrite"
	if (prev_op == "10") printop = "Lobgetlen"
	if (prev_op == "11") printop = "Lobappend"
	if (prev_op == "12") printop = "Lobarrread"
	if (prev_op == "13") printop = "Lobarrtmpfr"
	if (prev_op == "14") printop = "Lobarrwrite"
	if (prev_op == "15") printop = "Lobtmpfre"
	printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
		printop, stcount, stcpu / 100, stelapsed / 100, \\
		stdisk, stquery, stcurrent, strows >> outf
	tcount = tcount + stcount
	tcpu = tcpu + stcpu
	telapsed = telapsed + stelapsed
	if (prev_op == "3") {
		tfetch = tfetch + stelapsed
		if (stdisk > 0) avg_read_time = int(1000 * \\
			((stelapsed - stcpu) / 100) / stdisk)
	}
	tdisk = tdisk + stdisk
	tquery = tquery + stquery
	tcurrent = tcurrent + stcurrent
	trows = trows + strows
	if (dep == "0") {
		x9 = 0
		mtch = 0
		while (x9 < totn) {
			++x9
			if (opnames[x9] == printop) {
				mtch = x9
				x9 = totn
			}
		}
		if (mtch == 0) {
			++totn
			opnames[totn] = printop
			otcounts[totn] = 0
			otcpus[totn] = 0
			otelapseds[totn] = 0
			otdisks[totn] = 0
			otquerys[totn] = 0
			otcurrents[totn] = 0
			otrowss[totn] = 0
			otunaccs[totn] = 0
			mtch = totn
		}
		if (debug != 0) print "    print_prev_operation: Accum" \\
			" recur wait " mtch " out of " totn
		otcounts[mtch] = otcounts[mtch] + stcount
		otcpus[mtch] = otcpus[mtch] + stcpu
		otelapseds[mtch] = otelapseds[mtch] + stelapsed
		otdisks[mtch] = otdisks[mtch] + stdisk
		otquerys[mtch] = otquerys[mtch] + stquery
		otcurrents[mtch] = otcurrents[mtch] + stcurrent
		otrowss[mtch] = otrowss[mtch] + strows
		oper_indx = mtch
	} else {
		x9 = 0
		mtch = 0
		while (x9 < totnr) {
			++x9
			if (ropnames[x9] == printop) {
				mtch = x9
				x9 = totnr
			}
		}
		if (mtch == 0) {
			++totnr
			ropnames[totnr] = printop
			rotcounts[totnr] = 0
			rotcpus[totnr] = 0
			rotelapseds[totnr] = 0
			rotdisks[totnr] = 0
			rotquerys[totnr] = 0
			rotcurrents[totnr] = 0
			rotrowss[totnr] = 0
			rotunaccs[totnr] = 0
			mtch = totnr
		}
		if (debug != 0) print "    print_prev_operation: Accum" \\
			" non-recur wait " mtch " out of " totnr
		rotcounts[mtch] = rotcounts[mtch] + stcount
		rotcpus[mtch] = rotcpus[mtch] + stcpu
		rotelapseds[mtch] = rotelapseds[mtch] + stelapsed
		rotdisks[mtch] = rotdisks[mtch] + stdisk
		rotquerys[mtch] = rotquerys[mtch] + stquery
		rotcurrents[mtch] = rotcurrents[mtch] + stcurrent
		rotrowss[mtch] = rotrowss[mtch] + strows
		oper_indx = mtch
	}
} function print_prev_module() {
	print prev_module >> outf
	printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
		" ", stcount, stcpu / 100, \\
		stelapsed / 100, stdisk, stquery, stcurrent, strows >> outf
	print " " >> outf
	tcount = tcount + stcount
	tcpu = tcpu + stcpu
	telapsed = telapsed + stelapsed
	tdisk = tdisk + stdisk
	tquery = tquery + stquery
	tcurrent = tcurrent + stcurrent
	trows = trows + strows
} function print_prev_action() {
	print prev_action >> outf
	printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
		" ", stcount, stcpu / 100, \\
		stelapsed / 100, stdisk, stquery, stcurrent, strows >> outf
	print " " >> outf
	tcount = tcount + stcount
	tcpu = tcpu + stcpu
	telapsed = telapsed + stelapsed
	tdisk = tdisk + stdisk
	tquery = tquery + stquery
	tcurrent = tcurrent + stcurrent
	trows = trows + strows
} function print_temp_waits() {
	#
	# Read and print any Wait times from the temp wait file
	#
	if (totela > 0 || cur == 0) {
		if (cur == 0) hv = "0"
		found = 0
		wait_ctr = 0
		if (debug != 0) print "      Print temp waits..."
		close(waifil)
		while (getline < waifil > 0) {
			if (debug != 0) print "      Read waifil: " \$0
			elem = split(\$0, arr, "~")
			if (elem != 7) continue
			nam = arr[1]
			ela = arr[5]
			if (100 * ela >= 1) {
				if (substr(nam,1,17) == \\
					"buffer busy waits" || \\
					substr(nam,1,16) == \\
					"direct path read" || \\
					substr(nam,1,17) == \\
					"direct path write" || \\
					nam == "free buffer waits" || \\
					nam == "write complete waits" \\
					|| nam == \\
					"buffer busy global cache" || \\
					nam == \\
					"buffer busy global CR" || \\
					nam == "buffer read retry" || \\
					nam == \\
					"control file sequential read"\\
					|| nam == \\
					"control file single write" \\
					|| nam == \\
					"conversion file read" || \\
					nam == \\
					"db file single write" || \\
					nam == \\
					"global cache lock busy" || \\
					nam == \\
					"global cache lock cleanup" \\
					|| nam == \\
					"global cache lock null to s" \\
					|| nam == \\
					"global cache lock null to x" \\
					|| nam == \\
					"global cache lock open null" \\
					|| nam == \\
					"global cache lock open s" \\
					|| nam == \\
					"global cache lock open x" \\
					|| nam == \\
					"global cache lock s to x" \\
					|| nam == \\
					"local write wait" || \\
					substr(nam,1,12) == \\
					"db file scat" || \\
					substr(nam,1,11) == \\
					"db file seq") {
						file_numb = arr[2] # p1
						block_numb = arr[3] # p2
				} else {
					file_numb = ""
					block_numb = ""
				}
				if (substr(nam,1,11) == "enqueue (Na") {
					rollback_seg = arr[3]	# p2
				} else {
					rollback_seg = 0
				}
				if (found == 0) {
					if (hv == 1) {
						print "            " \\
							"        " \\
							"Unaccounted" \\
							" Wait" \\
							" Events for" \\
							" all" \\
							" cursors" \\
							>> outf
					} else {
						print "            " \\
							"         " \\
							"    " \\
							"Significant" \\
							" Wait" \\
							" Events" \\
							>> outf
					}
					print " " >> outf
					print "                   " \\
						"                 " \\
						"       Total" >> outf
					print "                   " \\
						"                 " \\
						"       Wait      " \\
						"   Trace" >> outf
					print "                    " \\
						"                  " \\
						"     Time         " \\
						" File File   Block" \\
						>> outf
					print "Oracle Event Name" \\
						"               " \\
						"          (secs)" \\
						"  Pct    Line Numb" \\
						"  Number" >> outf
					print "-----------------" \\
						"---------------" \\
						"------- --------" \\
						" ---- ------- ----" \\
						" -------" >> outf
					found = 1
					prev_event = "@"
					event_ctr = 0
				}
				recnum = arr[6]
				objn = arr[7]
				if (prev_event != nam || event_ctr < 11) {
					if (prev_event != "@" && \\
						event_ctr > 10) {
						print "     " event_ctr - \\
							10 " more " \\
							prev_event \\
							" wait events..." \\
							>> outf
						printf \\
					   "%s%9.3f %s%9.3f %s%9.3f\n", \\
							"Min Wait Time=", \\
							min_wait / 100, \\
							"Avg Wait Time=", \\
							(avg_wait / \\
							event_ctr) / 100, \\
							"Max Wait Time=", \\
							max_wait / 100>> outf
					}
					if (totela == 0) {
						printf \\
					     "%-39s%9.3f      %7d %4s%8s\n", \\
						  substr(nam, 1, 39), \\
						  ela / 100, \\
						  recnum, file_numb, \\
						  block_numb >> outf
					} else {
						printf \\
					     "%-39s%9.3f %3d%s %7d %4s%8s\n", \\
						  substr(nam, 1, 39), \\
						  ela / 100, \\
						  int(1000 * ela / \\
						  totela) / 10, "%", \\
						  recnum, file_numb, \\
						  block_numb >> outf
					}
					if (length(nam) > 39) \\
						print "  " substr(nam, 40) \\
							>> outf
					if (substr(nam,1,11) == "enqueue (Na") {
						rbsn = int(rollback_seg \\
							/ 65536)
						print "  Rollback segment #" \\
							rbsn ", Slot #" \\
							rollback_seg \\
							- (rbsn * 65536) >> outf
					}
					if (prev_event != nam) {
						prev_event = nam
						min_wait = 9999999999999
						avg_wait = 0
						max_wait = 0
						event_ctr = 0
					}
				}
				rest = 0
				++event_ctr
				avg_wait = avg_wait + ela
				if (ela < min_wait) min_wait = ela
				if (ela > max_wait) max_wait = ela
			} else {
				if (debug != 0) print "        Skip" \\
					" too-small wait: ela=" ela
			}
			# Accum subtotals by event name
			if (debug != 0) print "      Accum wait subtots..."
			x9 = 0
			mtch = 0
			while (x9 < wait_ctr) {
				++x9
				if (file_numb == "") {
					if (waitevs[x9] == nam) {
						mtch = x9
						x9 = wait_ctr
					}
				} else {
					if (waitevs[x9] == nam " (File " \\
						file_numb ")") {
						mtch = x9
						x9 = wait_ctr
					}
				}
			}
			if (mtch == 0) {
				++wait_ctr
				if (file_numb == "") {
					waitevs[wait_ctr] = nam
					waitfile[wait_ctr] = " "
				} else {
					waitevs[wait_ctr] = nam \\
						" (File " file_numb ")"
					if (substr(nam, 1, 7) == "db file") {
						waitfile[wait_ctr] = file_numb
					} else {
						waitfile[wait_ctr] = " "
					}
				}
				maxwait[wait_ctr] = ela
				waitsecs[wait_ctr] = ela
				waitcnts[wait_ctr] = 1
				ms1_wait[wait_ctr] = 0
				ms2_wait[wait_ctr] = 0
				ms4_wait[wait_ctr] = 0
				ms8_wait[wait_ctr] = 0
				ms16_wait[wait_ctr] = 0
				ms32_wait[wait_ctr] = 0
				ms64_wait[wait_ctr] = 0
				ms128_wait[wait_ctr] = 0
				ms256_wait[wait_ctr] = 0
				msbig_wait[wait_ctr] = 0
				mtch = wait_ctr
			} else {
				waitsecs[mtch] = waitsecs[mtch] + ela
				if (ela > maxwait[mtch]) maxwait[mtch] = ela
				++waitcnts[mtch]
			}
			if (debug != 0) print "      Accum wait hists..."
			if (ela * 1000 <= 100) {
				++ms1_wait[mtch]
			} else {
			  if (ela * 500 <= 100) {
			    ++ms2_wait[mtch]
			  } else {
			    if (ela * 250 <= 100) {
			      ++ms4_wait[mtch]
			    } else {
			      if (ela * 125 <= 100) {
				++ms8_wait[mtch]
			      } else {
				if (ela * 125 <= 2 * 100) {
				  ++ms16_wait[mtch]
				} else {
				  if (ela * 125 <= 4 * 100) {
				    ++ms32_wait[mtch]
				  } else {
				    if (ela * 125 <= 8 * 100) {
				      ++ms64_wait[mtch]
				    } else {
				      if (ela * 125 <= 16 * 100) {
					++ms128_wait[mtch]
				      } else {
					if (ela * 125 <= 32 * 100) {
					  ++ms256_wait[mtch]
					} else {
					  ++msbig_wait[mtch]
					}
				      }
				    }
				  }
				}
			      }
			    }
			  }
			}
		}
		close(waifil)
		if (found != 0) {
			if (prev_event != "@" && event_ctr > 10) {
				print "     " event_ctr - 10 " more " \\
					prev_event " wait events..." \\
					>> outf
				printf "%s%9.3f %s%9.3f %s%9.3f\n", \\
					" Min Wait Time=", min_wait / 100, \\
					"Avg Wait Time=", \\
					(avg_wait / event_ctr) / 100, \\
					"Max Wait Time=", max_wait / 100 >> outf
			}
			if (totela == 0) {
				print "-----------------------------" \\
					"---------- --------" >> outf
				printf "%-39s%9.3f\n", \\
					"Total", totela / 100 >> outf
			} else {
				print "-----------------------------" \\
					"---------- -------- ----" \\
					>> outf
				printf "%-39s%9.3f %3d%s\n", \\
					"Total", totela / 100, 100, \\
					"%" >> outf
			}
			print "" >> outf
			if (debug != 0) print \\
				"      Print wait subtots..."
			print "                           Sub-Totals" \\
				" by Wait Event:" >> outf
			print "" >> outf
			print "                            " \\
				"                        Total" >> outf
			print "                            " \\
				"                        Wait " \\
				"       Number" >> outf
			print "                            " \\
				"                        Time " \\
				"         of    Avg ms" >> outf
			if (totela == 0) {
				print "Oracle Event Name           " \\
					"                       " \\
					"(secs)        Waits" \\
					" per Wait" >> outf
				print "----------------------------" \\
					"-------------------- --" \\
					"------      -------" \\
					" --------" >> outf
			} else {
				print "Oracle Event Name           " \\
					"                       " \\
					"(secs)  Pct   Waits" \\
					" per Wait" >> outf
				print "----------------------------" \\
					"-------------------- --" \\
					"------ ---- -------" \\
					" --------" >> outf
			}
			twait = 0
			nwaits = 0
			x9 = 0
			while (x9 < wait_ctr) {
				++x9
				if (totela == 0) {
					printf \\
					"%-48s%9.3f      %7d%9.2f\n",\\
					  substr(waitevs[x9], 1, 48), \\
					  waitsecs[x9] / 100, \\
					  waitcnts[x9], (1000 * \\
					  waitsecs[x9] / 100) / \\
					  waitcnts[x9] >> outf
				} else {
					printf \\
					"%-48s%9.3f %3d%s %7d%9.2f\n",\\
					  substr(waitevs[x9], 1, 48), \\
					  waitsecs[x9] / 100, \\
					  int(1000 * waitsecs[x9] / \\
					  totela) / 10, "%", \\
					  waitcnts[x9], (1000 * \\
					  waitsecs[x9] / 100) / \\
					  waitcnts[x9] >> outf
				}
				if (length(waitevs[x9]) > 48) \\
					print "  " \\
						substr(waitevs[x9], \\
						49) >> outf
				twait = twait + waitsecs[x9]
				nwaits = nwaits + waitcnts[x9]
				printf "%20s~%-s~%s\n", \\
					cur, waitevs[x9], \\
				  	waitsecs[x9] >> filtotcur
			}
			print "----------------------------" \\
				"-------------------- --------" \\
				" ---- ------- --------" >> outf
			printf "%40s%s%9.3f %3d%s %7d%9.2f\n",\\
				" ", "  Total ", twait / 100, \\
				100, "%", nwaits, \\
				(1000 * twait / 100) / nwaits >> outf
			print "" >> outf
			if (debug != 0) print "      Print max wait..."
			print "                            " \\
				"                          Max ms" \\
				>> outf
			print "Oracle Event Name           " \\
				"                         per Wait" \\
				>> outf
			print "----------------------------" \\
				"-------------------- ------------" \\
				>> outf
			x9 = 0
			while (x9 < wait_ctr) {
				++x9
				printf "%-48s%13.2f\n",\\
					substr(waitevs[x9], 1, 48), \\
					1000 * maxwait[x9] / 100 >> outf
				if (length(waitevs[x9]) > 48) \\
					print "  " \\
						substr(waitevs[x9], \\
						49) >> outf
			}
			print "" >> outf
			if (debug != 0) print "      Print wait hists..."
			print "                             " \\
				"Wait Event Histograms" >> outf
			print "" >> outf
			print "                               <<<<" \\
				"<< Count of Wait Events that waited" \\
				" for >>>>>" >> outf
			print "                                   " \\
				"                       16   32  64 " \\
				"  128  >" >> outf
			print "                                0-1" \\
				"  1-2  2-4  4-8 8-16  -32  -64 -128" \\
				" -256 256+" >> outf
			print "Oracle Event Name               ms " \\
				"  ms   ms   ms   ms   ms   ms   ms " \\
				"  ms   ms" >> outf
			print "------------------------------ ----" \\
				" ---- ---- ---- ---- ---- ---- ----" \\
				" ---- ----" >> outf
			x9 = 0
			tot = 0
			tot1 = 0
			tot2 = 0
			tot4 = 0
			tot8 = 0
			tot16 = 0
			tot32 = 0
			tot64 = 0
			tot128 = 0
			tot256 = 0
			totbig = 0
			while (x9 < wait_ctr) {
				++x9
				ms1 = " " kmc(ms1_wait[x9], 4)
				ms2 = " " kmc(ms2_wait[x9], 4)
				ms4 = " " kmc(ms4_wait[x9], 4)
				ms8 = " " kmc(ms8_wait[x9], 4)
				ms16 = " " kmc(ms16_wait[x9], 4)
				ms32 = " " kmc(ms32_wait[x9], 4)
				ms64 = " " kmc(ms64_wait[x9], 4)
				ms128 = " " kmc(ms128_wait[x9], 4)
				ms256 = " " kmc(ms256_wait[x9], 4)
				msbig = " " kmc(msbig_wait[x9], 4)
				printf \\
			      "%-30s%5s%5s%5s%5s%5s%5s%5s%5s%5s%5s\n",\\
					substr(waitevs[x9], 1, 30), \\
					ms1, ms2, ms4, ms8, ms16, \\
					ms32, ms64, ms128, ms256, \\
					msbig >> outf
				if (length(waitevs[x9]) > 30) \\
					print "  " substr(waitevs[x9], 31) \\
						>> outf
				if (debug != 0) print "      Accum hists..."
				tot1 = tot1 + ms1_wait[x9]
				tot2 = tot2 + ms2_wait[x9]
				tot4 = tot4 + ms4_wait[x9]
				tot8 = tot8 + ms8_wait[x9]
				tot16 = tot16 + ms16_wait[x9]
				tot32 = tot32 + ms32_wait[x9]
				tot64 = tot64 + ms64_wait[x9]
				tot128 = tot128 + ms128_wait[x9]
				tot256 = tot256 + ms256_wait[x9]
				totbig = totbig + msbig_wait[x9]
			}
			if (debug != 0) print "      Grand tot hists..."
			tot = tot1 + tot2 + tot4 + tot8 + tot16 + \\
				tot32 + tot64 + tot128 + tot256 + totbig
			if (tot > 0) {
				t = " " kmc(tot, 4)
				t1 = " " kmc(tot1, 4)
				t2 = " " kmc(tot2, 4)
				t4 = " " kmc(tot4, 4)
				t8 = " " kmc(tot8, 4)
				t16 = " " kmc(tot16, 4)
				t32 = " " kmc(tot32, 4)
				t64 = " " kmc(tot64, 4)
				t128 = " " kmc(tot128, 4)
				t256 = " " kmc(tot256, 4)
				tbig = " " kmc(totbig, 4)
				print "-----------------------------" \\
					"- ---- ---- ---- ---- ----" \\
					" ---- ---- ---- ---- ----" >> outf
				printf \\
			      "%-30s%5s%5s%5s%5s%5s%5s%5s%5s%5s%5s\n",\\
					" Histogram Bucket" \\
					" Sub-Totals  ", t1, t2, t4, \\
					t8, t16, t32, t64, t128, \\
					t256, tbig >> outf
				printf \\
		  "%-30s%4d%s%4d%s%4d%s%4d%s%4d%s%4d%s%4d%s%4d%s%4d%s%4d%s\n",\\
					" Percent of Total Wait Events ", \\
					int(100 * tot1 / tot), "%", \\
					int(100 * tot2 / tot), "%", \\
					int(100 * tot4 / tot), "%", \\
					int(100 * tot8 / tot), "%", \\
					int(100 * tot16 / tot), "%", \\
					int(100 * tot32 / tot), "%", \\
					int(100 * tot64 / tot), "%", \\
					int(100 * tot128 / tot), "%", \\
					int(100 * tot256 / tot), "%", \\
					int(100 * totbig / tot), "%" \\
					>> outf
			}
		}
		# See if file/block numbers written
		if (blockwaits == 1) {
			#
			#	Block Revisits
			#
			# Print total wait events by file/block number
			close(blkfil)
			system("sort -n " tmpf "/waitblocks > " tmpf \\
				"/waitblocks2")
			system("rm -f " tmpf "/waitblocks")
			prev_file = -1
			prev_block = -1
			cnt = 0
			fil = tmpf "/waitblocks2"
			fil2 = tmpf "/waitblocks"
			while (getline < fil > 0) {
				if (\$0 == "0") {
					print "0 0 0" >> fil2
					continue
				}
				if (prev_file != \$1 || prev_block != \$2) {
					if (prev_file >= 0 && cnt > 1) {
						print cnt " " prev_file " " \\
							prev_block >> fil2
					}
					prev_file = \$1
					prev_block = \$2
					cnt = 0
				}
				cnt = cnt + 1
			}
			if (prev_file >= 0 && cnt > 1) {
				print cnt " " prev_file " " prev_block >> fil2
			}
			close(fil2)
			close(fil)
			system("rm -f " tmpf "/waitblocks2")
			system("sort -nr " tmpf "/waitblocks > " tmpf \\
				"/waitblocks2")
			if (debug != 0) print "      Print block revisits..."
			h = 0
			revisit_ctr = 0
			while (getline < fil > 0) {
				if (\$1 == "0") continue
				if (h == 0) {
					print "                      Report" \\
						" of Frequently Visited" \\
						" Blocks" >> outf
					print " " >> outf
					if (print_revisits == 1) {
						print "           This shows" \\
							" which blocks have" \\
							" been re-read" \\
							" multiple times." \\
							>> outf
						print " " >> outf
						print "           Processes" \\
							" with a significant" \\
							" number of" \\
							" frequently visited" \\
							>> outf
						print "                " \\
							"blocks may offer" \\
							" the largest" \\
							" improvement gain." \\
							>> outf
						print " " >> outf
					}
					print "                  Block" \\
						" Visits     File Number" \\
						"    Block Number" >> outf
					print "                 ------" \\
						"------- ---------------" \\
						" ---------------" >> outf
					h = 1
				}
				printf "                 %13d %15d %15d\n", \\
					\$1, \$2, \$3 >> outf
				x9 = 0
				mtch = 0
				while (x9 < revisit_ctr) {
					++x9
					if (revfiles[x9] == \$2) {
						mtch = x9
						x9 = revisit_ctr
					}
				}
				if (mtch == 0) {
					++revisit_ctr
					revfiles[revisit_ctr] = \$2
					revvisits[revisit_ctr] = \$1
					revblocks[revisit_ctr] = \$3
					mtch = revisit_ctr
				} else {
					revvisits[mtch] = revvisits[mtch] + \$1
					revblocks[mtch] = revblocks[mtch] + 1
				}
			}
			close(fil)
			if (h == 1) print " " >> outf
			system("rm -f " fil)
			h = 0
			x9 = 0
			while (x9 < revisit_ctr) {
				++x9
				if (h == 0) {
					print "                      Summary" \\
						" of Frequently Visited" \\
						" Blocks" >> outf
					if (print_revisits == 1) {
						print " " >> outf
						print "         Processes" \\
							" with a" \\
							" significant" \\
							" Revisit Wait Time" \\
							" and a % Revisit" \\
							>> outf
						print "               Wait" \\
							" Time may" \\
							" offer the largest" \\
							" improvement gain." \\
							>> outf
						print_revisits = 0
					}
					print " " >> outf
					print "      File   Total Number" \\
						"  Total Block  Total Wait" \\
						"  Revisit Wait  % Revisit" \\
						>> outf
					print "     Number    of Blocks " \\
						"    Visits     Time (secs" \\
						")  Time (secs)  Wait Time" \\
						>> outf
					print "     ------  ------------" \\
						"  -----------  ----------" \\
						"  ------------  ---------" \\
						>> outf
					h = 1
				}
				totwat = 0
				totblk = 0
				x8 = 0
				while (x8 < wait_ctr) {
					++x8
					if (waitfile[x8] == revfiles[x9]) {
						totwat = totwat + waitsecs[x8]
						totblk = totblk + waitcnts[x8]
					}
				}
				if (totwat == 0 || revvisits[x9] == 0) {
					printf "    %7d  %12d  %11d\n",\\
						revfiles[x9], revblocks[x9], \\
						revvisits[x9] >> outf
				} else {
					printf \\
			    "    %7d  %12d  %11d  %10.3f  %12.3f    %3d%s\n",\\
						revfiles[x9], revblocks[x9], \\
						revvisits[x9], totwat / 100, \\
						(totwat / 100) * \\
						(revvisits[x9] / totblk), \\
						100 * (totwat * \\
						(revvisits[x9] / totblk)) / \\
						totwat, "%" >> outf
				}
			}
			blockwaits = 0
		}
		#
		# Print Read Time Histogram Buckets for this cursor
		#
		if (debug != 0) print "      Print read time hist..."
		if (totblocks == 0) totblocks = .0001
		if (totela > 0 && totreads > 0) {
			found = 0
			ms1_read = 0
			ms1_block = 0
			ms1_time = 0
			ms2_read = 0
			ms2_block = 0
			ms2_time = 0
			ms4_read = 0
			ms4_block = 0
			ms4_time = 0
			ms8_read = 0
			ms8_block = 0
			ms8_time = 0
			ms16_read = 0
			ms16_block = 0
			ms16_time = 0
			ms32_read = 0
			ms32_block = 0
			ms32_time = 0
			ms64_read = 0
			ms64_block = 0
			ms64_time = 0
			ms128_read = 0
			ms128_block = 0
			ms128_time = 0
			ms256_read = 0
			ms256_block = 0
			ms256_time = 0
			msbig_read = 0
			msbig_block = 0
			msbig_time = 0
			while (getline < waifil > 0) {
				if (debug != 0) print "      Read waifil"
				elem = split(\$0, arr, "~")
				if ((arr[1] == "db file sequential read" || \\
					substr(arr[1],1,12) == \\
					"db file scat") && arr[4] > 0) {
					if (found == 0) {
						print " " >> outf
						print "                Disk" \\
							" Read Time" \\
							" Histogram Summary" \\
							" for this cursor" \\
							>> outf
						print " " >> outf
						print "Millisecond          " \\
							"              I/O  " \\
							"  Pct of Pct of" \\
							" Throughput" \\
							" Throughput" >> outf
						print " Range per    Number " \\
							"  Number   Read Tim" \\
							"e  Total  Total" \\
							"  (Reads/" \\
							"   (DBblocks/" >> outf
						print "   Read      of Reads" \\
							" of Blocks  in secs" \\
							"   Reads Blocks" \\
							"  second)" \\
							"     second)" >> outf
						print "-----------  --------" \\
							" ---------" \\
							" --------- ------" \\
							" ------ ----------" \\
							" ----------" >> outf
						found = 1
					}
					blocks = arr[4]
					ela = arr[5]
					objn = arr[7]
					ms = int((1000 * ela) / 100)
					if (ms <= 1) {
						ms1_read = ms1_read + 1
						ms1_block = ms1_block + blocks
						ms1_time = ms1_time + ela
					} else {
					 if (ms <= 2) {
						ms2_read = ms2_read + 1
						ms2_block = ms2_block + blocks
						ms2_time = ms2_time + ela
					 } else {
					  if (ms <= 4) {
						ms4_read = ms4_read + 1
						ms4_block = ms4_block + blocks
						ms4_time = ms4_time + ela
					  } else {
					   if (ms <= 8) {
						ms8_read = ms8_read + 1
						ms8_block = ms8_block + blocks
						ms8_time = ms8_time + ela
					   } else {
					    if (ms <= 16) {
						ms16_read = ms16_read + 1
						ms16_block = ms16_block + blocks
						ms16_time = ms16_time + ela
					    } else {
					     if (ms <= 32) {
						ms32_read = ms32_read + 1
						ms32_block = ms32_block + blocks
						ms32_time = ms32_time + ela
					     } else {
					      if (ms <= 64) {
						ms64_read = ms64_read + 1
						ms64_block = ms64_block + blocks
						ms64_time = ms64_time + ela
					      } else {
					       if (ms <= 128) {
						ms128_read = ms128_read + 1
						ms128_block = ms128_block + \\
							blocks
						ms128_time = ms128_time + ela
					       } else {
					        if (ms <= 256) {
						 ms256_read = ms256_read + 1
						 ms256_block = ms256_block + \\
							blocks
						 ms256_time = ms256_time + ela
					        } else {
						 msbig_read = msbig_read + 1
						 msbig_block = msbig_block + \\
							blocks
						 msbig_time = msbig_time + ela
					        }
					       }
					      }
					     }
					    }
					   }
					  }
					 }
					}
				}
			}
			close(waifil)
			if (ms1_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					0, 1, ms1_read, ms1_block, \\
					ms1_time / 100, \\
					int(100 * ms1_read / totreads), \\
					"%", \\
					int(100 * ms1_block / totblocks), \\
					"%", \\
					int(ms1_read / (ms1_time / 100)), \\
					int(ms1_block / (ms1_time / 100)) \\
					>> outf
			}
			if (ms2_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					1, 2, ms2_read, ms2_block, \\
					ms2_time / 100, \\
					int(100 * ms2_read / totreads), \\
					"%", \\
					int(100 * ms2_block / totblocks), \\
					"%", \\
					int(ms2_read / (ms2_time / 100)), \\
					int(ms2_block / (ms2_time / 100)) \\
					>> outf
			}
			if (ms4_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					2, 4, ms4_read, ms4_block, \\
					ms4_time / 100, \\
					int(100 * ms4_read / totreads), \\
					"%", \\
					int(100 * ms4_block / totblocks), \\
					"%", \\
					int(ms4_read / (ms4_time / 100)), \\
					int(ms4_block / (ms4_time / 100)) \\
					>> outf
			}
			if (ms8_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					4, 8, ms8_read, ms8_block, \\
					ms8_time / 100, \\
					int(100 * ms8_read / totreads), \\
					"%", \\
					int(100 * ms8_block / totblocks), \\
					"%", \\
					int(ms8_read / (ms8_time / 100)), \\
					int(ms8_block / (ms8_time / 100)) \\
					>> outf
			}
			if (ms16_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					8, 16, ms16_read, ms16_block, \\
					ms16_time / 100, \\
					int(100 * ms16_read / totreads), \\
					"%", \\
					int(100 * ms16_block / totblocks), \\
					"%", \\
					int(ms16_read / \\
					(ms16_time / 100)), \\
					int(ms16_block / \\
					(ms16_time / 100)) >> outf
			}
			if (ms32_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					16, 32, ms32_read, ms32_block, \\
					ms32_time / 100, \\
					int(100 * ms32_read / totreads), \\
					"%", \\
					int(100 * ms32_block / totblocks), \\
					"%", \\
					int(ms32_read / \\
					(ms32_time / 100)), \\
					int(ms32_block / \\
					(ms32_time / 100)) >> outf
			}
			if (ms64_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					32, 64, ms64_read, ms64_block, \\
					ms64_time / 100, \\
					int(100 * ms64_read / totreads), \\
					"%", \\
					int(100 * ms64_block / totblocks), \\
					"%", \\
					int(ms64_read / \\
					(ms64_time / 100)), \\
					int(ms64_block / \\
					(ms64_time / 100)) >> outf
			}
			if (ms128_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					64, 128, ms128_read, ms128_block, \\
					ms128_time / 100, \\
					int(100 * ms128_read / totreads), \\
					"%", \\
					int(100 * ms128_block / totblocks), \\
					"%", \\
					int(ms128_read / \\
					(ms128_time / 100)), \\
					int(ms128_block / \\
					(ms128_time / 100)) >> outf
			}
			if (ms256_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					128, 256, ms256_read, ms256_block, \\
					ms256_time / 100, \\
					int(100 * ms256_read / totreads), \\
					"%", \\
					int(100 * ms256_block / totblocks), \\
					"%", \\
					int(ms256_read / \\
					(ms256_time / 100)), \\
					int(ms256_block / \\
					(ms256_time / 100)) >> outf
			}
			if (msbig_read > 0) {
				printf \\
				"%4d - %4d%10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					256, "+", msbig_read, msbig_block, \\
					msbig_time / 100, \\
					int(100 * msbig_read / totreads), \\
					"%", \\
					int(100 * msbig_block / totblocks), \\
					"%", \\
					int(msbig_read / \\
					(msbig_time / 100)), \\
					int(msbig_block / \\
					(msbig_time / 100)) >> outf
			}
			if (found != 0) {
				print "-----------  -------- ---------" \\
					" --------- ------ ------ ----------" \\
					" ----------" >> outf
				printf \\
			      "   Total   %10d%10d%10.2f%6d%s%6d%s%11d%11d\n",\\
					totreads, totblocks, \\
					totread_time / 100, 100, "%", 100, \\
					"%", int(totreads / \\
					(totread_time / 100)), \\
					int(totblocks / \\
					(totread_time / 100)) >> outf
				print " " >> outf
			}
		}
		if (debug != 0) print "      Delete waifil"
		system("rm -f " waifil)
		tempwaits = 0
	}
} function print_stats_detail_line() {
	if (fnd == 0) {
		print "" >> outf
		print "      Rows  Row Source Operation" >> outf
		print "----------  ----------------------" \\
			"-----------------------------" >> outf
		fnd = 1
	}
	if (debug != 0) print "  Stat from trc line " trc_line
	# Reinsert any tildes that I previously replaced
	gsub("!@#","~",arr[11])
	# Calculate indentation and print STAT info
	found = 0
	nn = 0
	while (nn < statn) {
		++nn
		if (stat_id[nn] == arr[3]) {
			found = nn
			nn = statn
		}
	}
	if (found == 0) {
		link = 0
	} else {
		link = stat_indent[found] + 1
	}
	++statn
	stat_id[statn] = arr[2]
	stat_indent[statn] = link
	indent = substr(\\
		"                                                  ",\\
		1, 2 + link)
	printf "%10d%s%s\n", arr[1], indent, arr[11] >> outf
	if (arr[9] != 0 || arr[10] != 0) {
		printf "%sPartition Start: %s  Partition End: %s\n", \\
			"            ", arr[9], arr[10] >> outf
	}
} function print_prior_stats() {
	fnd = 0
	++plan_ctr
	if (plan_ctr > 1) {
		print "" >> outf
		print "                        (Multiple Plans For This" \\
			" Cursor)" >> outf
		if (debug != 0) print "  multiple plans"
	}
	if (prior_elem == 0) {
		if (debug != 0) print "      prior_elem=0, stat_elem=" stat_elem
		# Print current STAT lines stored in memory
		for (xx=1;xx<=stat_elem;xx++) {
			elem = split(curr_stats[xx], arr, "~")
			if (elem != 14) {
				print "Unexpected number of columns(" elem \\
					") in stats line:"
				print curr_stats[xx]
				continue
			}
			trc_line = curr_stats_nr[xx]
			xxx = print_stats_detail_line()
		}
		stat_elem = 0
	} else {
		if (debug != 0) print "      prior_elem=" prior_elem \\
			", stat_elem=" stat_elem
		# Print prior STAT lines stored in memory
		for (xx=1;xx<=prior_elem;xx++) {
			elem = split(store_stats[xx], arr, "~")
			if (elem != 14) {
				print "Unexpected number of columns(" elem \\
					") in stats line:"
				print store_stats[xx]
				continue
			}
			trc_line = store_stats_nr[xx]
			xxx = print_stats_detail_line()
		}
		prior_elem = 0
	}
} function print_segs_detail_line() {
	if (found == 0) {
		print "" >> outf
		print "                            Segment-Level" \\
			" Statistics" >> outf
		print "" >> outf
		if (arr[12] == ".") {
			print "                                         " \\
				"                        Elapsed Time" >> outf
			print "   Object ID        Logical I/Os      Phy" \\
				"s Reads     Phys Writes  (seconds)" >> outf
			print "   ------------- --------------- --------" \\
				"------- --------------- ------------" >> outf
		} else {
			print "                                Phys   Phys " \\
				" Elapsed Time" >> outf
			print "   Object ID   Logical I/Os     Reads Writes" \\
				"  (seconds)     Cost     Size   Card" >> outf
			print "   ----------- ------------ --------- ------" \\
				" ------------ ------ -------- ------" >> outf
			cost_flag = 1
		}
	}
	if (cost_flag == 0) {
		printf "   %13d %15d %15d %15d %12.6f\n", \\
			arr[4], arr[5], arr[6], arr[7], arr[8] / 1000000 >> outf
	} else {
		a4 = kmc(arr[4], 11)
		a5 = kmc(arr[5], 12)
		a6 = kmc(arr[6], 9)
		a7 = kmc(arr[7], 6)
		a12 = kmc(arr[12], 6)
		a13 = kmc(arr[13], 8)
		a14 = kmc(arr[14], 6)
		printf "   %11s %12s %9s %6s %12.6f %6s %8s %6s\n", \\
			a4, a5, a6, a7, arr[8] / 1000000, a12, a13, a14 >> outf
	}
	t4 = t4 + arr[5]
	t5 = t5 + arr[6]
	t6 = t6 + arr[7]
	t7 = t7 + arr[8]
	t8 = t8 + arr[12]
	found = 1
} function print_prior_seg_stats() {
	++seg_plan_ctr
	if (seg_plan_ctr > 1) {
		print "              (Multiple Segment-Level Statistics For" \\
			" This Cursor)" >> outf
		print "" >> outf
		if (debug != 0) print "  multiple segment-level plans"
	}
	if (prior_seg == 0) {
		if (debug != 0) print "  prior_seg=0, stat_seg=" stat_seg
		# Print current segment statistics lines stored in memory
		for (xx=1;xx<=stat_seg;xx++) {
			elem = split(curr_segs[xx], arr, "~")
			if (elem != 14) {
				print "Unexpected number of columns(" elem \\
					") in seg stats line:"
				print curr_segs[xx]
				continue
			}
			xxx = print_segs_detail_line()
		}
		stat_seg = 0
	} else {
		if (debug != 0) print "  prior_seg=" prior_seg \\
			", stat_seg=" stat_seg
		# Print prior segment statistics lines stored in memory
		for (xx=1;xx<=prior_seg;xx++) {
			elem = split(store_segs[xx], arr, "~")
			if (elem != 14) {
				print "Unexpected number of columns(" elem \\
					") in seg stats line:"
				print store_segs[xx]
				continue
			}
			xxx = print_segs_detail_line()
		}
		prior_seg = 0
	}
	if (seg_plan_ctr > 1) {
		print "" >> outf
	}
} function process_prior_code() {
	if (debug != 0) print "  ++ Process prior code of " prev_code " on " \\
		curlin
	# See if code for Cursors
	if (prev_code == 0) {
		if (tempwaits == 1) xx = print_temp_waits()
	}
	# See if code for Parameters used by the optimizer
	if (prev_code == 1) print "" >> outf
	# See if code for SQL Text
	if (prev_code == 2) {
		print "" >> outf
		if (prev_hv == "0") {
			if (sqlid != ".") print "SQL ID: " sqlid >> outf
		} else {
			if (sqlid == ".") {
				print "SQL Hash Value: " prev_hv >> outf
			} else {
				print "SQL Hash Value: " prev_hv \\
					"   SQL ID: " sqlid >> outf
			}
		}
		print "" >> outf
		#
		# Print any bind variables for the prior cursor
		#
		if (debug != 0) print "  Read bind variables for" \\
			" prev_cur " prev_cur "..."
		cnt = 0
		found_bind = 0
		fil = tmpf "/binds/" prev_cur
		while (getline < fil > 0) {
			++cnt
			if (found_bind == 0) {
				print "          First 100 Bind" \\
					" Variable Values (Including" \\
					" any peeked values)" >> outf
				print "" >> outf
				print "     Bind Number    Bind Valu" \\
					"e                         " \\
					"          Trace line" >> outf
				print "     -----------    --------" \\
					"---------------------" \\
					"--------------- ----------" \\
					>> outf
			}
			if (cnt <= 100) {
				if (length(\$0) <= 75) {
					print \$0 >> outf
				} else {
					# Wrap long variables over
					# multiple lines
					print substr(\$0, 1, 64) >> outf
					xxx = substr(\$0, 65)
					ll = length(xxx)
					while (ll > 0) {
						if (ll > 55) {
							print offst \\
							    substr(xxx, 1, \\
							    44) >> outf
							xxx = substr(xxx, 45)
							ll = ll - 44
						} else {
							if (ll < 55) {
							  print offst \\
							    substr(xxx, 1, \\
							    ll - 10) \\
							    substr(blanks, \\
							    1, 55 - ll) \\
							    substr(xxx, ll - \\
							    9) >> outf
							} else {
							  print offst xxx \\
								>> outf
							}
							ll = 0
						}
					}
				}
			}
			found_bind = 1
		}
		close(fil)
		if (cnt == 1) print "                         Total of 1" \\
			" bind variable" >> outf
		if (cnt > 1) print "                         Total of " cnt \\
			" bind variables" >> outf
		if (found_bind != 0) print "" >> outf
	}
	# See if code for Parse/Execute/Fetch/Close/Lobread/Lobpgsize/
	# Lobwrite/Lobgetlen/Lobappend/Lobarrread/Lobarrtmpfre/Lobarrwrite/
	# Lobtmpfre times
	if (prev_code == 3) {
		if (print_parse_totals != 0) {
			xx = print_prev_operation()
			print "----------- ------ -------- ----------" \\
				" --------- --------- ---------" \\
				" ---------" >> outf
			printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
				"total", tcount, tcpu / 100, \\
				telapsed / 100, tdisk, tquery, \\
				tcurrent, trows >> outf
			print_parse_totals = 0
		}
		if (stgap >= 1) {
			printf "\n%s %7.2f\n", \\
				"  Timing Gap error (secs):", \\
				stgap / 100 >> outf
		}
		if (avg_read_time > 0) {
			printf "\n%s%s%8d\n", \\
				"Avg time to read one disk", \\
				" block(ms): ", avg_read_time >> outf
		}
		# Omit, as this only calculates the time between the
		# prior cursor and this cursor, not the elapsed time of
		# this cursor
		#if (elapsed_time >= 100) {
		#	printf "\n%s%13.2f\n", \\
		#		"Elapsed wall clock time (secs): ", \\
		#		int(elapsed_time) / 100 >> outf
		#}
	}
	# See if code for WAIT
	if (prev_code == 4) {
		# If we printed a parse/exec/fetch line:
		if (write_cursor_summary != 0) {
			#
			# Write summary of total cpu time, elapsed time, and
			# fetch time per cursor (sorted by descending elapsed
			# time)
			#
			telapsed = int(telapsed)
			printf \\
			    "%12d %12s %12d %12d %12d %12d %12d %12d %12d\n", \\
				telapsed, cur, uid, tcount, tcpu, \\
				totela, tdisk, tquery, tcurrent >> filelap
			#
			# Write summary of total cpu time, elapsed time, and
			# fetch time per cursor (sorted by descending fetch
			# time)
			#
			tfetch = int(tfetch)
			printf \\
			    "%12d %12s %12d %12d %12d %12d %12d %12d %12d\n", \\
				tfetch, cur, uid, tcount, tcpu, \\
				telapsed, tdisk, tquery, tcurrent >> filfetch
			write_cursor_summary = 0
		}
		if (debug != 0) print "    Print waits (totela=" totela ")..."
		if (tempwaits == 1) xx = print_temp_waits()
	}
	# See if code for Waits by Event Name/Object Number
	if (prev_code == 6) {
		found = 0
		if (tempwaits == 1) xx = print_temp_waits()
		if (print_obj_wait_totals == 1) {
			if (debug != 0) print "    Print total obj waits..."
			if (prev_event != "@" && event_ctr > 10) {
				print "     " event_ctr - 10 " more " \\
					prev_event ", Object Number " \\
					prev_objn " wait events..." \\
					>> outf
				printf "%s%9.3f %s%9.3f %s%9.3f\n", \\
					" Min Wait Time=", \\
					min_wait / 100, \\
					"Avg Wait Time=", \\
					(avg_wait / event_ctr) / \\
					100, "Max Wait Time=", \\
					max_wait / 100 >> outf
			}
			if (totela == 0) {
				print "-----------------------------" \\
					"----------" \\
					"          --------" >> outf
				printf "%-48s%9.3f\n", \\
					"Total", totela / 100 >> outf
			} else {
				print "-----------------------------" \\
					"----------" \\
					"          -------- ----" \\
					>> outf
				printf "%-48s%9.3f %3d%s\n", \\
					"Total", totela / 100, 100, \\
					"%" >> outf
			}
			print "" >> outf
			if (debug != 0) print "    Print wait subtots..."
			print "                       Sub-Totals" \\
				" by Wait Event/Object:" >> outf
			print "" >> outf
			print "                            " \\
				"                        Total" >> outf
			print "                            " \\
				"                        Wait " \\
				"       Number" >> outf
			print "                            " \\
				"              Object    Time " \\
				"         of    Avg ms" >> outf
			if (totela == 0) {
				print "Oracle Event Name           " \\
					"              Number" \\
					"   (secs)" \\
					"        Waits per Wait" >> outf
				print "----------------------------" \\
					"----------- --------" \\
					" --------" \\
					"      ------- --------" >> outf
			} else {
				print "Oracle Event Name           " \\
					"              Number" \\
					"   (secs)" \\
					"  Pct   Waits per Wait" >> outf
				print "----------------------------" \\
					"----------- --------" \\
					" --------" \\
					" ---- ------- --------" >> outf
			}
			twait = 0
			nwaits = 0
			x9 = 0
			while (x9 < wait_obj) {
				++x9
				if (totela == 0) {
					printf \\
				   "%-39s %8d %8.3f      %7d%9.2f\n",\\
					  substr(waitevs[x9], 1, 39), \\
					  waitobs[x9], \\
					  waitsecs[x9] / 100, \\
					  waitcnts[x9], (1000 * \\
					  waitsecs[x9] / 100) / \\
					  waitcnts[x9] >> outf
				} else {
					printf \\
				   "%-39s %8d %8.3f %3d%s %7d%9.2f\n",\\
					  substr(waitevs[x9], 1, 39), \\
					  waitobs[x9], \\
					  waitsecs[x9] / 100, \\
					  int(1000 * waitsecs[x9] / \\
					  totela) / 10, "%", \\
					  waitcnts[x9], (1000 * \\
					  waitsecs[x9] / 100) / \\
					  waitcnts[x9] >> outf
				}
				if (length(waitevs[x9]) > 39) \\
					print "  " substr(waitevs[x9], 40) \\
						>> outf
				twait = twait + waitsecs[x9]
				nwaits = nwaits + waitcnts[x9]
			}
			print "----------------------------" \\
				"-----------          --------" \\
				" ---- ------- --------" >> outf
			printf "%-48s %8.3f %3d%s %7d%9.2f\n",\\
				"Total", twait / 100, \\
				100, "%", nwaits, \\
				(1000 * twait / 100) / nwaits >> outf
			print "" >> outf
			if (debug != 0) print "    Print max wait..."
			print "                            " \\
				"              Object   Max ms" >> outf
			print "Oracle Event Name           " \\
				"              Number  per Wait" >> outf
			print "----------------------------" \\
				"----------- -------- ---------" >> outf
			x9 = 0
			while (x9 < wait_obj) {
				++x9
				printf "%-39s %8d %9.2f\n",\\
					substr(waitevs[x9], 1, 39), \\
					waitobs[x9], \\
					1000 * maxwait[x9] / 100 >> outf
				if (length(waitevs[x9]) > 39) \\
					print "  " \\
						substr(waitevs[x9], \\
						40) >> outf
			}
			print "" >> outf
			print_obj_wait_totals = 0
		}
	}
	# See if code for any Errors
	if (prev_code == 7) {
		if (tempwaits == 1) xx = print_temp_waits()
		#if (found != 0) print "" >> outf
	}
	# See if code for any Transaction Info
	if (prev_code == 10) {
		if (tempwaits == 1) xx = print_temp_waits()
		#if (found != 0) print "" >> outf
	}
	# See if code for any Optimizer Row Source Plan
	if (prev_code == 11) {
		if (tempwaits == 1) xx = print_temp_waits()
		# Print any prior STAT lines stored in memory
		if (stat_elem > 0 || prior_elem > 0) {
			if (debug != 0) print "    prev_code=11 code=" code \\
				": Print prior_stats stat_elem=" stat_elem \\
				" prior_elem=" prior_elem
			xx = print_prior_stats()
			plan_ctr = 0
		}
		# Print any prior segment statistic lines stored in
		# memory
		if (stat_seg > 0 || prior_seg > 0) {
			xx = print_prior_seg_stats()
		}
	}
	# See if code for any Oracle 9.2 segment-level Optimizer Statistics
	if (prev_code == 12) {
		if (tempwaits == 1) xx = print_temp_waits()
		if (t4 != 0 || t7 != 0) {
			if (cost_flag == 0) {
				print "   -------------" \\
					" ---------------" \\
					" ---------------" \\
					" ---------------" \\
					" ------------" >> outf
				printf \\
			    "       Total %19d %15d %15d %12.6f\n", \\
					t4, t5, t6, t7 / 1000000 >> outf
			} else {
				print "   -----------" \\
					" ------------" \\
					" ---------" \\
					" ------" \\
					" ------------ ------" >> outf
				  a4 = kmc(t4, 12)
				  a5 = kmc(t5, 9)
				  a6 = kmc(t6, 6)
				  a82 = kmc(t8, 6)
				printf \\
			  "         Total %12s %9s %6s %12.6f %6s\n", \\
					a4, a5, a6, t7 / 1000000, a8 \\
					>> outf
			}
		}
		if (found != 0) print "" >> outf
	}
	if (debug != 0) print "  --Done processing prior code"
} function process_prior_cur() {
	found_opt_parse = 0
	if (debug != 0) print "  Print final parse info for cur " cur \\
		", stmissparse " stmissparse
	if (cur != 9999) {
		if (stmissparse != 0 || stmissexec != 0 || stmissfetch != 0 \\
			|| op_goal > 0 || uid == "0" || uid != "0" && \\
			uid != "x" || sqlid != ".") print "" >> outf
		if (stmissparse != 0) print "Misses in library cache" \\
			" during parse: " stmissparse >> outf
		if (stmissexec != 0) print "Misses in library cache" \\
			" during execute: " stmissexec >> outf
		if (stmissfetch != 0) print "Misses in library cache" \\
			" during fetch: " stmissfetch >> outf
		if (op_goal == 1) print "Optimizer goal: All_Rows" \\
			>> outf
		if (op_goal == 2) print "Optimizer goal: First_Rows" \\
			>> outf
		if (op_goal == 3) print "Optimizer goal: Rule" >> outf
		if (op_goal == 4) print "Optimizer goal: Choose" >> outf
		if (op_goal > 4) print "Unexpected optimizer goal of " \\
			op_goal " near line " NR
		if (uid == "0") {
			print "Parsing user id: SYS" >> outf
		} else {
			if (uid != "x") print "Parsing user id: " uid >> outf
		}
		if (sqlid != ".") print "SQL ID: " sqlid >> outf
	}
	# Calculate unaccounted-for time
	unacc = int(unacc_elapsed - unacc_wait - unacc_cpu)
	# Zero if within timing degree of precision
	if (unacc < 2000) unacc = 0
	# Accum unaccounted-for time
	if (unacc >= 1000) {
		unacc_total = unacc_total + unacc
		++unacc_cnt
		if (dep == "0") {
			otunaccs[oper_indx] = otunaccs[oper_indx] + unacc
		} else {
			rotunaccs[oper_indx] = rotunaccs[oper_indx] + unacc
		}
		print "" >> outf
		printf "%s %7.2f\n", "  Unaccounted-for time:   ", \\
			unacc / 100000 >> outf
	}
	if (debug != 0) {
		if (unacc != 0) {
			print "Unaccounted-for time curno=" prev_cur \\
				", elapsed=" unacc_elapsed \\
				", waits=" unacc_wait \\
				", cpu=" unacc_cpu " = " unacc
		} else {
			print "No Unacc time: Elap " unacc_elapsed " - Wait " \\
				unacc_wait " - CPU " unacc_cpu " < 2000"
		}
	}
} {
	if (NF != 43) {
		print "Unexpected number of columns (" NF ") in init line:"
		print \$0
		next
	}
	filelap = tmpf "/elap"
	filfetch = tmpf "/fetch"
	filtotcur = tmpf "/waitstotcur"
	filtotact = tmpf "/waitstotact"
	# Define file to xfer the wait events
	waifil = tmpf "/xferwaits"
	if (debug != 0) print "Init report..."
	mm = \$1
	dd = \$2
	yy = \$3
	hh = \$4
	mi = \$5
	ss = \$6
	divisor = \$7
	first_time = \$8
	gap_time = \$9
	gap_cnt = \$10
	cpu_timing_parse = \$11
	cpu_timing_exec = \$12
	cpu_timing_fetch = \$13
	cpu_timing_unmap = \$14
	cpu_timing_sort = \$15
	cpu_timing_parse_cnt = \$16
	cpu_timing_exec_cnt = \$17
	cpu_timing_fetch_cnt = \$18
	cpu_timing_unmap_cnt = \$19
	cpu_timing_sort_cnt = \$20
	maxcn = \$21 + 1
	cpu_timing_rpcexec = \$22
	cpu_timing_rpcexec_cnt =\$23
	cpu_timing_close = \$24
	cpu_timing_close_cnt = \$25
	cpu_timing_lobread = \$26
	cpu_timing_lobread_cnt = \$27
	cpu_timing_lobpgsize = \$28
	cpu_timing_lobpgsize_cnt = \$29
	cpu_timing_lobwrite = \$30
	cpu_timing_lobwrite_cnt = \$31
	cpu_timing_lobgetlen = \$32
	cpu_timing_lobgetlen_cnt = \$33
	cpu_timing_lobappend = \$34
	cpu_timing_lobappend_cnt = \$35
	cpu_timing_lobarrread = \$36
	cpu_timing_lobarrread_cnt = \$37
	cpu_timing_lobarrtmpfre = \$38
	cpu_timing_lobarrtmpfre_cnt = \$39
	cpu_timing_lobarrwrite = \$40
	cpu_timing_lobarrwrite_cnt = \$41
	cpu_timing_lobtmpfre = \$42
	cpu_timing_lobtmpfre_cnt = \$43
	fil = tmpf "/eof"
	if (getline < fil > 0) {
		grand_elapsed = \$0
		if (debug != 0) print "Report: Read grand_elapsed= " \\
			grand_elapsed
	} else {
		print "Error while trying to read eof"
	}
	close(fil)
	#
	# Init for command type summaries
	#
	if (debug > 0) print "  Print command type summaries..."
	maxcmdtyp = 0
	fil = tmpf "/cmdtypes"
	while (getline < fil > 0) {
		if (NF != 10) {
			print "Unexpected number of columns (" NF \\
				") in cmdtypes line #" NR ":"
			print \$0
			continue
		}
		if (\$1 > maxcmdtyp) maxcmdtyp = \$1
	}
	close(fil)
	for (x=77;x<=maxcmdtyp;x++) cmdtypstrs[x] = x ""
	cmdtypstrs[0] = "UNKNOWN"
	cmdtypstrs[1] = "create table"
	cmdtypstrs[2] = "insert"
	cmdtypstrs[3] = "select"
	cmdtypstrs[4] = "create cluster"
	cmdtypstrs[5] = "alter cluster"
	cmdtypstrs[6] = "update"
	cmdtypstrs[7] = "delete"
	cmdtypstrs[8] = "drop cluster"
	cmdtypstrs[9] = "create index"
	cmdtypstrs[10] = "drop index"
	cmdtypstrs[11] = "alter index"
	cmdtypstrs[12] = "drop table"
	cmdtypstrs[13] = "create sequence"
	cmdtypstrs[14] = "alter sequence"
	cmdtypstrs[15] = "alter table"
	cmdtypstrs[16] = "drop sequence"
	cmdtypstrs[17] = "grant"
	cmdtypstrs[18] = "revoke"
	cmdtypstrs[19] = "create synonym"
	cmdtypstrs[20] = "drop synonym"
	cmdtypstrs[21] = "create view"
	cmdtypstrs[22] = "drop view"
	cmdtypstrs[23] = "validate index"
	cmdtypstrs[24] = "create procedure"
	cmdtypstrs[25] = "alter procedure"
	cmdtypstrs[26] = "lock table"
	cmdtypstrs[27] = "no operation"
	cmdtypstrs[28] = "rename"
	cmdtypstrs[29] = "comment"
	cmdtypstrs[30] = "audit"
	cmdtypstrs[31] = "noaudit"
	cmdtypstrs[32] = "create database link"
	cmdtypstrs[33] = "drop database link"
	cmdtypstrs[34] = "create database"
	cmdtypstrs[35] = "alter database"
	cmdtypstrs[36] = "create rollback segment"
	cmdtypstrs[37] = "alter rollback segment"
	cmdtypstrs[38] = "drop rollback segment"
	cmdtypstrs[39] = "create tablespace"
	cmdtypstrs[40] = "alter tablespace"
	cmdtypstrs[41] = "drop tablespace"
	cmdtypstrs[42] = "alter session"
	cmdtypstrs[43] = "alter use"
	cmdtypstrs[44] = "commit"
	cmdtypstrs[45] = "rollback"
	cmdtypstrs[46] = "savepoint"
	cmdtypstrs[47] = "pl/sql execute"
	cmdtypstrs[48] = "set transaction"
	cmdtypstrs[49] = "alter system switch log"
	cmdtypstrs[50] = "explain"
	cmdtypstrs[51] = "create user"
	cmdtypstrs[52] = "create role"
	cmdtypstrs[53] = "drop user"
	cmdtypstrs[54] = "drop role"
	cmdtypstrs[55] = "set role"
	cmdtypstrs[56] = "create schema"
	cmdtypstrs[57] = "create control file"
	cmdtypstrs[58] = "alter tracing"
	cmdtypstrs[59] = "create trigger"
	cmdtypstrs[60] = "alter trigger"
	cmdtypstrs[61] = "drop trigger"
	cmdtypstrs[62] = "analyze table"
	cmdtypstrs[63] = "analyze index"
	cmdtypstrs[64] = "analyze cluster"
	cmdtypstrs[65] = "create profile"
	cmdtypstrs[66] = "drop profile"
	cmdtypstrs[67] = "alter profile"
	cmdtypstrs[68] = "drop procedure"
	cmdtypstrs[69] = "drop procedure"
	cmdtypstrs[70] = "alter resource cost"
	cmdtypstrs[71] = "create snapshot log"
	cmdtypstrs[72] = "alter snapshot log"
	cmdtypstrs[73] = "drop snapshot log"
	cmdtypstrs[74] = "create snapshot"
	cmdtypstrs[75] = "alter snapshot"
	cmdtypstrs[76] = "drop snapshot"
	cmdtypstrs[79] = "alter role"
	cmdtypstrs[85] = "truncate table"
	cmdtypstrs[86] = "truncate couster"
	cmdtypstrs[88] = "alter view"
	cmdtypstrs[91] = "create function"
	cmdtypstrs[92] = "alter function"
	cmdtypstrs[93] = "drop function"
	cmdtypstrs[94] = "create package"
	cmdtypstrs[95] = "alter package"
	cmdtypstrs[96] = "drop package"
	cmdtypstrs[97] = "create package body"
	cmdtypstrs[98] = "alter package body"
	cmdtypstrs[99] = "drop package body"
	#
	# Process each cursor
	#
	if (debug != 0) print "********** Reading cursors file... **********"
	#
	# col 1 = ncur (number of cursor array element in memory)
	# col 2 = curno (cursor number from trace file)
	# col 3 = hv (hash value)
	# col 4 = code (0=cursors, 1=params, 2=sqls, 3=parse, 4=waits,
	#               6=obj waits, 7=errors, 8=module, 9=action, 10=xctend,
	#		11=non-segment-level stats, 12=segment-level stats)
	# (rest of line contains a variable number of cols, depending on code)
	#
	unacc_total = 0
	unacc_cnt = 0
	print_parse_totals = 0
	write_cursor_summary = 0
	found_opt_parse = 0
	print_obj_wait_totals = 0
	cn = 0
	curlin = 0
	tempwaits = 0
	blockwaits = 0
	plan_ctr = 0
	seg_plan_ctr = 0
	prev_cur = -1
	prev_code = -1
	prev_hv = -1
	unacc_cpu = 0
	unacc_elapsed = 0
	unacc_wait = 0
	topstmts = tmpf "/topstmts"
	curfil = tmpf "/cursors"
	while (getline < curfil > 0) {
		++curlin
		cursornf = NF
		cursor_zero = \$0
		cur = \$1
		curno = \$2
		hv = \$3
		code = \$4
		if (debug != 0) print "----Read cur " cur " curno " curno \\
			" hv " hv " code " code " five=" \$5
		# See if hash value changes
		if (hv != prev_hv) {
			# Print any prior STAT lines stored in memory
			if (stat_elem > 0 || prior_elem > 0) {
				if (debug != 0) print "    new hv " hv \\
					" prev_hv=" prev_hv ": Print" \\
					" prior_stats stat_elem=" stat_elem \\
					" prior_elem=" prior_elem
				xx = print_prior_stats()
			}
			# Print any prior segment statistic lines stored in
			# memory
			if (stat_seg > 0 || prior_seg > 0) {
				xx = print_prior_seg_stats()
			}
			plan_ctr = 0
			seg_plan_ctr = 0
			stat_elem = 0
			stat_seg = 0
			prior_elem = 0
			prior_seg = 0
		}
		if (code == 0) {
			five = \$5
			six = \$6
			seven = \$7
			eight = \$8
			nine = \$9
			ten = \$10
			eleven = \$11
			twelve = \$12
			thirteen = \$13
		}
		if (code == 1) {
			cursor_line = substr(cursor_zero,47)
		}
		if (code == 2) {
			cursor_line = substr(cursor_zero,47)
		}
		if (code == 3) {
			five = \$5
			six = \$6
			seven = \$7
			eight = \$8
			nine = \$9
			ten = \$10
			eleven = \$11
			twelve = \$12
			thirteen = \$13
			fourteen = \$14
			fifteen = \$15
			sixteen = \$16
			seventeen = \$17
		}
		if (code == 11 || code == 12) stat_ndx = \$5
		if (debug != 0) print "# Read cursor " cur \\
			" curno=" curno " code=" code \\
			" prev_code=" prev_code " NR=" curlin
		if (prev_cur != cur) {
			if (prev_code >= 0) xx = process_prior_code()
			if (found_opt_parse != 0) xx = process_prior_cur()
			prev_cur = cur
			prev_code = -1
			prev_hv = -1
		}
		if (prev_code != code) {
			found = 0
			prev_stat_ndx = 0
			if (prev_code >= 0) xx = process_prior_code()
			# See if code for Parse/Execute/Fetch/Close/Lobread/
			# Lobpgsize/Lobwrite/Lobgetlen/Lobappend/Lobarrread/
			# Lobarrtmpfre/Lobarrwrite/Lobtmpfre times
			if (code == 3) {
				stmissparse = 0
				stmissexec = 0
				stmissfetch = 0
				stgap = 0
				avg_read_time = 0
			}
			# See if code for WAIT
			if (code == 4) {
				blkfil = tmpf "/waitblocks"
				print "0" >> blkfil
				blockwaits = 1
				totela = 0
				totreads = 0
				totblocks = 0
				totread_time = 0
			}
			# See if code for Waits by Event Name/Object Number
			if (code == 6) {
				wait_obj = 0
			}
			# See if code for any Errors
			if (code == 7) {
				if (debug != 0) print "  Print errors..."
				if (err != "x") {
					print "Oracle Error: " err \\
						" on trace line " recn >> outf
				}
			}
			# See if code for Transaction Info
			if (code == 10) {
				if (debug != 0) print "  Print transaction..."
			}
			# See if code for any Optimizer Row Source Plan
			if (code == 11) {
				if (debug != 0) print \\
					"  Print optimizer stats..."
				statn = 0
				fnd = 0
			}
			# See if code for any Oracle 9.2 segment-level Optimizer
			# Statistics
			if (code == 12) {
				if (debug != 0) print \\
					"  Print segment-level stats..."
				t4 = 0
				t5 = 0
				t6 = 0
				t7 = 0
				t8 = 0
				cost_flag = 0
				found = 0
			}
			prev_code = code
			prev_hv = hv
		}
		# See if code for a new "PARSING IN CURSOR" or "PARSE ERROR"
		if (code == 0) {
			if (cursornf != 13) {
				print "Unexpected number of columns (" \\
					cursornf \\
					") in cursor line on line " curlin ":"
				print cursor_zero
				continue
			}
			orig_cursor = thirteen ""
			++cn
			if (debug == 0) {
				if (cn == 100 * int(cn / 100)) \\
					print "Processing cursor " cn " of " \\
						maxcn "..."
			} else {
				print "  Read cursor #" curno " in array #" \\
					cur " (cn=" cn " maxcn=" maxcn ")"
				if (orig_cursor != curno) print "  Original" \\
					" cursor #" orig_cursor
			}
			oct = five
			uid = six
			dep = seven
			elapsed_time = eight
			parsing_tim = nine
			err = ten
			recn = eleven
			sqlid = twelve
			if (debug != 0) print "  hv=" hv " elapsed=" \\
				elapsed_time
			print "" >> outf
			print "#############################################" \\
				"###################################" >> outf
			print "" >> outf
			print_parse_totals = 0
			write_cursor_summary = 0
			found_opt_parse = 1
			if (cur != 9999) {
				if (parsing_tim == 0) {
					xxx = ""
				} else {
					xxx = " at " ymdhms(parsing_tim)
				}
				if (orig_cursor == curno) {
					if (dep == "0") {
						print "ID #" cur xxx \\
							" (Cursor " \\
							curno "):" >> outf
					} else {
						print "ID #" cur \\
							" (RECURSIVE DEPTH " \\
							dep ")" xxx \\
							" (Cursor " curno \\
							"):" >> outf
					}
				} else {
					if (dep == "0") {
						print "ID #" cur xxx \\
							" (Cursor " \\
							orig_cursor "):" >> outf
					} else {
						print "ID #" cur \\
							" (RECURSIVE DEPTH " \\
							dep ")" xxx \\
							" (Cursor " \\
							orig_cursor "):" >> outf
					}
				}
				print "" >> outf
			}
			if (err != "x") {
				er = "ORA-" substr("00000",1,5-length(err)) err
				print "Oracle Parse Error: " er \\
					" on trace line " recn >> outf
				print "" >> outf
			}
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
			op_goal = 0
			if (debug != 0) print "Zero unacc counters"
			unacc_cpu = 0
			unacc_elapsed = 0
			unacc_wait = 0
		}
		# See if code for Parameters used by the optimizer
		if (code == 1) {
			if (debug != 0) print "  Read Optimizer Parameters..."
			print cursor_line >> outf
		}
		# See if code for SQL Text
		if (code == 2) {
			if (debug != 0) print "  Read SQL text..."
			print cursor_line >> outf
		}
		# See if code for Parse/Execute/Fetch/Close/Lobread/Lobpgsize/
		# Lobwrite/Lobgetlen/Lobappend/Lobarrread/Lobarrtmpfre/
		# Lobarrwrite/Lobtmpfre times
		if (code == 3) {
			if (debug != 0) print "  Read parse/exec/fetch for" \\
				" line " seventeen "..."
			if (cursornf != 17) {
				print "Unexpected number of columns" \\
					" (" cursornf ") in parse line" \\
					" for hash value " hv " on line " \\
					curlin ":"
				print cursor_zero
				continue
			}
			if (print_parse_totals == 0) {
				print "call         count      cpu" \\
					"    elapsed      disk" \\
					"     query   current" \\
					"      rows" >> outf
				print "----------- ------ --------" \\
					" ---------- ---------" \\
					" --------- ---------" \\
					" ---------" >> outf
				print_parse_totals = 1
				write_cursor_summary = 1
				prev_op = "@"
				tcount = 0
				tcpu = 0
				telapsed = 0
				tfetch = 0
				tdisk = 0
				tquery = 0
				tcurrent = 0
				trows = 0
			}
			op = five
			if (prev_op != op) {
				if (prev_op != "@") {
					xx = print_prev_operation()
				}
				prev_op = op
				stcount = 0
				stcpu = 0
				stelapsed = 0
				stdisk = 0
				stquery = 0
				stcurrent = 0
				strows = 0
				op_goal = thirteen
				tim = fourteen
				gap_tim = fifteen
				sqlid = sixteen
				parse_nr = seventeen
			}
			++stcount
			unacc_cpu = unacc_cpu + int(six * 1000)
			if (debug != 0) {
				if (int(six * 1000) > 0) {
					print "Read: " \$0
					print "Accum unacc cpu " \\
						int(six * 1000) " on line " \\
						curlin " - Total of " unacc_cpu
				}
			}
			stcpu = stcpu + six
			unacc_elapsed = unacc_elapsed + int(seven * 1000)
			if (debug != 0) {
				if (int(seven * 1000) > 0) {
					print "Read: " \$0
					print "Accum unacc elapsed " \\
						int(seven * 1000) " on line " \\
						curlin " - Total of " \\
						unacc_elapsed
				}
			}
			stelapsed = stelapsed + seven
			stdisk = stdisk + eight
			stquery = stquery + nine
			stcurrent = stcurrent + ten
			strows = strows + eleven
			if (debug != 0) {
				if (op == "1") print "  Accum " twelve \\
					" into stmissparse"
			}
			if (op == "1") stmissparse = stmissparse + twelve
			if (op == "2") stmissexec = stmissexec + twelve
			if (op == "3") stmissfetch = stmissfetch + twelve
			stgap = stgap + fifteen
			seventeen = sixteen
			# Write time for each operation
			if (op == "1") printop = "Parse"
			if (op == "2") printop = "Execute"
			if (op == "3") printop = "Fetch"
			if (op == "4") printop = "Unmap"
			if (op == "5") printop = "Srt Unm"
			if (op == "6") printop = "Close"
			if (op == "7") printop = "Lobread"
			if (op == "8") printop = "Lobpgsiz"
			if (op == "9") printop = "Lobwrite"
			if (op == "10") printop = "Lobgetlen"
			if (op == "11") printop = "Lobappend"
			if (op == "12") printop = "Lobarrread"
			if (op == "13") printop = "Lobarrtmpfr"
			if (op == "14") printop = "Lobarrwrite"
			if (op == "15") printop = "Lobtmpfre"
			if (int(seven * 10000) > 0) {
				#if (debug != 0) print \\
				#	"Write top stmnt event: " printop
				printf "%-50s~%-12s~%18s~%16s\n", \\
					printop, hv, curno, \\
					int(seven * 10000) >> topstmts
			}
		}
		# See if code for WAIT
		if (code == 4) {
			elem = split(substr(cursor_zero,41), arr, "~")
			if (elem != 7) {
				print "Unexpected number of columns (" elem \\
					") in waits line " NR \\
					" for hash value " hv " on line " \\
					curlin ":"
				print cursor_zero
				continue
			}
			ela = arr[5]
			if (debug != 0) print "  Read total wait of " ela \\
				" on " NR "..."
			# Accum total Wait Time by file/block number
			if (arr[1] == "db file sequential read" || \\
				substr(arr[1],1,12) == "db file scat") {
				totreads = totreads + 1
				totblocks = totblocks + arr[4]
				totread_time = totread_time + ela
				printf "%12d %12d\n", arr[2], arr[3] >> blkfil
				blockwaits = 1
			}
			# Accum total Wait Time
			totela = totela + ela
			unacc_wait = unacc_wait + int(ela * 1000)
			if (debug != 0) {
				if (int(ela * 1000) > 0) {
					print "Read: " \$0
					print "Accum unacc wait " \\
						int(ela * 1000) " on line " \\
						curlin " - Total of " unacc_wait
				}
			}
			# Copy the wait events to a temp file
			if (debug != 0) print "  Write wait events to" \\
				" waifil: " substr(cursor_zero,41)
			print substr(cursor_zero,41) >> waifil
			tempwaits = 1
			# Write time for each wait event
			if (int(ela * 10000) > 0) {
				#if (debug != 0) print \\
				#	"Write top stmnt wait: " arr[1]
				printf "%-50s~%-12s~%18s~%16s\n", \\
					substr(arr[1], 1, 50), hv, curno, \\
					int(ela * 10000) >> topstmts
			}
		}
		# See if code for Waits by Event Name/Object Number (code=6)
		if (code == 6) {
			elem = split(substr(cursor_zero,41), arr, "~")
			if (elem != 7) continue
			nam = arr[1]
			objn = arr[2]
			if (objn <= 0) continue
			ela = arr[6]
			if (substr(nam,1,17) == "buffer busy waits" || \\
				substr(nam,1,16) == "direct path read" || \\
				substr(nam,1,17) == "direct path write" || \\
				nam == "free buffer waits" || \\
				nam == "write complete waits" || \\
				nam == "buffer busy global cache" || \\
				nam == "buffer busy global CR" || \\
				nam == "buffer read retry" || \\
				nam == "control file sequential read" || \\
				nam == "control file single write" || \\
				nam == "conversion file read" || \\
				nam == "db file single write" || \\
				nam == "global cache lock busy" || \\
				nam == "global cache lock cleanup" || \\
				nam == "global cache lock null to s" || \\
				nam == "global cache lock null to x" || \\
				nam == "global cache lock open null" || \\
				nam == "global cache lock open s" || \\
				nam == "global cache lock open x" || \\
				nam == "global cache lock s to x" || \\
				nam == "local write wait" || \\
				substr(nam,1,12) == "db file scat" || \\
				substr(nam,1,11) == "db file seq") {
					file_numb = arr[3] # p1
					block_numb = arr[4] # p2
			} else {
				file_numb = ""
				block_numb = ""
			}
			if (substr(nam,1,11) == "enqueue (Na") {
				rollback_seg = arr[4]	# p2
			} else {
				rollback_seg = 0
			}
			if (100 * ela >= 1) {
				if (print_obj_wait_totals == 0) {
					print " " >> outf
					if (hv == 1) {
						print "            " \\
							"        " \\
							"Unaccounted" \\
							" Wait" \\
							" Events for" \\
							" all" \\
							" cursors" \\
							>> outf
					} else {
						print "            " \\
							"        " \\
							"Significant" \\
							" Wait" \\
							" Events by" \\
							" Object" \\
							>> outf
					}
					print " " >> outf
					print "                 " \\
						"               " \\
						"               " \\
						"     Total" >> outf
					print "                 " \\
						"               " \\
						"               " \\
						"     Wait" >> outf
					print "                 " \\
						"               " \\
						"          Objec" \\
						"t    Time      " \\
						" File   Block" >> outf
					if (totela == 0) {
						print \\
						  "Oracle Event Name" \\
						  "               " \\
						  "          Numbe" \\
						  "r   (secs)     " \\
						  " Numb  Number" \\
						  >> outf
						print \\
						  "-----------------" \\
						  "---------------" \\
						  "------- -------" \\
						  "- --------     " \\
						  " ---- -------" \\
						  >> outf
					} else {
						print \\
						  "Oracle Event Name" \\
						  "               " \\
						  "          Numbe" \\
						  "r   (secs)  Pct" \\
						  " Numb  Number" \\
						  >> outf
						print \\
						  "-----------------" \\
						  "---------------" \\
						  "------- -------" \\
						  "- -------- ----" \\
						  " ---- -------" \\
						  >> outf
					}
					print_obj_wait_totals = 1
					prev_event = "@"
					prev_objn = -9
					event_ctr = 0
				}
				recnum = arr[7]
				if (prev_event != nam || prev_objn != objn || \\
					event_ctr < 11) {
					if (prev_event != "@" && \\
						event_ctr > 10) {
						print "     " \\
							event_ctr - \\
							10 " more " \\
							prev_event \\
							", Object #" \\
							prev_objn \\
							" wait" \\
							" events..." \\
							>> outf
						printf \\
					   "%s%9.3f %s%9.3f %s%9.3f\n", \\
							"Min Wait Time=", \\
							min_wait / 100, \\
							"Avg Wait Time=", \\
							(avg_wait / \\
							event_ctr) / 100, \\
							"Max Wait Time=", \\
							max_wait / 100 >> outf
					}
					if (totela == 0) {
						printf \\
					    "%-39s %8d %8.3f      %4s%8s\n", \\
							substr(nam, 1, 39), \\
							objn, ela / 100, \\
							file_numb, \\
							block_numb >> outf
					} else {
						printf \\
					    "%-39s %8d %8.3f %3d%s %4s%8s\n", \\
							substr(nam, 1, 39), \\
							objn, ela / 100, \\
							int(1000 * ela / \\
							totela) / 10, "%", \\
							file_numb, \\
							block_numb >> outf
					}
					if (length(nam) > 39) \\
						print "  " substr(nam, 40) \\
							>> outf
					if (substr(nam,1,11) == "enqueue (Na") {
						rbsn = int(rollback_seg \\
							/ 65536)
						print "  Rollback segment #" \\
							rbsn ", Slot #" \\
							rollback_seg \\
							- (rbsn * 65536) >> outf
					}
					if (prev_event != nam || \\
						prev_objn != objn) {
						prev_event = nam
						prev_objn = objn
						min_wait = 9999999999999
						avg_wait = 0
						max_wait = 0
						event_ctr = 0
					}
				}
				rest = 0
				++event_ctr
				avg_wait = avg_wait + ela
				if (ela < min_wait) min_wait = ela
				if (ela > max_wait) max_wait = ela
			}
			# Accum subtotals by event name/object
			if (debug != 0) print "  Accum wait subtots..."
			x9 = 0
			mtch = 0
			while (x9 < wait_obj) {
				++x9
				if (file_numb == "") {
					if (waitevs[x9] == nam && \\
						waitobs[x9] == objn) {
						mtch = x9
						x9 = wait_obj
					}
				} else {
					if (waitevs[x9] == nam " (File " \\
						file_numb ")" && \\
						waitobs[x9] == objn) {
						mtch = x9
						x9 = wait_obj
					}
				}
			}
			if (mtch == 0) {
				++wait_obj
				if (file_numb == "") {
					waitevs[wait_obj] = nam
				} else {
					waitevs[wait_obj] = nam \\
						" (File " file_numb ")"
				}
				waitobs[wait_obj] = objn
				maxwait[wait_obj] = ela
				waitsecs[wait_obj] = ela
				waitcnts[wait_obj] = 1
				ms1_wait[wait_obj] = 0
				ms2_wait[wait_obj] = 0
				ms4_wait[wait_obj] = 0
				ms8_wait[wait_obj] = 0
				ms16_wait[wait_obj] = 0
				ms32_wait[wait_obj] = 0
				ms64_wait[wait_obj] = 0
				ms128_wait[wait_obj] = 0
				ms256_wait[wait_obj] = 0
				msbig_wait[wait_obj] = 0
				mtch = wait_obj
			} else {
				waitsecs[mtch] = waitsecs[mtch] + ela
				if (ela > maxwait[mtch]) maxwait[mtch] = ela
				++waitcnts[mtch]
			}
			if (debug != 0) print "  Accum obj wait hists..."
			if (ela * 1000 <= 100) {
				++ms1_wait[mtch]
			} else {
			  if (ela * 500 <= 100) {
			    ++ms2_wait[mtch]
			  } else {
			    if (ela * 250 <= 100) {
			      ++ms4_wait[mtch]
			    } else {
			      if (ela * 125 <= 100) {
				++ms8_wait[mtch]
			      } else {
				if (ela * 125 <= 2 * 100) {
				  ++ms16_wait[mtch]
				} else {
				  if (ela * 125 <= 4 * 100) {
				    ++ms32_wait[mtch]
				  } else {
				    if (ela * 125 <= 8 * 100) {
				      ++ms64_wait[mtch]
				    } else {
				      if (ela * 125 <= 16 * 100) {
					++ms128_wait[mtch]
				      } else {
					if (ela * 125 <= 32 * 100) {
					  ++ms256_wait[mtch]
					} else {
					  ++msbig_wait[mtch]
					}
				      }
				    }
				  }
				}
			      }
			    }
			  }
			}
		}
		# See if code for any Errors
		if (code == 7) {
			elem = split(substr(cursor_zero,41), arr, "~")
			if (elem != 3) {
				print "Unexpected number of columns (" \\
					cursornf ") in errors line " NR \\
					" for hash value " hv " on line " \\
					curlin ":"
				print cursor_zero
				continue
			}
			err = arr[1]
			recnum = arr[2]
			errtim = arr[3]
			if (debug != 0) print "    Read Error: " err " " \
				recnum " " errtim
			er = "ORA-" substr("00000",1,5-length(err)) err
			#Ignore error time, since it may be more than 2gig
			#xx = ymdhms(errtim)
			#if (debug != 0) print "    at time: " xx
			print "Oracle Error " er " on trace line " \\
				recnum >> outf
			found = 1
		}
		# See if code for module for this cursor
		if (code == 8) {
			print "Module: " substr(cursor_zero,41) >> outf
		}
		# See if code for action for this cursor
		if (code == 9) {
			print "Action: " substr(cursor_zero,41) >> outf
		}
		# See if code for Transaction Info
		if (code == 10) {
			print substr(cursor_zero,41) >> outf
			found = 1
		}
		# See if code for any Optimizer Row Source Plan
		if (code == 11) {
			if (debug != 0) print "    STAT: stat_ndx=" stat_ndx \\
				" prev_stat_ndx=" prev_stat_ndx \\
				" stat_elem=" stat_elem
			if (prev_stat_ndx == stat_ndx) {
				# Append to current set of STAT lines in memory
				++stat_elem
				# Store all STAT fields, except for NR
				elem = split(substr(cursor_zero,53), arr, "~")
				curr_stats[stat_elem] = arr[1]
				for(xx=2;xx<elem;xx++) \\
					curr_stats[stat_elem] = \\
						curr_stats[stat_elem] "~" \\
						arr[xx]
				# Store the STAT line NR
				curr_stats_nr[stat_elem] = arr[elem]
				if (debug != 0) print "      Append [" \\
					stat_elem "]: " substr(cursor_zero,53)
			} else {
				# If another current set of STAT lines found:
				if (stat_elem > 0) {
					if (debug != 0) print "      Found " \\
						stat_elem " prior stats..."
					# See if current and prior stats exist
					if (prior_elem > 0) {
						# See if stats have changed
						if (prior_elem == stat_elem) {
							diff_stats = 0
							for (xx=1;\\
							  xx<=stat_elem;xx++) {
							  if (store_stats[xx] \\
							    != curr_stats[xx]) {
								diff_stats = 1
							  }
							}
							if (debug != 0) {
								if (\\
								  diff_stats \\
								  == 0) {
								  print "   " \\
								    "   same"
								} else {
								  print "   " \\
								    "   diff"
								}
							}
						} else {
							diff_stats = 1
							if (debug != 0) {
								print "      "\\
								    "diff" \\
								    " elems"
							}
						}
						# Print if stats have changed
						# Ignore duplicate stats
						if (diff_stats != 0) {
							if (debug != 0) print \\
							  "    diff stats:" \\
							  " Print prior_stats"\\
							  " stat_elem=" \\
							  stat_elem \\
							  " prior_elem=" \\
							  prior_elem
							xx = print_prior_stats()
						}
					}
					# Move current stats to prior stats
					if (debug != 0) print "      Move" \\
						" curr->prior"
					for (xx=1;xx<=stat_elem;xx++) {
						store_stats[xx] = curr_stats[xx]
						store_stats_nr[xx] = \\
							curr_stats_nr[xx]
					}
					# Store number of prior stats lines
					prior_elem = stat_elem
					if (debug != 0) print "      Set" \\
						" prior_elem=" prior_elem
					stat_elem = 0
				}
				# Store new current set of STAT lines in memory
				stat_elem = 1
				# Store all STAT fields, except for NR
				elem = split(substr(cursor_zero,53), arr, "~")
				curr_stats[stat_elem] = arr[1]
				for(xx=2;xx<elem;xx++) \\
					curr_stats[stat_elem] = \\
						curr_stats[stat_elem] "~" \\
						arr[xx]
				# Store the STAT line NR
				curr_stats_nr[stat_elem] = arr[elem]
				if (debug != 0) print "      New Stat [1]: " \\
					substr(cursor_zero,53)
				prev_stat_ndx = stat_ndx
			}
		}
		# See if code for any Oracle 9.2 segment-level Optimizer
		# Statistics
		if (code == 12) {
			if (debug != 0) print "    SEG: stat_ndx=" stat_ndx \\
				" prev_stat_ndx=" prev_stat_ndx \\
				" stat_seg=" stat_seg
			if (prev_stat_ndx == stat_ndx) {
				# Append to current set of segment statistic
				# lines in memory
				++stat_seg
				curr_segs[stat_seg] = substr(cursor_zero,53)
				if (debug != 0) print "      Append [" \\
					stat_seg"]: " substr(cursor_zero,53)
			} else {
				# If another current set of segment statistic
				# lines found:
				if (stat_seg > 0) {
					if (debug != 0) print "      Found " \\
						stat_seg " prior segs..."
					# See if current and prior stats exist
					if (prior_seg > 0) {
						# See if stats have changed
						if (prior_seg == stat_seg) {
							diff_stats = 0
							for (xx=1;\\
							  xx<=stat_seg;xx++) {
							  if (store_segs[xx] \\
							    != curr_segs[xx]) {
								diff_stats = 1
							  }
							}
							if (debug != 0) {
								if (\\
								  diff_stats \\
								  == 0) {
								  print "   " \\
								    "   same"
								} else {
								  print "   " \\
								    "   diff"
								}
							}
						} else {
							diff_stats = 1
							if (debug != 0) {
								print "      "\\
								    "diff" \\
								    " segs"
							}
						}
						# Print if stats have changed
						# Ignore duplicate stats
						if (diff_stats != 0) {
							xx = \\
							 print_prior_seg_stats()
						}
					}
					# Move current segment statistics to
					# prior segment statistics
					if (debug != 0) print "      Move" \\
						" curr->prior"
					for (xx=1;xx<=stat_seg;xx++) {
						store_segs[xx] = curr_segs[xx]
					}
					# Store number of prior segment
					# statistic lines
					prior_seg = stat_seg
					if (debug != 0) print "      Set" \\
						" prior_seg=" prior_seg
				}
				# Store new current set of segment statistic
				# lines in memory
				stat_seg = 1
				curr_segs[stat_seg] = substr(cursor_zero,53)
				if (debug != 0) print "      New Seg [1]: " \\
					substr(cursor_zero,53)
				prev_stat_ndx = stat_ndx
			}
		}
	}
	close(curfil)
	if (prev_code >= 0) xx = process_prior_code()
	if (found_opt_parse != 0) xx = process_prior_cur()
	#
	# Print any RPC info
	#
	if (debug != 0) print "  Read any RPC calls..."
	x = 0
	fil = tmpf "/rpccalls"
	while (getline < fil > 0) {
		++x
		rpc_text = \$0
		#
		# Accum any RPC cpu/elapsed times for this RPC call
		#
		stcount = 0
		stcpu = 0
		stelapsed = 0
		rpccpu = tmpf "/rpccpu/" x
		while (getline < rpccpu > 0) {
			if (NF != 2) {
				print "Unexpected number of columns" \\
					" (" NF ") in rpccpu line" \\
					" for index " x ":"
				print \$0
				continue
			}
			++stcount
			stcpu = stcpu + \$1
			stelapsed = stelapsed + \$2
		}
		close(rpccpu)
		if (x == 1) {
			print "" >> outf
			print "##########################################" \\
				"######################################" >> outf
			print "                         Remote Procedure" \\
				" Call Summary" >> outf
			print "" >> outf
			print "         (The total elapsed time for all RPC" \\
				" EXEC calls is shown in the" >> outf
			print "       ORACLE TIMING ANALYSIS section of this" \\
				" report as \\"RPC EXEC Calls\\")" >> outf
			print "" >> outf
			print "RPC Text:                                    " \\
				"        Execs CPU secs Elapsed secs" >> outf
			print "---------------------------------------------" \\
				"------- ----- -------- ------------" >> outf
		}
		while (length(rpc_text) > 52) {
			print substr(rpc_text, 1, 52) >> outf
			rpc_text = substr(rpc_text, 53)
		}
		printf "%-52s %5d %8.2f %12.2f\n", \\
			rpc_text, stcount, stcpu / 100, stelapsed / 100 >> outf
		#
		# Print any RPC bind variables
		#
		if (debug != 0) print "  Print RPC bind variables..."
		cnt = 0
		rpcbind = tmpf "/rpcbinds/" x
		while (getline < rpcbind > 0) {
			++cnt
			if (cnt <= 100) print \$0 >> outf
		}
		close(rpcbind)
		if (cnt > 0) print "     Total of " cnt " RPC bind variables" \\
			>> outf
	}
	close(fil)
	close(topstmts)
	# Accum time for each event by hash value
	if (debug != 0) print "Sort top stmnts:"
	system("sort " tmpf "/topstmts > " tmpf "/topstmts.tmp")
	system("rm -f " topstmts)
	topstmts_srt = tmpf "/topstmts.tmp"
	prev_event = "@"
	prev_hv = -1
	while (getline < topstmts_srt > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 4) {
			print "Unexpected number of columns (" elem \\
				") in sorted top stmts line #" NR ":"
			print \$0
			continue
		}
		event = substr(arr[1], 1, 50)
		hv = arr[2]
		curno = arr[3]
		ela = arr[4]
		if (debug != 0) print "Read Top Stmnt: " substr(event,1,25) \\
			" : " hv " ela=" ela
		if (prev_event != event) {
			if (prev_event != "@" && grand_tot_ela >= 1) {
				if (debug != 0) print \\
					"  Write top stmnt grand total for " \\
					prev_event ": " grand_tot_ela
				printf "%-50s~%-12s~%18s~%16s~%-16s\n", \\
					prev_event, "0", "0", \\
					"9999999999999999", \\
					grand_tot_ela >> topstmts
			}
			grand_tot_ela = 0
		}
		if (prev_event != event || prev_hv != hv) {
			if (prev_event != "@" && tot_ela >= 1) {
				if (debug != 0) print "  Write top stmnt new" \\
					" event: " prev_event "/" prev_hv \\
					" ela=" ela
				printf "%-50s~%-12s~%-18s~%16s~%-16s\n", \\
					prev_event, prev_hv, curno, \\
					tot_ela, calls >> topstmts
			}
			tot_ela = 0
			calls = 0
			prev_event = event
			prev_hv = hv
		}
		tot_ela = tot_ela + ela
		grand_tot_ela = grand_tot_ela + ela
		++calls
	}
	if (prev_event != "@" && grand_tot_ela >= 1) {
		if (debug != 0) "  Write top stmnt grand total for " prev_event
		printf "%-50s~%-12s~%18s~%16s~%-16s\n", \\
			prev_event, "0", "0", "9999999999999999", \\
			grand_tot_ela >> topstmts
	}
	close(topstmts_srt)
	if (prev_event != event) {
		if (prev_event != "@" && tot_ela >= 1) {
			if (debug != 0) print "  Write top stmnt new event: " \\
				prev_event ": " grand_tot_ela
			printf "%-50s~%-12s~%-18s~%16s~%-16s\n", \\
				prev_event, prev_hv, curno, \\
				tot_ela, calls >> topstmts
		}
	}
	close(topstmts)
	system("rm -f " topstmts_srt)
	if (debug != 0) {
		print "Sort top stmnts again:"
		system("ls -l " topstmts)
	}
	# Sort in ascending order of event, and then descending order of time
	topstmts_srt = tmpf "/topstmts.tmp"
	if (debug != 0) print "Sort top stmnts by event and descending time"
	system("sort -t~ -k 1,1 -k 4,4nr " topstmts " > " topstmts_srt)
	system("rm -f " topstmts)
	if (debug != 0) {
		print "Read sorted top stmnts:"
		system("ls -l " topstmts_srt)
	}
	#
	# Print top 5 statements per event
	#
	if (debug != 0) print "Print top 5 stmnts per event"
	spaces = "                                                         " \\
		"                                                         "
	dashes = "#########################################################" \\
		"#########################################################"
	prev_event = "@"
	while (getline < topstmts_srt > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 5) {
			print "Unexpected number of columns (" elem \\
				") in top stmts line #" NR ":"
			print \$0
			continue
		}
		event = arr[1]
		gsub(/[[:space:]]+$/,"",event)
		hv = arr[2]
		curno = arr[3]
		ela = arr[4]
		calls = arr[5]
		if (debug != 0) print "Read top stmt: " substr(event,1,20) \\
			" hv=" hv " curno=" curno " ela=" ela " calls=" calls
		if (ela == "9999999999999999") {
			if (debug != 0) print "  " substr(event,1,20) \\
				" grand total: " calls
			tot_ela = calls
			if (tot_ela == 0) tot_ela = .1
			continue
		}
		if (prev_event != event) {
			if (prev_event != "@") {
				if (others > 0) {
					pct = int(1000 * other_ela / \\
						prev_tot_ela) / 10
					if (others == 1) {
						othrs = others " other"
					} else {
						othrs = others " others"
					}
					printf \\
					   "%-16s %18s %7.1f%s %14.4f %8d\n", \\
						othrs, " ", pct, \\
						"%", other_ela / 1000000, \\
						other_calls >> outf
				}
				print "---------------- ------------------" \\
					" -------- -------------- --------" \\
					>> outf
				printf "%-16s %18s %7.1f%s %14.4f %8d\n", \\
					"Total", " ", 100, "%", \\
					prev_tot_ela / 1000000, tot_calls \\
					>> outf
				print "" >> outf
			} else {
				print "" >> outf
				print "Top 5 Statements per Event" >> outf
				print "==========================" >> outf
				print "" >> outf
			}
			print substr(spaces, 1, \\
				int((80 - length(substr(event, 1, 50))) / 2)) \\
				substr(event, 1, 50) >> outf
			print substr(spaces, 1, \\
				int((80 - length(substr(event, 1, 50))) / 2)) \\
				substr(dashes, 1, length(substr(event,1,50))) \\
				>> outf
			print "" >> outf
			print "SQL Hash Value               Cursor   % Time" \\
				" Elapsed secs    Calls" >> outf
			print "---------------- ------------------ --------" \\
				" -------------- --------" >> outf
			tot_calls = 0
			prev_event = event
			event_ctr = 0
			others = 0
			other_ela = 0
			other_calls = 0
			prev_tot_ela = tot_ela
		}
		++event_ctr
		if (event_ctr < 6) {
			pct = int(1000 * ela / tot_ela) / 10
			printf "%-16s %18s %7.1f%s %14.4f %8d\n", \\
				hv, curno, pct, "%", ela / 1000000, calls \\
				>> outf
		} else {
			++others
			other_ela = other_ela +  ela
			if (debug != 0) print "Accum " ela \\
				" into other_ela: " other_ela
			other_calls = other_calls + calls
		}
		tot_calls = tot_calls + calls
	}
	close(topstmts_srt)
	system("rm -f " topstmts_srt)
	if (prev_event != "@") {
		if (others > 0) {
			pct = int(1000 * other_ela / prev_tot_ela) / 10
			if (others == 1) {
				othrs = others " other"
			} else {
				othrs = others " others"
			}
			printf "%-16s %18s %7.1f%s %14.4f %8d\n", \\
				othrs, " ", pct, "%", \\
				other_ela / 1000000, other_calls >> outf
		}
		print "---------------- ------------------ --------" \\
			" -------------- --------" >> outf
		printf "%-16s %18s %7.1f%s %14.4f %8d\n", \\
			"Total", " ", 100, "%", \\
			prev_tot_ela / 1000000, tot_calls >> outf
	}
	#
	# Print totals by module
	#
	if (debug == 0) {
		print "Creating report totals..."
	} else {
		print "  Print module totals..."
	}
	fil = tmpf "/modules"
	found = 0
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 10) {
			print "Unexpected number of columns (" elem \\
				") in module totals line #" NR ":"
			print \$0
			continue
		}
		dep = arr[9]
		if (found == 0) {
			print "" >> outf
			print "###################################" \\
				"#################################" \\
				"############" >> outf
			print "" >> outf
			print "                      TOTALS FOR ALL" \\
				" STATEMENTS BY MODULE" >> outf
			print "" >> outf
			print "Module   count      cpu    elapsed" \\
				"       disk      query    current" \\
				"       rows" >> outf
			print "------- ------ -------- ----------" \\
				" ---------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			prev_module = "@"
			tcount = 0
			tcpu = 0
			telapsed = 0
			tdisk = 0
			tquery = 0
			tcurrent = 0
			trows = 0
		}
		module = arr[1]
		if (prev_module != module) {
			if (prev_module != "@") xx = print_prev_module()
			prev_module = module
			stcount = 0
			stcpu = 0
			stelapsed = 0
			stdisk = 0
			stquery = 0
			stcurrent = 0
			strows = 0
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
		}
		++stcount
		stcpu = stcpu + arr[2]
		stelapsed = stelapsed + arr[3]
		stdisk = stdisk + arr[4]
		stquery = stquery + arr[5]
		stcurrent = stcurrent + arr[6]
		strows = strows + arr[7]
	}
	close(fil)
	if (found != 0) {
		xx = print_prev_module()
		print "        ------ -------- ---------- ----------" \\
			" ---------- ---------- ----------" >> outf
		printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
			"total", tcount, tcpu / 100, \\
			telapsed / 100, tdisk, tquery, tcurrent, trows >> outf
	}
	#
	# Print totals by action
	#
	if (debug > 0) {
		print "  Print action summary..."
	}
	fil = tmpf "/actions"
	found = 0
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 10) {
			print "Unexpected number of columns (" elem \\
				") in action totals line #" NR ":"
			print \$0
			continue
		}
		dep = arr[9]
		if (found == 0) {
			print "" >> outf
			print "###################################" \\
				"#################################" \\
				"############" >> outf
			print "" >> outf
			print "                      TOTALS FOR ALL" \\
				" STATEMENTS BY ACTION" >> outf
			print "" >> outf
			print "Action   count      cpu    elapsed" \\
				"       disk      query    current" \\
				"       rows" >> outf
			print "------- ------ -------- ----------" \\
				" ---------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			prev_action = "@"
			tcount = 0
			tcpu = 0
			telapsed = 0
			tdisk = 0
			tquery = 0
			tcurrent = 0
			trows = 0
		}
		action = arr[1]
		if (prev_action != action) {
			if (prev_action != "@") xx = print_prev_action()
			prev_action = action
			stcount = 0
			stcpu = 0
			stelapsed = 0
			stdisk = 0
			stquery = 0
			stcurrent = 0
			strows = 0
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
		}
		++stcount
		stcpu = stcpu + arr[2]
		stelapsed = stelapsed + arr[3]
		stdisk = stdisk + arr[4]
		stquery = stquery + arr[5]
		stcurrent = stcurrent + arr[6]
		strows = strows + arr[7]
	}
	close(fil)
	if (found != 0) {
		xx = print_prev_action()
		print "        ------ -------- ---------- ----------" \\
			" ---------- ---------- ----------" >> outf
		printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
			"total", tcount, tcpu / 100, \\
			telapsed / 100, tdisk, tquery, tcurrent, trows >> outf
	}
	close(filtotcur)
	system("sort " tmpf "/waitstotcur > " tmpf "/waitssrt.tmp")
	system("mv -f " tmpf "/waitssrt.tmp " tmpf "/waitstotcur")
	#
	# Print total Wait time by cursor
	#
	if (debug != 0) print "  Print wait time by cursor totals..."
	found = 0
	prev_cur = "99999"
	prev_nam = "@"
	while (getline < filtotcur > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 3) {
			print "Unexpected number of columns (" elem \\
				") in waits by cursor line #" NR ":"
			print \$0
			continue
		}
		cur = arr[1] ""
		nam = arr[2]
		ela = arr[3]
		if (prev_cur != cur) {
			if (prev_cur != "99999") xx = print_prev_curwait()
			prev_cur = cur
			prev_nam = nam
			namela = 0
		}
		if (prev_nam != nam) {
			xx = print_prev_curwait()
			prev_nam = nam
			namela = 0
		}
		namela = namela + ela
	}
	if (prev_cur != "99999") xx = print_prev_curwait()
	close(filtotcur)
	#
	# Print total Wait time by module/wait event
	#
	if (debug != 0) print "  Print wait time by module totals..."
	found = 0
	print_module = 1
	prev_module = "@"
	prev_nam = "@"
	filtotmod = tmpf "/waitstotmod"
	while (getline < filtotmod > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 5) {
			print "Unexpected number of columns (" elem \\
				") in waits by module line #" NR ":"
			print \$0
			continue
		}
		module = arr[1]
		nam = arr[2]
		p1 = arr[3]
		p2 = arr[4]
		ela = arr[5]
		if (prev_module != module) {
			if (prev_module != "@") xx = print_prev_modwait()
			prev_module = module
			prev_nam = nam
			prev_p1 = p1
			prev_p2 = p2
			namela = 0
			print_module = 1
		}
		if (prev_nam != nam) {
			xx = print_prev_modwait()
			prev_nam = nam
			prev_p1 = p1
			prev_p2 = p2
			namela = 0
		}
		namela = namela + ela
	}
	close(filtotmod)
	if (prev_module != "@") xx = print_prev_modwait()
	#
	# Print total Wait time by action/wait event
	#
	if (debug != 0) print "  Print wait time by action totals..."
	found = 0
	prev_action = "@"
	while (getline < filtotact > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 5) {
			print "Unexpected number of columns (" elem \\
				") in waits by action line #" NR ":"
			print \$0
			continue
		}
		action = arr[1]
		nam = arr[2]
		p1 = arr[3]
		p2 = arr[4]
		ela = arr[5]
		if (prev_action != action) {
			if (prev_action != "@") xx = print_prev_actwait()
			prev_action = action
			prev_nam = nam
			prev_p1 = p1
			prev_p2 = p2
			namela = 0
			print_action = 1
		}
		if (prev_nam != nam) {
			xx = print_prev_actwait()
			prev_nam = nam
			prev_p1 = p1
			prev_p2 = p2
			namela = 0
		}
		namela = namela + ela
	}
	if (prev_action != "@") xx = print_prev_actwait()
	#
	# Print non-recursive totals by command type for user
	#
	if (debug != 0) print "  Print non-recursive totals..."
	fil = tmpf "/cmdtypes"
	found = 0
	while (getline < fil > 0) {
		if (NF != 10) continue
		dep = \$9
		if (dep != 0) continue		# Skip if recursive
		if (found == 0) {
			print "" >> outf
			print "###################################" \\
				"#################################" \\
				"############" >> outf
			print "" >> outf
			print "       TOTALS FOR ALL NON-RECURSIVE" \\
				" STATEMENTS BY COMMAND TYPE FOR" \\
				" USERS" >> outf
			print "" >> outf
			print "cmdtyp   count      cpu    elapsed" \\
				"       disk      query    current" \\
				"       rows" >> outf
			print "------- ------ -------- ----------" \\
				" ---------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			prev_cmd = "@"
			tcount = 0
			tcpu = 0
			telapsed = 0
			tdisk = 0
			tquery = 0
			tcurrent = 0
			trows = 0
		}
		cmd = \$1
		if (prev_cmd != cmd) {
			if (prev_cmd != "@") {
				xx = print_prev_command_type()
			}
			prev_cmd = cmd
			stcount = 0
			stcpu = 0
			stelapsed = 0
			stdisk = 0
			stquery = 0
			stcurrent = 0
			strows = 0
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
		}
		++stcount
		stcpu = stcpu + \$2
		stelapsed = stelapsed + \$3
		stdisk = stdisk + \$4
		stquery = stquery + \$5
		stcurrent = stcurrent + \$6
		strows = strows + \$7
	}
	close(fil)
	if (found != 0) {
		xx = print_prev_command_type()
		print "------- ------ -------- ---------- ----------" \\
			" ---------- ---------- ----------" >> outf
		printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
			"total", tcount, tcpu / 100, \\
			telapsed / 100, tdisk, tquery, tcurrent, trows >> outf
	}
	#
	# Print recursive totals by command type for user
	#
	if (debug != 0) print "  Print recursive totals..."
	fil = tmpf "/cmdtypes"
	found = 0
	while (getline < fil > 0) {
		if (NF != 10) continue
		uid = \$8
		dep = \$9
		if (dep == 0) continue		# Skip if non-recursive
		if (uid == 0) continue		# Skip if SYS user
		if (found == 0) {
			print "" >> outf
			print "###################################" \\
				"#################################" \\
				"############" >> outf
			print "" >> outf
			print "         TOTALS FOR ALL RECURSIVE" \\
				" STATEMENTS BY COMMAND TYPE FOR" \\
				" USERS" >> outf
			print "" >> outf
			print "cmdtyp   count      cpu    elapsed" \\
				"       disk      query    current" \\
				"       rows" >> outf
			print "------- ------ -------- ----------" \\
				" ---------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			prev_cmd = "@"
			tcount = 0
			tcpu = 0
			telapsed = 0
			tdisk = 0
			tquery = 0
			tcurrent = 0
			trows = 0
		}
		cmd = \$1
		if (prev_cmd != cmd) {
			if (prev_cmd != "@") {
				xx = print_prev_command_type()
			}
			prev_cmd = cmd
			stcount = 0
			stcpu = 0
			stelapsed = 0
			stdisk = 0
			stquery = 0
			stcurrent = 0
			strows = 0
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
		}
		++stcount
		stcpu = stcpu + \$2
		stelapsed = stelapsed + \$3
		stdisk = stdisk + \$4
		stquery = stquery + \$5
		stcurrent = stcurrent + \$6
		strows = strows + \$7
	}
	close(fil)
	if (found != 0) {
		xx = print_prev_command_type()
		print "------- ------ -------- ---------- ----------" \\
			" ---------- ---------- ----------" >> outf
		printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
			"total", tcount, tcpu / 100, \\
			telapsed / 100, tdisk, tquery, tcurrent, trows >> outf
	}
	#
	# Print recursive totals by command type for SYS
	#
	if (debug != 0) print "  Print recursive sys totals..."
	fil = tmpf "/cmdtypes"
	found = 0
	while (getline < fil > 0) {
		if (NF != 10) continue
		uid = \$8
		dep = \$9
		if (dep == 0) continue		# Skip if non-recursive
		if (uid != 0) continue		# Skip if non-SYS user
		if (found == 0) {
			print "" >> outf
			print "###################################" \\
				"#################################" \\
				"############" >> outf
			print "" >> outf
			print "          TOTALS FOR ALL RECURSIVE" \\
				" STATEMENTS BY COMMAND TYPE FOR" \\
				" SYS" >> outf
			print "" >> outf
			print "cmdtyp   count      cpu    elapsed" \\
				"       disk      query    current" \\
				"       rows" >> outf
			print "------- ------ -------- ----------" \\
				" ---------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			prev_cmd = "@"
			tcount = 0
			tcpu = 0
			telapsed = 0
			tdisk = 0
			tquery = 0
			tcurrent = 0
			trows = 0
		}
		cmd = \$1
		if (prev_cmd != cmd) {
			if (prev_cmd != "@") {
				xx = print_prev_command_type()
			}
			prev_cmd = cmd
			stcount = 0
			stcpu = 0
			stelapsed = 0
			stdisk = 0
			stquery = 0
			stcurrent = 0
			strows = 0
			stmissparse = 0
			stmissexec = 0
			stmissfetch = 0
		}
		++stcount
		stcpu = stcpu + \$2
		stelapsed = stelapsed + \$3
		stdisk = stdisk + \$4
		stquery = stquery + \$5
		stcurrent = stcurrent + \$6
		strows = strows + \$7
	}
	close(fil)
	if (found != 0) {
		xx = print_prev_command_type()
		print "------- ------ -------- ---------- ----------" \\
			" ---------- ---------- ----------" >> outf
		printf "%-8s%6d %8.2f %10.2f %10d %10d %10d %10d\n", \\
			"total", tcount, tcpu / 100, \\
			telapsed / 100, tdisk, tquery, tcurrent, trows >> outf
	}
	totcounts = 0
	totcpus = 0
	totelapseds = 0
	totdisks = 0
	totquerys = 0
	totcurrents = 0
	totrowss = 0
	totunaccs = 0
	h = 0
	x9 = 0
	while (x9 < totn) {
		++x9
		if (h == 0) {
			print "" >> outf
			print "############################################" \\
				"####################################" >> outf
			print "" >> outf
			print "                OVERALL TOTALS FOR ALL" \\
				" NON-RECURSIVE STATEMENTS" >> outf
			print "" >> outf
			print "call         count      cpu    elapsed" \\
				"      disk     query   current      rows" \\
				>> outf
			print "----------- ------ -------- ----------" \\
				" --------- --------- --------- ---------" \\
				>> outf
			h = 1
		}
		printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
			opnames[x9], otcounts[x9], otcpus[x9] / 100, \\
			otelapseds[x9] / 100, otdisks[x9], otquerys[x9], \\
			otcurrents[x9], otrowss[x9] >> outf
		totcounts = totcounts + otcounts[x9]
		totcpus = totcpus + otcpus[x9]
		totelapseds = totelapseds + otelapseds[x9]
		totdisks = totdisks + otdisks[x9]
		totquerys = totquerys + otquerys[x9]
		totcurrents = totcurrents + otcurrents[x9]
		totrowss = totrowss + otrowss[x9]
		totunaccs = totunaccs + otunaccs[x9]
	}
	if (h == 1) {
		print "----------- ------ -------- ----------" \\
			" --------- --------- --------- ---------" >> outf
		printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
			"total", totcounts, totcpus / 100, totelapseds / 100, \\
			totdisks, totquerys, totcurrents, totrowss >> outf
		if (totunaccs != 0) {
			print " " >> outf
			printf "  Unaccounted-for time: %10.2f\n", \\
				totunaccs / 100000 >> outf
			print " " >> outf
			print "  Large amounts of unaccounted-for time can" \\
				" indicate excessive context" >> outf
			print "  switching, paging, swapping, CPU run" \\
				" queues, or uninstrumented Oracle code." \\
				>> outf
			print " " >> outf
		}
	}
	h = 0
	totcounts = 0
	totcpus = 0
	totelapsedsr = 0
	totdisks = 0
	totquerys = 0
	totcurrents = 0
	totrowss = 0
	totunaccs = 0
	x9 = 0
	while (x9 < totnr) {
		++x9
		if (h == 0) {
			print "" >> outf
			print "###########################################" \\
				"#####################################" >> outf
			print "" >> outf
			print "                  OVERALL TOTALS FOR ALL" \\
				" RECURSIVE STATEMENTS" >> outf
			print "" >> outf
			print "call         count      cpu    elapsed" \\
				"      disk     query   current      rows" \\
				>> outf
			print "----------- ------ -------- ----------" \\
				" --------- --------- --------- ---------" \\
				>> outf
			h = 1
		}
		printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
			ropnames[x9], rotcounts[x9], rotcpus[x9] / 100, \\
			rotelapseds[x9] / 100, rotdisks[x9], \\
			rotquerys[x9], rotcurrents[x9], rotrowss[x9] >> outf
		totcounts = totcounts + rotcounts[x9]
		totcpus = totcpus + rotcpus[x9]
		totelapsedsr = totelapsedsr + rotelapseds[x9]
		totdisks = totdisks + rotdisks[x9]
		totquerys = totquerys + rotquerys[x9]
		totcurrents = totcurrents + rotcurrents[x9]
		totrowss = totrowss + rotrowss[x9]
		totunaccs = totunaccs + rotunaccs[x9]
	}
	if (h == 1) {
		print "----------- ------ -------- ----------" \\
			" --------- --------- --------- ---------" >> outf
		printf "%-12s%6d %8.2f %10.2f %9d %9d %9d %9d\n", \\
			"total", totcounts, totcpus / 100, \\
			totelapsedsr / 100, totdisks, totquerys, \\
			totcurrents, totrowss >> outf
		if (totunaccs != 0) {
			print " " >> outf
			printf "  Unaccounted-for time: %10.2f\n", \\
				totunaccs / 100000 >> outf
			print " " >> outf
			print "  Large amounts of unaccounted-for time can" \\
				" indicate excessive context" >> outf
			print "  switching, paging, swapping, CPU run" \\
				" queues, or uninstrumented Oracle code." \\
				>> outf
		}
	}
	#
	# Print summary by descending elapsed time
	#
	close(filelap)
	if (debug != 0) print "  Print elapsed summary totals..."
	grtelapsed = 0
	system("sort -n -r " tmpf "/elap > " tmpf "/srt.tmp")
	system("mv -f " tmpf "/srt.tmp " tmpf "/elap")
	found = 0
	while (getline < filelap > 0) {
		if (NF != 9) {
			print "Unexpected number of columns (" NF \\
				") in elap line for hash value " hv ":"
			print \$0
			continue
		}
		if (int(100 * \$5 / 100) == 0 && \\
			int(100 * \$1 / 100) == 0 && \\
			int(100 * \$6 / 100) == 0) continue
		if (found == 0) {
			print "" >> outf
			print "#####################################" \\
				"###################################" \\
				"########" >> outf
			print "" >> outf
			print "       SUMMARY OF TOTAL CPU TIME," \\
				" ELAPSED TIME, WAITS, AND I/O PER" \\
				" CURSOR" >> outf
			print "                       (SORTED BY" \\
				" DESCENDING ELAPSED TIME)" >> outf
			print "" >> outf
			print " Cur User  Total     CPU     Elapsed" \\
				"      Wait   Physical Consistent" \\
				"    Current" >> outf
			print " ID#  ID   Calls     Time      Time " \\
				"      Time     Reads     Reads  " \\
				"     Reads" >> outf
			print "---- ---- ------ -------- ----------" \\
				" --------- ---------- ----------" \\
				" ----------" >> outf
			found = 1
			telapsed = 0
			tcpu = 0
		}
		printf \\
		    "%4d %4s %6d %8.2f %10.2f %9.2f %10d %10d %10d\n", \\
			\$2, \$3, \$4, \$5 / 100, \$1 / 100, \\
			\$6 / 100, \$7, \$8, \$9 >> outf
		tcpu = tcpu + \$5
		telapsed = telapsed + \$1
	}
	close(fil)
	if (found != 0) {
		print "               ---------- ----------" >> outf
		printf "               %10.2f %10.2f %-s\n",
			tcpu / 100, telapsed / 100, \\
			"Total elapsed time for all cursors" >> outf
		grtcpu = int(tcpu)
		grtelapsed = int(telapsed)
	}
	#
	# Print summary by descending fetch time
	#
	close(filfetch)
	#if (debug != 0) print "  Print fetch time totals..."
	#system("sort -n -r " tmpf "/fetch > " tmpf "/srt.tmp")
	#system("mv -f " tmpf "/srt.tmp " tmpf "/fetch")
	#found = 0
	#while (getline < filfetch > 0) {
	#	if (NF != 9) {
	#		print "Unexpected number of columns (" NF \\
	#			") in fetch line for hash value " hv ":"
	#		print \$0
	#		continue
	#	}
	#	if (int(100 * \$5 / 100) == 0 && \\
	#		int(100 * \$6 / 100) == 0 && \\
	#		int(100 * \$1 / 100) == 0) continue
	#	if (found == 0) {
	#		print "" >> outf
	#		print "#####################################" \\
	#			"###################################" \\
	#			"########" >> outf
	#		print "" >> outf
	#		print "       SUMMARY OF TOTAL CPU TIME," \\
	#			" ELAPSED TIME, AND FETCH TIME PER" \\
	#			" CURSOR" >> outf
	#		print "                        (SORTED BY" \\
	#			" DESCENDING FETCH TIME)" >> outf
	#		print "" >> outf
	#		print " Cur User  Total     CPU     Elapsed" \\
	#			"     Fetch   Physical Consistent" \\
	#			"    Current" >> outf
	#		print " ID#  ID   Calls     Time      Time " \\
	#			"      Time     Reads     Reads  " \\
	#			"     Reads" >> outf
	#		print "---- ---- ------ -------- ----------" \\
	#			" --------- ---------- ----------" \\
	#			" ----------" >> outf
	#		found = 1
	#		tfetch = 0
	#	}
	#	printf \\
	#	    "%4d %4s %6d %8.2f %10.2f %9.2f %10d %10d %10d\n", \\
	#		\$2, \$3, \$4, \$5 / 100, \$6 / 100, \\
	#		\$1 / 100, \$7, \$8, \$9 >> outf
	#	tfetch = tfetch + \$1
	#}
	#close(filfetch)
	#if (found != 0) {
	#	print "                                    ----------" >> outf
	#	printf "                                    %10.2f %-s\n",
	#		tfetch / 100, "Total fetch time for all cursors" >> outf
	#}
	filblk = 0
	#
	# Print total Wait times for all statements for users
	#
	if (debug != 0) print "  Print wait time totals..."
	fil = tmpf "/waitst"
	totwait = 0
	prev_nam = "@"
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 4) {
			print "Unexpected number of columns (" elem \\
				") in total waits line #" NR ":"
			print \$0
			continue
		}
		nam = arr[1]
		ela = arr[4]
		if (prev_nam != nam) {
			if (prev_nam != "@") {
				if (totela >= 1) totwait = totwait + totela
			}
			prev_nam = nam
			totela = 0
		}
		totela = totela + ela
	}
	close(fil)
	if (prev_nam != "@") {
		if (totela >= 1) totwait = totwait + totela
	}
	fil = tmpf "/waitst"
	found = 0
	wait_head = 1
	gtotwts = 0
	gtotela = 0
	prev_nam = "@"
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 4) continue
		nam = arr[1]
		p1 = arr[2]
		p2 = arr[3]
		ela = arr[4]
		if (prev_nam != nam) {
			if (prev_nam != "@") {
				print_nam = prev_nam
				xx = print_prev_wait()
			}
			prev_nam = nam
			totela = 0
			totwts = 0
		}
		++totwts
		totela = totela + ela
	}
	close(fil)
	if (prev_nam != "@") {
		print_nam = prev_nam
		xx = print_prev_wait()
	}
	if (found == 1) {
		print "--------------------------------------------------" \\
			" -------- ---- ------ -------" >> outf
		printf "%-50s %8.2f %3d%s %6d %7.2f\n", "Total Wait Events:", \\
			gtotela / 100, 100, "%", gtotwts, \\
			gtotela / (gtotwts * 100 + .0000001) >> outf
	}
	if (filblk != 0) {
		print "" >> outf
		print "To determine which segment is causing a" \\
			" specific wait, issue the following" >> outf
		print "query:" >> outf
		print "   SELECT OWNER, SEGMENT_NAME FROM DBA_EXTENTS" >> outf
		print "   WHERE FILE_ID = <File-ID-from-above> AND" >> outf
		print "   <Block-Number-from-above> BETWEEN BLOCK_ID" \\
			" AND BLOCK_ID+BLOCKS-1;" >> outf
	}
	#
	# Print grand total Wait times
	#
	if (debug != 0) print "  Print grand total waits..."
	fil = tmpf "/waitst"
	totwait = 0
	prev_nam = "@"
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 6) continue
		nam = arr[1]
		# Skip events issued between database calls
		if (nam == "smon timer" || \\
			nam == "pmon timer" || \\
			nam == "rdbms ipc message" || \\
			nam == "pipe get" || \\
			nam == "client message" || \\
			nam == "single-task message" || \\
			nam == "SQL*Net message from client" || \\
			nam == "SQL*Net more data from client" || \\
			nam == "dispatcher timer" || \\
			nam == "virtual circuit status" || \\
			nam == "lock manager wait for remote message" || \\
			nam == "wakeup time manager" || \\
			nam == "PX Deq: Execute Reply" || \\
			nam == "PX Deq: Execution Message" || \\
			nam == "PX Deq: Table Q Normal" || \\
			nam == "PX Idle Wait" || \\
			nam == "slave wait" || \\
			nam == "i/o slave wait" || \\
			nam == "jobq slave wait") continue
		ela = arr[4]
		if (prev_nam != nam) {
			if (prev_nam != "@") {
				if (totela >= 1) totwait = totwait + totela
			}
			prev_nam = nam
			totela = 0
		}
		totela = totela + ela
	}
	close(fil)
	if (prev_nam != "@") {
		if (totela >= 1) totwait = totwait + totela
	}
	fil = tmpf "/waitst"
	found = 0
	found_scattered = 0
	wait_head = 2
	gtotwts = 0
	gtotela = 0
	gridle = 0
	grscan = 0
	prev_nam = "@"
	non_idle_gtotela = 0
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 6) continue
		nam = arr[1]
		if (nam == "smon timer" || \\
			nam == "pmon timer" || \\
			nam == "rdbms ipc message" || \\
			nam == "pipe get" || \\
			nam == "client message" || \\
			nam == "single-task message" || \\
			nam == "SQL*Net message from client" || \\
			nam == "SQL*Net more data from client" || \\
			nam == "dispatcher timer" || \\
			nam == "virtual circuit status" || \\
			nam == "lock manager wait for remote message" || \\
			nam == "wakeup time manager" || \\
			nam == "PX Deq: Execute Reply" || \\
			nam == "PX Deq: Execution Message" || \\
			nam == "PX Deq: Table Q Normal" || \\
			nam == "PX Idle Wait" || \\
			nam == "slave wait" || \\
			nam == "i/o slave wait" || \\
			nam == "jobq slave wait") {
			gridle = gridle + arr[4]
			continue
		}
		if (substr(nam,1,12) == "db file scat") grscan = grscan + arr[4]
		p1 = arr[2]
		p2 = arr[3]
		ela = arr[4]
		if (prev_nam != nam) {
			if (substr(nam,1,12) == "db file scat") {
				found_scattered = found_scattered + 1
			}
			if (prev_nam != "@") {
				print_nam = prev_nam
				xx = print_prev_wait()
			}
			prev_nam = nam
			totela = 0
			totwts = 0
		}
		++totwts
		totela = totela + ela
	}
	close(fil)
	if (prev_nam != "@") {
		print_nam = prev_nam
		xx = print_prev_wait()
	}
	if (found == 1) {
		print "--------------------------------------------------" \\
			" -------- ---- ------ -------" >> outf
		printf "%-50s %8.2f %3d%s %6d %7.2f\n", \\
			"Grand Total Non-Idle Wait Events:", \\
			gtotela / 100, 100, "%", gtotwts, \\
			gtotela / (gtotwts * 100 + .0000001) >> outf
		non_idle_gtotela = gtotela
	}
	if (found_scattered > 1) {
		print "" >> outf
		print "Note:  For db file scattered read, the number of" \\
			" blocks read may be less" >> outf
		print "       than db_file_multiblock_read_count, if Oracle" \\
			" is able to locate the" >> outf
		print "       block it needs from cache and therefore does" \\
			" not need to read in" >> outf
		print "       the block(s) from disk." >> outf
	}
	# Calc lines for Oracle Timing Analysis
	n = 0
	totwait = 0
	# Store any CPU usage in arrays
	if (cpu_timing_parse_cnt > 0) {
		if (cpu_timing_parse >= 1) {
			++n
			ta_nams[n] = "CPU PARSE Calls"
			ta_ela[n] = cpu_timing_parse
			ta_calls[n] = cpu_timing_parse_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_parse
		}
	}
	if (cpu_timing_exec_cnt > 0) {
		if (cpu_timing_exec >= 1) {
			++n
			ta_nams[n] = "CPU EXEC Calls"
			ta_ela[n] = cpu_timing_exec
			ta_calls[n] = cpu_timing_exec_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_exec
		}
	}
	if (cpu_timing_fetch_cnt > 0) {
		if (cpu_timing_fetch >= 1) {
			++n
			ta_nams[n] = "CPU FETCH Calls"
			ta_ela[n] = cpu_timing_fetch
			ta_calls[n] = cpu_timing_fetch_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_fetch
		}
	}
	if (cpu_timing_unmap_cnt > 0) {
		if (cpu_timing_unmap >= 1) {
			++n
			ta_nams[n] = "CPU UNMAP Calls"
			ta_ela[n] = cpu_timing_unmap
			ta_calls[n] = cpu_timing_unmap_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_unmap
		}
	}
	if (cpu_timing_sort_cnt > 0) {
		if (cpu_timing_sort >= 1) {
			++n
			ta_nams[n] = "CPU SORT UNMAP Calls"
			ta_ela[n] = cpu_timing_sort
			ta_calls[n] = cpu_timing_sort_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_sort
		}
	}
	if (cpu_timing_rpcexec_cnt > 0) {
		if (cpu_timing_rpcexec >= 1) {
			++n
			ta_nams[n] = "RPC EXEC Calls"
			ta_ela[n] = cpu_timing_rpcexec
			ta_calls[n] = cpu_timing_rpcexec_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_rpcexec
		}
	}
	if (cpu_timing_close_cnt > 0) {
		if (cpu_timing_close >= 1) {
			++n
			ta_nams[n] = "CPU CLOSE Calls"
			ta_ela[n] = cpu_timing_close
			ta_calls[n] = cpu_timing_close_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_close
		}
	}
	if (cpu_timing_lobread_cnt > 0) {
		if (cpu_timing_lobread >= 1) {
			++n
			ta_nams[n] = "LOBREAD Calls"
			ta_ela[n] = cpu_timing_lobread
			ta_calls[n] = cpu_timing_lobread_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobread
		}
	}
	if (cpu_timing_lobgetlen_cnt > 0) {
		if (cpu_timing_lobgetlen >= 1) {
			++n
			ta_nams[n] = "LOBGETLEN Calls"
			ta_ela[n] = cpu_timing_lobgetlen
			ta_calls[n] = cpu_timing_lobgetlen_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobgetlen
		}
	}
	if (cpu_timing_lobpgsize_cnt > 0) {
		if (cpu_timing_lobpgsize >= 1) {
			++n
			ta_nams[n] = "LOBPGSIZE Calls"
			ta_ela[n] = cpu_timing_lobpgsize
			ta_calls[n] = cpu_timing_lobpgsize_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobpgsize
		}
	}
	if (cpu_timing_lobwrite_cnt > 0) {
		if (cpu_timing_lobwrite >= 1) {
			++n
			ta_nams[n] = "LOBWRITE Calls"
			ta_ela[n] = cpu_timing_lobwrite
			ta_calls[n] = cpu_timing_lobwrite_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobwrite
		}
	}
	if (cpu_timing_lobappend_cnt > 0) {
		if (cpu_timing_lobappend >= 1) {
			++n
			ta_nams[n] = "LOBAPPEND Calls"
			ta_ela[n] = cpu_timing_lobappend
			ta_calls[n] = cpu_timing_lobappend_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobappend
		}
	}
	if (cpu_timing_lobarrread_cnt > 0) {
		if (cpu_timing_lobarrread >= 1) {
			++n
			ta_nams[n] = "LOBARRREAD Calls"
			ta_ela[n] = cpu_timing_lobarrread
			ta_calls[n] = cpu_timing_lobarrread_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobarrread
		}
	}
	if (cpu_timing_lobarrtmpfre_cnt > 0) {
		if (cpu_timing_lobarrtmpfre >= 1) {
			++n
			ta_nams[n] = "LOBARRTMPFRE Calls"
			ta_ela[n] = cpu_timing_lobarrtmpfre
			ta_calls[n] = cpu_timing_lobarrtmpfre_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobarrtmpfre
		}
	}
	if (cpu_timing_lobarrwrite_cnt > 0) {
		if (cpu_timing_lobarrwrite >= 1) {
			++n
			ta_nams[n] = "LOBARRWRITE Calls"
			ta_ela[n] = cpu_timing_lobarrwrite
			ta_calls[n] = cpu_timing_lobarrwrite_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobarrwrite
		}
	}
	if (cpu_timing_lobtmpfre_cnt > 0) {
		if (cpu_timing_lobtmpfre >= 1) {
			++n
			ta_nams[n] = "LOBTMPFRE Calls"
			ta_ela[n] = cpu_timing_lobtmpfre
			ta_calls[n] = cpu_timing_lobtmpfre_cnt
			ta_flg[n] = 0
			totwait = totwait + cpu_timing_lobtmpfre
		}
	}
	# Store any timing gap error in arrays
	if (gap_cnt > 0) {
		if (gap_time >= 1) {
			++n
			ta_nams[n] = "Timing Gap Error"
			ta_ela[n] = gap_time
			ta_calls[n] = gap_cnt
			ta_flg[n] = 0
			totwait = totwait + gap_time
		}
	}
	# Store any unaccounted-for time in arrays
	if (unacc_cnt > 0) {
		if (unacc_total >= 1) {
			++n
			ta_nams[n] = "Unaccounted-for time"
			ta_ela[n] = unacc_total / 1000
			ta_calls[n] = unacc_cnt
			ta_flg[n] = 0
			totwait = totwait + unacc_total / 1000
		}
	}
	# Store all wait info in arrays, and accum total elapsed times
	fil = tmpf "/waitst"
	prev_nam = "@"
	while (getline < fil > 0) {
		elem = split(\$0, arr, "~")
		if (elem != 4) {
			print "Unexpected number of columns (" elem \\
				") in total waits line #" NR ":"
			print \$0
			continue
		}
		nam = arr[1]
		if (nam == "smon timer" || \\
			nam == "pmon timer" || \\
			nam == "rdbms ipc message" || \\
			nam == "pipe get" || \\
			nam == "client message" || \\
			nam == "single-task message" || \\
			nam == "dispatcher timer" || \\
			nam == "virtual circuit status" || \\
			nam == "lock manager wait for remote message" || \\
			nam == "wakeup time manager" || \\
			nam == "slave wait" || \\
			nam == "i/o slave wait" || \\
			nam == "jobq slave wait") continue
		p1 = arr[2]
		p2 = arr[3]
		ela = arr[4]
		if (prev_nam != nam) {
			if (prev_nam != "@") {
				if (totwts > 0) {
					if (totela >= 1) {
						++n
						ta_nams[n] = prev_nam
						ta_ela[n] = totela
						ta_calls[n] = totwts
						ta_flg[n] = 0
						totwait = totwait + totela
					}
				}
			}
			prev_nam = nam
			totela = 0
			totwts = 0
		}
		++totwts
		totela = totela + ela
	}
	close(fil)
	if (prev_nam != "@") {
		if (totwts > 0) {
			if (totela >= 1) {
				++n
				ta_nams[n] = prev_nam
				ta_ela[n] = totela
				ta_calls[n] = totwts
				ta_flg[n] = 0
				totwait = totwait + totela
			}
		}
	}
	# Print grand total timings, sorted by descending elapsed time
	found = 0
	wait_head = 3
	gtotwts = 0
	gtotela = 0
	print_gap_desc = 0
	print_unacc_desc = 0
	i = 0
	while (i < n) {
		++i
		greatest_time = 0
		k = 0
		j = 0
		while (j < n) {
			++j
			if (ta_ela[j] > greatest_time && ta_flg[j] == 0) {
				greatest_time = ta_ela[j]
				k = j
			}
		}
		print_nam = ta_nams[k]
		totela = ta_ela[k]
		totwts = ta_calls[k]
		xx = print_prev_wait()
		ta_flg[k] = 1
		# See if > 10% Timing Gap Error
		if (print_nam == "Timing Gap Error" && 20 * totela > totwait) {
			print_gap_desc = 1
		}
		if (print_nam == "unaccounted-for time" && \\
			10 * totela > totwait) {
			print_unacc_desc = 1
		}
	}
	if (found == 1) {
		print "--------------------------------------------------" \\
			" -------- ---- ------ -------" >> outf
		printf "%-50s %8.2f %3d%s %6d %7.2f\n", \\
			"Total Oracle Timings:", \\
			gtotela / 100, 100, "%", gtotwts, \\
			gtotela / (gtotwts * 100 + .0000001) >> outf
		print "" >> outf
		print "(Note that these timings may differ from the" \\
			" following grand totals, due to" >> outf
		print " overlapping wall clock time for" \\
			" simultaneously-executed processes, as well as" >> outf
		print " omitted RPC times.)" >> outf
	}
	if (print_unacc_desc != 0) {
		print "" >> outf
		print "  Unaccounted-for time is any remaining time" \\
			" after subtracting wait time" >> outf
		print "  and cpu time from total elapsed time." >> outf
		print "  Large amounts of unaccounted-for time can" \\
			" indicate excessive context" >> outf
		print "  switching, paging, swapping, CPU run" \\
			" queues, or uninstrumented Oracle code." >> outf
	}
	if (print_gap_desc != 0) {
		print "" >> outf
		print "A significant portion of the total elapsed time is" \\
			" due to Timing Gap" >> outf
		print "Error.  This measurement accumulates the differences" \\
			" in the trace file's" >> outf
		print "timing values when there is an unexplained increase" \\
			" of time.  When Timing" >> outf
		print "Gap Error time is a large amount of the total" \\
			" elapsed time, this usually" >> outf
		print "indicates that a process has spent a significant" \\
			" amount of time in a" >> outf
		print "preempted state.  The operating system's scheduler" \\
			" will preempt a process" >> outf
		print "if there is contention for the CPU's run queue." \\
			"  The best way to reduce" >> outf
		print "this time is to reduce the demand for the CPUs," \\
			" typically by optimizing" >> outf
		print "the application code to reduce the number of I/O" \\
			" and/or parsing operations." >> outf
		print "" >> outf
		print "Note that excessive parsing will show up in this" \\
			" report as \"CPU PARSE Calls\"." >> outf
		print "Programs which parse too much will typically have a" \\
			" CPU PARSE Calls" >> outf
		print "value near the value of CPU EXEC Calls." >> outf
	}
	post_wait = 0
	fil = tmpf "/waitsela"
	while (getline < fil > 0) {
		post_wait = post_wait + \$0
	}
	close(fil)
	if (post_wait >= 1) {
		print "" >> outf
		printf "%-50s %8.2f\n", \\
			"Total Wait Time without a matching cursor:", \\
			post_wait / 100 >> outf
	}
	print "" >> outf
	print "###################################################" \\
		"#############################" >> outf
	if (first_time == 0) {
		elapsed_time = 0
	} else {
		elapsed_time = int(100 * grand_elapsed / 100)
	}
	if (debug != 0) print "Grand total: elapsed_time = " elapsed_time
	print "" >> outf
	if (elapsed_time == 0) {
		printf "%s  %12.2f\n", \\
			"GRAND TOTAL SECS:", elapsed_time / 100 >> outf
	} else {
		print "                   Elapsed Wall  Elapsed         " \\
			" Non-Idle     Idle    Table" >> outf
		print "                    Clock Time    Time   CPU Time" \\
			"   Waits     Waits    Scans" >> outf
		print "                   ------------ -------- --------" \\
			" -------- -------- --------" >> outf
		if (gridle > non_idle_gtotela) gridle = non_idle_gtotela
		printf "%s  %12.2f %8.2f %8.2f %8.2f %8.2f %8.2f\n", \\
			"GRAND TOTAL SECS:", \\
			elapsed_time / 100, \\
			int(grtelapsed) / 100, \\
			int(grtcpu) / 100, \\
			int(non_idle_gtotela - gridle) / 100, \\
			int(gridle) / 100, \\
			int(grscan) / 100 >> outf
		printf "%s %3d%s %3d%s %3d%s %3d%s %3d%s\n", \\
			"PCT OF WALL CLOCK:                 ", \\
			int((10000 * grtelapsed) / (100 * elapsed_time)), \\
			"%    ", \\
			int((10000 * grtcpu) / (100 * elapsed_time)), \\
			"%    ", \\
			int((10000 * (non_idle_gtotela - gridle)) / \\
			(100 * elapsed_time)), \\
			"%    ", \\
			int((10000 * gridle) / (100 * elapsed_time)), \\
			"%    ", \\
			int((10000 * grscan) / (100 * elapsed_time)), \\
			"%" >> outf
	}
	fil = tmpf "/truncated"
	if (getline < fil > 0) {
		if (\$0 == 1) {
			print "" >> outf
			print "WARNING:  THIS DUMP FILE HAS BEEN TRUNCATED!" \\
				>> outf
		}
	} else {
		print "Error while trying to read truncated"
	}
	close(fil)
	fil = tmpf "/duplheader"
	x = 0
	if (getline < fil > 0) {
		if (x == 0) {
			print "" >> outf
			print "*** Warning: Multiple trace file headings" \\
				" are in the trace file!" >> outf
			print "" >> outf
			x = 1
		}
		print "             An extra trace header starts on" \\
			" trace line " \$0 >> outf
	}
	close(fil)
	close(filelap)
	close(filtotact)
	if (debug != 0) print "DONE..."
}
EOF
echo "Processing cursors..."
cat $tmpf/init | $cmd -f trace_report.awk outf=$outf tmpf="$tmpf" debug="$debug"
rm -f trace_report.awk
ls -l $outf
if [ "$debug" = "1" ]
then
	echo "Retaining $tmpf for debugging..."
else
	rm -Rf $tmpf
	echo ""
fi
trap - QUIT INT KILL TERM
