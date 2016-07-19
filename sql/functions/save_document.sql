CREATE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_doc           jsonb;
v_doc_id        jsonb;
v_id            uuid;
v_returning     record;
v_schema        text;
v_schemaname    text;
v_table         text;
v_tablename     text;

BEGIN

/* Working on array handling
IF jsonb_typeof(p_doc_string) = 'array' THEN
    FOR v_element IN jsonb_array_elements(p_doc_string) LOOP
        PERFORM save_document(v_element);
    END LOOP;
END IF;
*/

IF position('.' in p_tablename) > 0 THEN
    v_schema := split_part(p_tablename, '.', 1); 
    v_table := split_part(p_tablename, '.', 2);
ELSE
    RAISE EXCEPTION 'tablename must be schema qualified';
END IF;


SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM pg_catalog.pg_tables WHERE schemaname = v_schema AND tablename = v_table;

IF v_tablename IS NULL THEN
    SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM @extschema@.create_document(p_tablename);
END IF;

v_doc := p_doc_string;

IF v_doc ? 'id' THEN

    SELECT v_doc ->> 'id' INTO v_id;
    EXECUTE format('INSERT INTO %I.%I (id, body) 
                    VALUES (%L, %L) 
                    ON CONFLICT (id)
                    DO UPDATE SET body = EXCLUDED.body, updated_at = CURRENT_TIMESTAMP
                    RETURNING *'
                , v_schemaname, v_tablename, v_id, p_doc_string) INTO v_returning;
    RAISE DEBUG 'save_document: v_returning.id:%', v_returning.id;
    IF v_returning.id IS NOT NULL THEN
        RETURN v_doc;
    END IF;

ELSE -- id not contained in given json string

    EXECUTE format('INSERT INTO %I.%I (body) VALUES (%L) RETURNING *', v_schemaname, v_tablename, p_doc_string)
        INTO v_returning;

    RAISE DEBUG 'save_document: v_returning.id: %', v_returning.id;

    v_doc_id := jsonb_set(v_doc, ARRAY['id'], to_json(v_returning.id)::jsonb, true);

    RAISE DEBUG 'save_document: v_doc_id: %', v_doc_id;

    EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L'
        , v_schemaname
        , v_tablename
        , v_doc_id
        , v_returning.id);

    RETURN v_doc_id;

END IF;

END
$$;


