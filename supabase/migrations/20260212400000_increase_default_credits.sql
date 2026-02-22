-- =============================================================================
-- Increase default chat credits from 50 to 100,000
-- =============================================================================

-- Update the column default
ALTER TABLE chat_credits ALTER COLUMN credit_balance SET DEFAULT 100000;

-- Update the trigger function that initializes credits on chat creation
CREATE OR REPLACE FUNCTION on_chat_insert_create_credits()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.chat_credits (chat_id, credit_balance)
    VALUES (NEW.id, 100000);

    INSERT INTO public.chat_credit_transactions
        (chat_id, transaction_type, amount, balance_after)
    VALUES
        (NEW.id, 'initial', 100000, 100000);

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION on_chat_insert_create_credits IS
  'Auto-creates a chat_credits row with 100,000 free credits when a new chat is created.';
