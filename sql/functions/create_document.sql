/*
 * Create a table to store documents (MongoDB "create" equivalent)
 * Only creates the table if it does not already exist
 * Returns the schema and tablename
 */
CREATE FUNCTION create_document(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record
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

