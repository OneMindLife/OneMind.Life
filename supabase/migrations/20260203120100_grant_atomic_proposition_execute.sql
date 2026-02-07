-- Migration: Grant execute permission on submit_proposition_atomic to service_role
-- Required for Edge Functions to call the function

GRANT EXECUTE ON FUNCTION submit_proposition_atomic(bigint, bigint, text, text) TO service_role;
