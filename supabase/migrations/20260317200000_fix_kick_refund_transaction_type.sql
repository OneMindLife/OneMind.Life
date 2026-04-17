-- Fix: Add 'kick_refund' to chat_credit_transactions transaction_type CHECK constraint.
-- The cleanup_round_funding_on_kick trigger (20260227025637) inserts 'kick_refund'
-- but it was never added to the allowed values, causing kicks to fail.

ALTER TABLE public.chat_credit_transactions
    DROP CONSTRAINT chat_credit_transactions_transaction_type_check;

ALTER TABLE public.chat_credit_transactions
    ADD CONSTRAINT chat_credit_transactions_transaction_type_check
    CHECK (transaction_type IN (
        'initial', 'round_start', 'mid_round_join', 'purchase', 'kick_refund'
    ));
