CREATE FUNCTION search_document(p_tablename text, p_query text) RETURNS SETOF jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_document      jsonb;
v_schemaname    text;
v_tablename     text;  

BEGIN

IF position('.' in p_tablename) > 0 THEN
    v_schemaname := split_part(p_tablename, '.', 1); 
    v_tablename := split_part(p_tablename, '.', 2);
ELSE
    RAISE EXCEPTION 'tablename must be schema qualified';
END IF;

FOR v_document IN 
    EXECUTE format('SELECT body
                    FROM %I.%I
                    WHERE search @@ to_tsquery(%L)
                    ORDER BY ts_rank_cd(search,to_tsquery(%L)) DESC'
                    , v_schemaname
                    , v_tablename
                    , p_query
                    , p_query) 
LOOP
    RETURN NEXT v_document;
END LOOP;

END
$$;

