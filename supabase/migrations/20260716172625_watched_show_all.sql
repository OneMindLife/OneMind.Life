-- The bell inbox showed only watched threads with matches, so watching an
-- opinion with nothing to vote yet made it "vanish" (confusing). Show ALL
-- watches instead: matches-bearing first (actionable), the quiet ones after.
DROP FUNCTION IF EXISTS public.get_watched_matches(bigint);

CREATE FUNCTION public.get_watched(p_participant_id bigint)
RETURNS TABLE(proposition_id bigint, content text, match_count int, last_activity_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT ow.proposition_id, p.content, ow.match_count, ow.last_activity_at
  FROM opinion_watches ow
  JOIN propositions p ON p.id = ow.proposition_id
  WHERE ow.participant_id = p_participant_id
  ORDER BY (ow.match_count > 0) DESC,   -- actionable first
           ow.match_count DESC,          -- most votes waiting
           ow.last_activity_at ASC NULLS LAST,  -- oldest backlog first
           ow.created_at DESC;           -- newest quiet watches first
$$;

GRANT EXECUTE ON FUNCTION public.get_watched(bigint) TO anon, authenticated;
