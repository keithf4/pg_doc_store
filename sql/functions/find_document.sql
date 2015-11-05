CREATE FUNCTION find_document(p_tablename text, p_criteria jsonb, p_orderbykey text DEFAULT 'id', p_orderby text DEFAULT 'ASC') RETURNS SETOF jsonb
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

IF upper(p_orderby) NOT IN ('ASC', 'DESC') THEN
    RAISE EXCEPTION 'orderby must be either ASC or DESC';
END IF;

FOR v_document IN 
    EXECUTE format('SELECT body FROM %I.%I WHERE body @> %L ORDER BY body ->> %L %s', v_schemaname, v_tablename, p_criteria, p_orderbykey, p_orderby)
LOOP
    RETURN NEXT v_document;
END LOOP;

END
$$;
