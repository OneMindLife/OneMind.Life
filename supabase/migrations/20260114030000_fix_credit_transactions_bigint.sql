-- Fix credit_transactions table to use BIGINT for chat_id and round_id
-- These columns reference chats.id and rounds.id which are BIGINT

-- Drop the foreign key constraints first
ALTER TABLE public.credit_transactions
DROP CONSTRAINT IF EXISTS credit_transactions_chat_id_fkey;

ALTER TABLE public.credit_transactions
DROP CONSTRAINT IF EXISTS credit_transactions_round_id_fkey;

-- Alter columns to BIGINT
ALTER TABLE public.credit_transactions
ALTER COLUMN chat_id TYPE BIGINT;

ALTER TABLE public.credit_transactions
ALTER COLUMN round_id TYPE BIGINT;

-- Re-add foreign key constraints
ALTER TABLE public.credit_transactions
ADD CONSTRAINT credit_transactions_chat_id_fkey
FOREIGN KEY (chat_id) REFERENCES public.chats(id) ON DELETE SET NULL;

ALTER TABLE public.credit_transactions
ADD CONSTRAINT credit_transactions_round_id_fkey
FOREIGN KEY (round_id) REFERENCES public.rounds(id) ON DELETE SET NULL;

COMMENT ON TABLE public.credit_transactions IS 'Audit log of all credit transactions (purchases, usage, refunds)';
