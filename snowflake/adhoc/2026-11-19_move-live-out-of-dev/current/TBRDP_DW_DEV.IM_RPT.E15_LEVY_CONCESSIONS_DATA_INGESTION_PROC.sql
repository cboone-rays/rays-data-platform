
DECLARE
    row_count INTEGER;
    source_qualified_name STRING;
    target_qualified_name STRING;
BEGIN
    source_qualified_name := source_db || '.' || source_schema || '.' || source_table;
    target_qualified_name := target_db || '.' || target_schema || '.' || target_table;
    
    TRUNCATE TABLE IDENTIFIER(:target_qualified_name);
    
    INSERT INTO IDENTIFIER(:target_qualified_name)
    SELECT * FROM IDENTIFIER(:source_qualified_name);

    TRUNCATE TABLE TBRDP_DW_QA.LOAD.E15_LEVY_CONCESSIONS_LOAD;
    
    INSERT INTO TBRDP_DW_QA.LOAD.E15_LEVY_CONCESSIONS_LOAD
    SELECT * FROM IDENTIFIER(:target_qualified_name);

    TRUNCATE TABLE TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD;
    
    INSERT INTO TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD
    SELECT * FROM IDENTIFIER(:target_qualified_name);
    
    row_count := SQLROWCOUNT;
    
    RETURN 'Successfully copied ' || row_count || ' rows from ' || 
           source_qualified_name || ' to ' || target_qualified_name;
END;
