CREATE FUNCTION update_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

v_row           record;
v_search_vals   text = '';

BEGIN

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        FOR v_row IN SELECT key, value FROM jsonb_each_text(NEW.body) LOOP
            IF v_row.key <> 'id' THEN
                v_search_vals := v_search_vals || ' ' || v_row.value;
            END IF;
        END LOOP;

        NEW.search := to_tsvector(v_search_vals);

    END IF;

    RETURN NEW;
END
$$;

