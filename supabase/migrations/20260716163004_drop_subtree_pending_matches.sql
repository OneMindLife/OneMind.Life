-- The per-opinion "votes waiting below" slot was removed (at scale every card is
-- lit, so the badge saturates to noise). Drop its now-unused RPC.
DROP FUNCTION IF EXISTS public.get_subtree_pending_matches(bigint, bigint);
