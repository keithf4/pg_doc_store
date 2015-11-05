CREATE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_doc           jsonb;
v_id            uuid;
v_returning     record;
v_schemaname    text;
v_tablename     text;

BEGIN

IF position('.' in p_tablename) < 1 THEN
    RAISE EXCEPTION 'tablename must be schema qualified';
END IF;

/* Working on array handling
IF jsonb_typeof(p_doc_string) = 'array' THEN
    FOR v_element IN jsonb_array_elements(p_doc_string) LOOP
        PERFORM save_document(v_element);
    END LOOP;
END IF;
*/

SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM pg_catalog.pg_tables WHERE schemaname||'.'||tablename = p_tablename;

IF v_tablename IS NULL THEN
    SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM create_document(p_tablename);
END IF;

v_doc := p_doc_string;

IF p_doc_string ? 'id' THEN

    SELECT v_doc ->> 'id' INTO v_id;
    LOOP
        -- Implemenent true UPSERT in 9.5. Following solution still has race conditions
        EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L RETURNING *'
            , v_schemaname
            , v_tablename
            , v_doc
            , v_id) INTO v_returning;
        RAISE DEBUG 'save_document: v_returning.id:% ', v_returning.id;
        IF v_returning.id IS NOT NULL THEN
            RETURN v_doc;
        END IF;
        BEGIN
            EXECUTE format('INSERT INTO %I.%I (id, body) VALUES (%L, %L) RETURNING *', v_schemaname, v_tablename, v_id, p_doc_string);
            RETURN v_doc;
        EXCEPTION WHEN unique_violation THEN
            -- Do nothing and loop to try the UPDATE again.
        END;
    END LOOP;

ELSE -- id if

    EXECUTE format('INSERT INTO %I.%I (body) VALUES (%L) RETURNING *', v_schemaname, v_tablename, p_doc_string)
        INTO v_returning;

    RAISE DEBUG 'insert_document: v_returning.id: %', v_returning.id;

    -- There is no native way to add fields to a json column. Pulled this method from
    -- http://michael.otacoo.com/postgresql-2/manipulating-jsonb-data-with-key-unique/
    WITH json_union AS (
        SELECT * FROM jsonb_each(p_doc_string)
        UNION 
        SELECT * FROM jsonb_each(json_build_object('id', v_returning.id)::jsonb)
    )
    SELECT json_object_agg(key,value) 
    INTO v_doc
    FROM json_union;

    EXECUTE format('UPDATE %I.%I SET body = %L WHERE id = %L'
        , v_schemaname
        , v_tablename
        , v_doc
        , v_returning.id);

END IF; -- id if

RETURN v_doc;

END
$$;
