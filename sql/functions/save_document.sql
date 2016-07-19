/*
 * Add or update document in given table (MongoDB "save" equivalent)
 * If given table doesn't exist, create it
 * If given document id does not exist, create new document with that id
 * If given document id does exist, update that document
 * If no document id is given, generate one and create new document
 * Returns the new document as jsonb. 
 */
CREATE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

v_doc           jsonb;
v_doc_id        jsonb;
v_id            uuid;
v_returning     record;
v_schemaname    text;
v_tablename     text;

BEGIN

/* Working on array handling
IF jsonb_typeof(p_doc_string) = 'array' THEN
    FOR v_element IN jsonb_array_elements(p_doc_string) LOOP
        PERFORM save_document(v_element);
    END LOOP;
END IF;
*/

SELECT schemaname, tablename INTO v_schemaname, v_tablename FROM @extschema@.create_document(p_tablename);

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

