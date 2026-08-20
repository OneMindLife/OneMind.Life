-- The root→target path of a proposition, for the /g?take=<id> deep-link: the
-- client pre-commits these choices so the walk auto-descends and lands on the
-- proposition (with the chain shown as the committed-card spine). Walks UP
-- prop → round → cycle.parent_proposition_id to the root cycle, then reverses.
CREATE OR REPLACE FUNCTION public.get_proposition_path(p_proposition_id bigint)
RETURNS TABLE(proposition_id bigint, round_id bigint, depth int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_prop bigint := p_proposition_id;
  v_round bigint;
  v_parent bigint;
  props bigint[] := '{}';
  rnds  bigint[] := '{}';
  n int; i int;
BEGIN
  LOOP
    SELECT p.round_id INTO v_round FROM propositions p WHERE p.id = v_prop;
    EXIT WHEN v_round IS NULL;
    props := array_append(props, v_prop);
    rnds  := array_append(rnds, v_round);
    SELECT c.parent_proposition_id INTO v_parent
    FROM rounds r JOIN cycles c ON c.id = r.cycle_id WHERE r.id = v_round;
    EXIT WHEN v_parent IS NULL;                 -- reached the root cycle
    v_prop := v_parent;
    EXIT WHEN array_length(props, 1) >= 20;      -- safety cap
  END LOOP;
  n := array_length(props, 1);
  IF n IS NULL THEN RETURN; END IF;
  FOR i IN REVERSE n..1 LOOP                      -- output root → target
    proposition_id := props[i];
    round_id := rnds[i];
    depth := n - i;
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_proposition_path(bigint) TO anon, authenticated, service_role;
