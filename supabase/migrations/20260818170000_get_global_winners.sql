-- Single round-trip permanent record for the continuous Global room.
--
-- Replaces the wedge's 4-sequential-request winners chain (get_round_history →
-- rounds → propositions → translations), which dominated cold-start latency:
-- perf_logs showed load_global_winners at a ~5s median while the underlying
-- queries ran in tens of ms — the cost was the round trips, not the SQL.
--
-- Returns, for every SEALED round (winner set) ordered oldest→newest, the fully
-- resolved record the client needs:
--   id, text (already translated), beat (props-in-round − 1, clamped ≥ 0),
--   voters (distinct rater count across rating_completions ∪ grid_rankings,
--   computed with ONE grouped aggregate instead of the old per-round
--   get_round_voter_count() N+1), time_iso (completed_at), and
--   winning_participant_id (for the client-side `mine` flag).
--
-- Access mirrors get_round_history: SECURITY DEFINER + can_read_chat_results
-- (service_role OR public chat OR participant). Additive — get_round_history is
-- left untouched so History/Results/LeaderChallenge keep their contract.
CREATE OR REPLACE FUNCTION public.get_global_winners(p_chat_id bigint, p_language_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE WHEN public.can_read_chat_results(p_chat_id) THEN
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'text', COALESCE(tr.translated_text, p.content),
          'beat', GREATEST(0, COALESCE(pc.cnt, 0) - 1),
          'voters', COALESCE(vc.voters, 0),
          'time_iso', to_jsonb(r.completed_at),
          'winning_participant_id', p.participant_id
        )
        ORDER BY r.id
      )
      FROM public.rounds r
      JOIN public.cycles cy ON cy.id = r.cycle_id
      LEFT JOIN public.propositions p ON p.id = r.winning_proposition_id
      LEFT JOIN public.translations tr
             ON tr.proposition_id = r.winning_proposition_id
            AND tr.entity_type = 'proposition'
            AND tr.field_name = 'content'
            AND tr.language_code = p_language_code
      LEFT JOIN LATERAL (
        SELECT count(*)::int AS cnt
        FROM public.propositions pp
        WHERE pp.round_id = r.id
      ) pc ON true
      LEFT JOIN LATERAL (
        SELECT count(DISTINCT u.participant_id)::int AS voters
        FROM (
          SELECT participant_id FROM public.rating_completions WHERE round_id = r.id
          UNION
          SELECT participant_id FROM public.grid_rankings WHERE round_id = r.id
        ) u
      ) vc ON true
      WHERE cy.chat_id = p_chat_id
        AND r.winning_proposition_id IS NOT NULL
    ), '[]'::jsonb)
  ELSE '[]'::jsonb END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_global_winners(bigint, text) TO anon, authenticated;
