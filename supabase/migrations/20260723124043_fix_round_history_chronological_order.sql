-- get_round_history ordered by r.custom_id, which is the round number WITHIN a
-- cycle. In instant mode (confirmation_rounds_required = 1) every round seals
-- its own cycle, so custom_id resets to 1 each time -- the newest winner sorted
-- next to the oldest and the /c/GLOBAL record showed messages out of order.
-- r.id is monotonic across cycles and matches custom_id order within a cycle,
-- so this is strictly more correct for both modes.
CREATE OR REPLACE FUNCTION public.get_round_history(p_chat_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE WHEN public.can_read_chat_results(p_chat_id) THEN coalesce(
    (SELECT jsonb_agg(
        jsonb_build_object('id', r.id, 'custom_id', r.custom_id, 'winner', p.content,
          'voters', public.get_round_voter_count(r.id))
        ORDER BY r.id)
     FROM public.rounds r
     JOIN public.cycles cy ON cy.id = r.cycle_id
     LEFT JOIN public.propositions p ON p.id = r.winning_proposition_id
     WHERE cy.chat_id = p_chat_id),
    '[]'::jsonb)
  ELSE '[]'::jsonb END;
$function$;
