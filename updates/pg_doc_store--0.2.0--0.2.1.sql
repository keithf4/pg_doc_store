-- Allow create_document() to work even if given table already exists. Outputs the same as if it had created it.


/*
 * Create a table to store documents (MongoDB "create" equivalent)
 * Only creates the table if it does not already exist
 * Returns the schema and tablename
 */
CREATE OR REPLACE FUNCTION create_document(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE

v_exists            text;
v_pgcrypto_schema   text;
v_schemaname        text;
v_tablename         text;

BEGIN

IF position('.' in p_tablename) > 0 THEN
    v_schemaname := split_part(p_tablename, '.', 1); 
    v_tablename := split_part(p_tablename, '.', 2);
ELSE
    RAISE EXCEPTION 'Given tablename must be schema qualified';
END IF;

SELECT nspname INTO v_pgcrypto_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'pgcrypto' AND e.extnamespace = n.oid;
IF v_pgcrypto_schema IS NULL THEN
    RAISE EXCEPTION 'Unable to determine schema pgcrypto is installed to.';
END IF;

SELECT t.tablename INTO v_exists FROM pg_catalog.pg_tables t WHERE t.schemaname = v_schemaname AND t.tablename = v_tablename;

IF v_exists IS NOT NULL THEN
    RAISE DEBUG 'create_document: Given table name (%) already exists. Skipping creation.', p_tablename;
    schemaname := v_schemaname;
    tablename := v_tablename;
    RETURN;
ELSE
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.%I (
                        id uuid PRIMARY KEY DEFAULT %I.gen_random_uuid()
                        , body jsonb NOT NULL
                        , search tsvector
                        , created_at timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL
                        , updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL
                        )'
                    , v_schemaname
                    , v_tablename
                    , v_pgcrypto_schema
                );

    EXECUTE format('CREATE INDEX ON %I.%I USING GIN(body jsonb_path_ops)', v_schemaname, v_tablename);
    EXECUTE format('CREATE INDEX ON %I.%I USING GIN(search)', v_schemaname, v_tablename);

    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF body
                    ON %I.%I
                    FOR EACH ROW
                    EXECUTE PROCEDURE @extschema@.update_search()'
                , v_tablename||'_trig'
                , v_schemaname
                , v_tablename
            );

    schemaname := v_schemaname;
    tablename := v_tablename;
    RETURN;
END IF;

END
$$;


/*
 * Add or update document in given table (MongoDB "save" equivalent)
 * If given table doesn't exist, create it
 * If given document id does not exist, create new document with that id
 * If given document id does exist, update that document
 * If no document id is given, generate one and create new document
 * Returns the new document as jsonb. 
 */
CREATE OR REPLACE FUNCTION save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb
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


