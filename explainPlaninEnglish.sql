SELECT CASE operation
    WHEN 'SELECT'                       THEN 'Rows were returned by the remote SELECT statement.'
    WHEN 'SELECT STATEMENT'             THEN
        CASE options
            WHEN 'REMOTE' THEN 'Rows were returned by the remote SELECT statement.'
            ELSE 'Rows were returned by the SELECT statement.'
        END
    WHEN 'TABLE ACCESS'                 THEN
        CASE options
            WHEN 'BY GLOBAL INDEX ROWID'    THEN 'Rows from table ' || object_name || ' were accessed using ROWID got from a global (cross-partition) index.'
            WHEN 'BY INDEX ROWID'           THEN 'Rows from table ' || object_name || ' were accessed using ROWID got from an index.'
            WHEN 'BY INDEX ROWID BATCHED'   THEN 'Rows from table ' || object_name || ' were accessed by a bunch of ROWID from the index.'
            WHEN 'BY LOCAL INDEX ROWID'     THEN 'Rows from table ' || object_name || ' were accessed using ROWID got from a local (single-partition) index.'
            WHEN 'BY ROWID'                 THEN 'Accesses rows in table ' || object_name || ' based on ROWIDs.'
            WHEN 'BY ROWID RANGE'           THEN 'Rows in table ' || object_name || ' matching a range of ROWIDs were processed.'
            WHEN 'BY USER ROWID'            THEN 'Rows in table' || object_name || ' matching a ROWID provided by the user (e.g., not from an index) were accessed.' -- Check user
            WHEN
            'CLUSTER'                  THEN 'Some rows in the clustered table ' || object_name || ' are read, using the cluster index.'
            WHEN 'FULL'                     THEN 'Every row in the table ' || object_name || ' is read.'
            WHEN 'HASH'                     THEN 'Some rows in the table ' || object_name || ' were read using the hash index.'
            WHEN 'SAMPLE'                   THEN 'A sampled set of rows are read from table ' || object_name || '.'
            WHEN 'SAMPLE BY ROWID RANGE'    THEN 'A sampled set of rows are read from table ' || object_name || ' based on a range of ROWIDs.'
        END
    WHEN 'HASH JOIN'                    THEN
        CASE options
            WHEN 'ANTI'          THEN 'Rows from %%c1 which matched rows from %%c2 were eliminated (hash anti-join).'
            WHEN 'BUFFERED' THEN 'Joins buffered rows from %%c1 that match buffered rows from %%c2.'
            WHEN 'CARTESIAN'     THEN 'Rows from %%c1 which matched rows from %%c2 were returned (hash join).'
            WHEN 'OUTER'         THEN 'Rows from %%c1 which matched rows from %%c2 were returned (hash join).'
            WHEN 'RIGHT OUTER'   THEN 'Uses a hash right outer join.'
            WHEN 'RIGHT ANTI'    THEN 'Uses a hash right antijoin.'
            WHEN 'RIGHT SEMI'    THEN 'Uses a hash right semijoin.'
            WHEN 'SEMI'          THEN 'Rows from %%c1 which matched rows from %%c2 were returned (hash join).'
        END
    WHEN 'MERGE JOIN'                   THEN
        CASE options
            WHEN 'ANTI'        THEN 'Rows from %%c1 which matched rows from %%c2 were eliminated (merge anti-join).'
            WHEN 'CARTESIAN'   THEN 'Every row in %%c1 was joined to every row in %%c2.'
            WHEN 'OUTER'       THEN 'Join the results sets provided from %%c0 If there are not matching rows from %%c2 return null values for those columns.'
            WHEN 'SEMI'        THEN 'Rows from %%c1 which matched rows from %%c2 were returned (hash join).'
        END
    WHEN 'NESTED LOOPS'                 THEN
        CASE options
            WHEN 'ANTI'              THEN 'For each row returned by %%c1 get the matching row from %%c2 If there are not matching rows from %%c2 return nulls for those columns.'
            WHEN 'CARTESIAN'         THEN 'For each row returned by %%c1 get the matching row from %%c2 If there are not matching rows from %%c2 return nulls for those columns.'
            WHEN 'OUTER'             THEN 'For each row returned by %%c1 get the matching row from %%c2 If there are not matching rows from %%c2 return nulls for those columns.'
            WHEN 'PARTITION OUTER' THEN 'Retrieves rows from different tables using a partition outer join operation.'
            WHEN 'SEMI'              THEN 'For each row returned by %%c1 get the matching row from %%c2 If there are not matching rows from %%c2 return nulls for those columns.'
        END
    WHEN 'INDEX'                        THEN
        CASE options
            WHEN 'UNIQUE SCAN'             THEN 'Rows were retrieved using the unique index %%on.'
            WHEN 'FAST FULL SCAN'          THEN 'Rows were retrieved by performing a fast read of all index records in %%on.'
            WHEN 'FULL SCAN'               THEN 'Rows were retrieved by performing a sequential read of all records in index %%on in ascending order.'
            WHEN 'FULL SCAN DESCENDING'    THEN 'Rows were retrieved by performing a sequential read of all records in index %%on in descending order.'
            WHEN 'FULL SCAN (MIN/MAX)'     THEN 'All records of index %%on were scanned to support a MIN/MAX operation.'
            WHEN 'RANGE SCAN'              THEN 'One or more rows were retrieved using index %%on. The index was scanned in ascending order.'
            WHEN 'RANGE SCAN DESCENDING'   THEN 'One or more rows were retrieved using index %%on. The index was scanned in descending order.'
            WHEN 'RANGE SCAN (MIN/MAX)'    THEN 'The index %%on was scanned to support a MIN/MAX operation.'
            WHEN 'SAMPLE FAST FULL SCAN'   THEN 'Retrieves rows by performing a fast read on a portion of the index records.'
            WHEN 'SKIP SCAN'               THEN 'Rows were retrieved from concatenated index %%on without using the leading column(s).'
            WHEN 'SKIP SCAN DESCENDING'    THEN 'Retrieves rows from a concatenated index without using the leading column in descending order.'
        END
    WHEN 'VIEW'                         THEN 'A view definition was processed, either from a stored view ' ||
        CASE
            WHEN object_name IS NOT NULL THEN object_name
            ELSE 'or as defined by step'
        END
    WHEN 'TEMP TABLE GENERATION'        THEN 'Creates and retrieves data for a temporary table used in star transformations.'
    WHEN 'TEMP TABLE TRANSFORMATION'    THEN 'Retrieves data for a temporary table used in star transformations.'
    WHEN 'TRANSPOSE'                    THEN 'Transposes the results of GROUP BY to evaluate a PIVOT operation to produce the final pivoted data.'
    WHEN 'VIEW PUSHED PREDICATE'        THEN 'Pushes predicates into a temporary table used for storing query results.'
    WHEN 'WINDOW'                       THEN
        CASE options
            WHEN 'BUFFER'               THEN 'Supports an analytic function.'
            WHEN 'BUFFER PUSHED RANK'   THEN 'Supports an analytic function while executing the RANK function.'
            WHEN 'NOSORT'               THEN 'Retrieves data without sorting for an analytic function.'
            WHEN 'NOSORT STOPKEY'       THEN 'Retrieves data without sorting for an analytic function. Query results are limited by conditions defined by the stopkey.'
            WHEN 'SORT'                 THEN 'Sorts data for an analytic function.'
            WHEN 'SORT PUSHED RANK'     THEN 'Sorts data before executing the RANK function for an analytic function.'
        END
    WHEN 'UNION'                        THEN 'Return all rows from %%c0 - excluding duplicate rows.'
    WHEN 'UNION-ALL'                    THEN
        CASE options
            WHEN 'PARTITION'          THEN 'Combines and retrieves all rows, including duplicates, from two tables from a partitioned view.'
            WHEN 'PUSHED PREDICATE'   THEN 'Combines and retrieves all rows, including duplicates, from two tables using predicte pushing.'
            ELSE 'Return all rows from %%c0 - including duplicate rows.'
        END
    WHEN 'UNION ALL (RECURSIVE WITH)'   THEN
        CASE options
            WHEN 'BREADTH FIRST'   THEN 'Retrieves data from child rows only after retrieving data from all sibling rows.'
            WHEN 'DEPTH FIRST'     THEN 'Retrieves data from sibling rows only after retrieving data from all child rows.'
        END
    WHEN 'CONNECT BY'                   THEN
        CASE options
            WHEN 'ANTI'                            THEN 'ANTI'
            WHEN 'CARTESIAN'                       THEN 'CARTESIAN'
            WHEN 'OUTER'                           THEN 'OUTER'
            WHEN 'SEMI'                            THEN 'SEMI'
            WHEN 'WITH FILTERING'                  THEN 'WITH FILTERING'
            WHEN 'WITH FILTERING (UNIQUE)'         THEN 'WITH FILTERING (UNIQUE)'
            WHEN 'WITHOUT FILTERING'               THEN 'WITHOUT FILTERING'
            WHEN 'WITHOUT FILTERING (UNIQUE)'      THEN 'WITHOUT FILTERING (UNIQUE)'
            WHEN 'NO FILTERING WITH START-WITH'    THEN 'NO FILTERING WITH START-WITH'
            WHEN 'NO FILTERING WITH SW (UNIQUE)'   THEN 'NO FILTERING WITH SW (UNIQUE)'
        END
    WHEN 'CONNECT BY PUMP'              THEN 'Executes a hierarchical self-join.'
    WHEN 'SORT'                         THEN
        CASE options
            WHEN 'AGGREGATE'                                  THEN 'The rows were sorted to support a group operation (MAX,MIN,AVERAGE, SUM, etc).'
            WHEN 'AGGREGATE(PARALLEL_COMBINED_WITH_PARENT)'   THEN 'The rows were sorted to support a group operation (MAX,MIN,AVERAGE, SUM, etc).'
            WHEN 'BUFFER'
        then null
            WHEN 'CREATE INDEX'                               THEN 'Sorts rows when creating the index.'
            WHEN 'GROUP BY'                                   THEN 'The rows were sorted in order to be grouped.'
            WHEN 'GROUP BY NOSORT'                            THEN 'Retrieves and groups rows without sorting.'
            WHEN 'GROUP BY NOSORT ROLLUP'                     THEN 'Retrieves and groups rows using the rollup operator without sorting.'
            WHEN 'GROUP BY PIVOT'                             THEN 'Operation that sorts a set of rows into groups to query with a GROUP BY clause The PIVOT funtion is a pivot-specific optimization function for the SORT GROUP BY operator.'
            WHEN 'GROUP BY ROLLUP'                            THEN 'Retrieves and groups rows using the rollup operator.'
            WHEN 'GROUP BY ROLL UP'
        THEN 'Retrieves and groups rows using the rollup operator.'
            WHEN 'GROUP BY STOPKEY'                           THEN 'Retrieves and groups rows while limiting the query to conditions defined by the stopkey.'
            WHEN 'JOIN'                                       THEN 'The rows were sorted to support the join at %%c1.'
            WHEN 'JOIN(PARALLEL_COMBINED_WITH_PARENT)'        THEN 'The rows were sorted to support the join at %%c1.'
            WHEN 'ORDER BY'                                   THEN 'The results were sorted to support the ORDER BY clause.'
            WHEN 'ORDER BY STOPKEY'                           THEN 'The results were sorted to support the ORDER BY STOPKEY clause.'
            WHEN 'PARTITION JOIN'                             THEN 'Sorts rows from different tables using a partition outer join operation.'
            WHEN 'UNIQUE'                                     THEN 'The rows from %%c1 were sorted to eliminate duplicate rows.'
            WHEN 'UNIQUE NOSORT'                              THEN 'Retrieves only unique rows without sorting.'
            WHEN 'UNIQUE STOPKEY'                             THEN 'Retrieves only unique rows while limiting the query to conditions defined by the stopkey.'
        END
    WHEN 'HASH'                         THEN
        CASE options WHEN 'GROUP BY'         THEN 'Indexes and retrieves rows using hashing, and then organizes rows into groups.'
            WHEN 'GROUP BY PIVOT'   THEN 'Indexes and retrieves rows using hashing, and then organizes rows into groups in a pivot table.'
            WHEN 'UNIQUE'           THEN 'Indexes and retrieves distinct rows using hashing.'
        END
    WHEN 'BUFFER'                       THEN
        CASE options
            WHEN 'SORT' THEN 'Reads frequently accessed data during statement execution into private memory to reduce overhead.'
        END
    WHEN 'COUNT'                        THEN
        CASE options
            WHEN 'STOPKEY' THEN 'Processing was stopped when the specified number of rows from %%c1 were processed.'
            ELSE 'The rows in the result set from %%c1 were counted.'
        END
    WHEN 'AND-EQUAL'                    THEN 'Rows retrieved by %%c0 are combined and rows common to all are returned.'
    WHEN 'BULK BINDS GET'               THEN NULL
    WHEN 'PARTITION'                    THEN
        CASE options
            WHEN 'ALL'            THEN 'All partitions of %%c0 were accessed.'
            WHEN 'CONCATENATED'   THEN 'The operations in %%c0 were performed on multiple partitions of %%on.'
            WHEN 'EMPTY'          THEN 'Does not perform the operation on any partition in the table.'
            WHEN 'INLIST'         THEN 'A range of partitions of %%c0 were accessed based on the values in the IN List.'
            WHEN 'INVALID'        THEN 'The partition to be accessed in %%c0 is empty.'
            WHEN 'ITERATOR'       THEN 'Use to access multiple partitions (a subset).'
            WHEN 'SINGLE'         THEN 'The operations in %%c0 were performed on a single partitions of %%on.'
        END
    WHEN 'PARTITION COMBINED'           THEN
        CASE options
            WHEN 'PARTITION HASH'   THEN NULL
            WHEN 'ALL'              THEN NULL
            WHEN 'CONCATENATED'     THEN NULL
            WHEN 'EMPTY'            THEN 'Does not perform the operation on any partition in the table.'
            WHEN 'INLIST'           THEN NULL
            WHEN 'INVALID'          THEN NULL
            WHEN 'ITERATOR'         THEN NULL
            WHEN 'SINGLE'           THEN NULL
        END
    WHEN 'PARTITION LIST'               THEN
        CASE options
            WHEN 'ALL'            THEN NULL
            WHEN 'CONCATENATED'   THEN NULL
            WHEN 'EMPTY'          THEN 'Does not perform the operation on any partition in the table.'
            WHEN 'INLIST'         THEN NULL
            WHEN 'INVALID'        THEN NULL
            WHEN 'ITERATOR'       THEN NULL
            WHEN 'OR'             THEN 'Performs the operation on all table partitions in a disjunction.'
            WHEN 'SINGLE'         THEN NULL
            WHEN 'SUBQUERY'       THEN 'Performs the operation on all list table partitions based on a subquery.'
        END
    WHEN 'PARTITION RANGE'              THEN
        CASE options
            WHEN 'ALL'            THEN NULL
            WHEN 'CONCATENATED'   THEN NULL
            WHEN 'EMPTY'          THEN 'Does not perform the operation on any partition in the table.'
            WHEN 'INLIST'         THEN NULL
            WHEN 'INVALID'        THEN NULL
            WHEN 'ITERATOR'       THEN 'A range of partitions of %%c0 were accessed.'
            WHEN 'OR'             THEN 'Performs the operation on all range table partitions in a disjunction.'
            WHEN 'SINGLE'         THEN NULL
            WHEN 'SUBQUERY'       THEN 'Performs the operation on all table partitions based on a subquery.'
        END
    WHEN 'PARTITION REFERENCE'          THEN NULL
    WHEN 'PARTITION SYSTEM'             THEN
        CASE options
            WHEN 'ALL'      THEN NULL
            WHEN 'SINGLE'   THEN NULL
        END
    WHEN 'PART JOIN FILTER'             THEN NULL
    WHEN 'CREATE AS SELECT'             THEN 'Creates a table using selected information from another table.'
    WHEN 'CREATE INDEX STATEMENT'       THEN 'Creates index.'
    WHEN 'CREATE TABLE STATEMENT'       THEN 'Creates table.'
END explain
       , vsp.*
FROM v$sql_plan vsp
WHERE vsp.operation IN (
    'PARTITION COMBINED'
);