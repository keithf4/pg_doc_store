-- Extension now requires PostgreSQL 9.5.
-- Changed from using exception trap to using INSERT ON CONFLICT (upsert) feature introduced in PostgreSQL 9.5. Concurrent inserts & updates to the same document ID should now be transactionally safe from race conditions.
-- Changed to using new json_set() function introduced in 9.5. Allows easier adding of automatic id value to a given document if one is not given to save_document().
-- Fixed bug where updated_at column was not being properly set when a document is updated.
-- Changed check_version() function to work with non-release versions of PostgreSQL. Not actually used in extension yet.


CREATE OR REPLACE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
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


/*
 * Check PostgreSQL version number. Parameter must be full 3 point version.
 * Returns true if current version is greater than or equal to the parameter given.
 */
CREATE OR REPLACE FUNCTION check_version(p_check_version text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE

v_check_version     text[];
v_current_version   text[] := string_to_array(current_setting('server_version'), '.');
 
BEGIN

v_check_version := string_to_array(p_check_version, '.');

IF v_current_version[1]::int > v_check_version[1]::int THEN
    RETURN true;
END IF;
IF v_current_version[1]::int = v_check_version[1]::int THEN
    IF substring(v_current_version[2] from 'beta') IS NOT NULL 
        OR substring(v_current_version[2] from 'alpha') IS NOT NULL 
        OR substring(v_current_version[2] from 'rc') IS NOT NULL 
    THEN
        -- You're running a test version. You're on your own if things fail.
        RETURN true;
    END IF;
    IF v_current_version[2]::int > v_check_version[2]::int THEN
        RETURN true;
    END IF;
    IF v_current_version[2]::int = v_check_version[2]::int THEN
        IF v_current_version[3]::int >= v_check_version[3]::int THEN
            RETURN true;
        END IF; -- 0.0.x
    END IF; -- 0.x.0
END IF; -- x.0.0

RETURN false;

END
$$;


