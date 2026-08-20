-- Daily Frontier ritual (Joel, 2026-07-15) — see docs/TELEGRAM_DAILY_FRONTIER.md.
-- Recursively follow the #1-ranked take down the tree to its living edge; snapshot
-- it once/day as the featured chain. Value + contribution, not divisive bait.

CREATE TABLE IF NOT EXISTS public.daily_featured (
  chat_id                 bigint NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  feature_date            date   NOT NULL,
  frontier_proposition_id bigint REFERENCES propositions(id) ON DELETE SET NULL,
  chain                   jsonb  NOT NULL DEFAULT '[]'::jsonb,
  created_at              timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chat_id, feature_date)
);
ALTER TABLE public.daily_featured ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS daily_featured_read ON public.daily_featured;
CREATE POLICY daily_featured_read ON public.daily_featured FOR SELECT USING (true);

-- Recursive #1-descent → the frontier chain.
CREATE OR REPLACE FUNCTION public.compute_daily_frontier(p_chat_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_round bigint; v_prop bigint; v_content text; v_score numeric;
  v_child_cycle bigint; v_child_round bigint;
  v_chain jsonb := '[]'::jsonb; v_depth int := 0; v_has_child boolean;
BEGIN
  SELECT r.id INTO v_round
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = p_chat_id AND c.parent_proposition_id IS NULL
  ORDER BY r.id DESC LIMIT 1;

  LOOP
    SELECT p.id, p.content, gs.global_score
      INTO v_prop, v_content, v_score
    FROM propositions p
    LEFT JOIN proposition_global_scores gs
           ON gs.proposition_id = p.id AND gs.round_id = v_round
    WHERE p.round_id = v_round AND p.carried_from_id IS NULL
    ORDER BY gs.global_score DESC NULLS LAST, p.created_at
    LIMIT 1;

    EXIT WHEN v_prop IS NULL OR v_depth >= 20;
    v_chain := v_chain || jsonb_build_object(
      'proposition_id', v_prop, 'content', v_content,
      'round_id', v_round, 'score', v_score);
    v_depth := v_depth + 1;

    SELECT cc.id INTO v_child_cycle FROM cycles cc
      WHERE cc.parent_proposition_id = v_prop;
    EXIT WHEN v_child_cycle IS NULL;
    SELECT r.id INTO v_child_round FROM rounds r
      WHERE r.cycle_id = v_child_cycle ORDER BY r.id DESC LIMIT 1;
    EXIT WHEN v_child_round IS NULL;
    SELECT EXISTS(SELECT 1 FROM propositions
      WHERE round_id = v_child_round AND carried_from_id IS NULL) INTO v_has_child;
    EXIT WHEN NOT v_has_child;
    v_round := v_child_round;
  END LOOP;

  RETURN jsonb_build_object('chain', v_chain, 'frontier_proposition_id', v_prop);
END;
$$;

-- Snapshot today's frontier (idempotent for the day). Callable by the cron.
CREATE OR REPLACE FUNCTION public.snapshot_daily_frontier(p_chat_id bigint)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.daily_featured (chat_id, feature_date, frontier_proposition_id, chain)
  SELECT p_chat_id, (now() AT TIME ZONE 'America/New_York')::date,
         (f->>'frontier_proposition_id')::bigint, f->'chain'
  FROM public.compute_daily_frontier(p_chat_id) f
  ON CONFLICT (chat_id, feature_date) DO UPDATE
    SET frontier_proposition_id = EXCLUDED.frontier_proposition_id,
        chain = EXCLUDED.chain;
$$;

GRANT EXECUTE ON FUNCTION public.compute_daily_frontier(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.snapshot_daily_frontier(bigint) TO service_role;

-- Daily snapshot for GLOBAL (1260) at 13:00 UTC (~9am ET). Pure SQL, no edge fn.
SELECT cron.unschedule('daily-frontier-global')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-frontier-global');
SELECT cron.schedule('daily-frontier-global', '0 13 * * *',
  $cron$ SELECT public.snapshot_daily_frontier(1260); $cron$);

-- Seed today's row immediately so there's something to feature now — but only
-- where chat 1260 (prod GLOBAL) actually exists. A fresh/local DB has no 1260,
-- and the unconditional seed hit a FK violation there and broke `db reset`.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.chats WHERE id = 1260) THEN
    PERFORM public.snapshot_daily_frontier(1260);
  END IF;
END $$;
