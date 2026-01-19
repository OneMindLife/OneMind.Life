-- Filter out chats the user has already joined from Discover
-- Pass session_token to exclude user's own chats

CREATE OR REPLACE FUNCTION public.get_public_chats(
    p_limit integer DEFAULT 20,
    p_offset integer DEFAULT 0,
    p_session_token uuid DEFAULT NULL
)
RETURNS TABLE(
    id bigint,
    name text,
    description text,
    initial_message text,
    participant_count bigint,
    created_at timestamp with time zone,
    last_activity_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) as participant_count,
        c.created_at,
        c.last_activity_at
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.access_method = 'public'
    AND c.is_active = true
    -- Exclude chats where the user is already a participant
    AND (
        p_session_token IS NULL
        OR NOT EXISTS (
            SELECT 1 FROM participants pp
            WHERE pp.chat_id = c.id
            AND pp.session_token = p_session_token
            AND pp.status = 'active'
        )
    )
    GROUP BY c.id
    ORDER BY c.last_activity_at DESC NULLS LAST, c.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$function$;

-- Also update search_public_chats to filter out joined chats
CREATE OR REPLACE FUNCTION public.search_public_chats(
    p_query text,
    p_limit integer DEFAULT 20,
    p_session_token uuid DEFAULT NULL
)
RETURNS TABLE(
    id bigint,
    name text,
    description text,
    initial_message text,
    participant_count bigint,
    created_at timestamp with time zone,
    last_activity_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) as participant_count,
        c.created_at,
        c.last_activity_at
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.access_method = 'public'
    AND c.is_active = true
    AND (
        c.name ILIKE '%' || p_query || '%'
        OR c.description ILIKE '%' || p_query || '%'
        OR c.initial_message ILIKE '%' || p_query || '%'
    )
    -- Exclude chats where the user is already a participant
    AND (
        p_session_token IS NULL
        OR NOT EXISTS (
            SELECT 1 FROM participants pp
            WHERE pp.chat_id = c.id
            AND pp.session_token = p_session_token
            AND pp.status = 'active'
        )
    )
    GROUP BY c.id
    ORDER BY
        CASE WHEN c.name ILIKE '%' || p_query || '%' THEN 0 ELSE 1 END,
        c.last_activity_at DESC NULLS LAST
    LIMIT p_limit;
END;
$function$;
