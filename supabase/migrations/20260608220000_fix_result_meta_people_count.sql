-- get_chat_result_meta.people counted ALL active participants (everyone who
-- joined the link), so a lurker who never proposed or voted inflated the
-- "N people converged" count on the result screen (e.g. chat 806 showed 7 when
-- only 6 participated). Count only people who actually participated in the
-- decision (submitted a proposition OR cast a pairwise comparison, incl. skips).
CREATE OR REPLACE FUNCTION public.get_chat_result_meta(p_chat_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'rounds', coalesce((SELECT max(r.custom_id) FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0),
    'people', (
      SELECT count(DISTINCT pid) FROM (
        SELECT pr.participant_id AS pid
          FROM propositions pr
          JOIN rounds r ON r.id = pr.round_id
          JOIN cycles cy ON cy.id = r.cycle_id
          WHERE cy.chat_id = p_chat_id AND pr.participant_id IS NOT NULL
        UNION
        SELECT pc.participant_id
          FROM pairwise_comparisons pc
          JOIN rounds r ON r.id = pc.round_id
          JOIN cycles cy ON cy.id = r.cycle_id
          WHERE cy.chat_id = p_chat_id AND pc.participant_id IS NOT NULL
      ) u
    ),
    'comparisons', coalesce((SELECT count(*) FROM pairwise_comparisons pc JOIN rounds r ON r.id = pc.round_id JOIN cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0)
  );
$function$;
