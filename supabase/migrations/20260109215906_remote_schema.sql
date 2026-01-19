


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgtap" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."generate_invite_code"() RETURNS character
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result CHAR(6) := '';
    i INT;
BEGIN
    FOR i IN 1..6 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."generate_invite_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    max_id INT;
BEGIN
    SELECT COALESCE(MAX(custom_id), 0) INTO max_id
    FROM iterations
    WHERE cycle_id = p_cycle_id;
    RETURN max_id + 1;
END;
$$;


ALTER FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_auth_user_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.users (id, email, display_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'name'),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = COALESCE(EXCLUDED.display_name, users.display_name),
        avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
        last_seen_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_auth_user_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_chat_check_limit"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    chat_count INT;
BEGIN
    IF NEW.creator_session_token IS NOT NULL AND NEW.creator_id IS NULL THEN
        SELECT COUNT(*) INTO chat_count
        FROM chats
        WHERE creator_session_token = NEW.creator_session_token
        AND is_active = TRUE;
        
        IF chat_count >= 10 THEN
            RAISE EXCEPTION 'Rate limit exceeded: maximum 10 active chats per anonymous session';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_chat_check_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_chat_insert_set_code"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    new_code CHAR(6);
    attempts INT := 0;
BEGIN
    IF NEW.access_method = 'code' AND NEW.invite_code IS NULL THEN
        LOOP
            new_code := generate_invite_code();
            BEGIN
                NEW.invite_code := new_code;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                attempts := attempts + 1;
                IF attempts > 10 THEN
                    RAISE EXCEPTION 'Could not generate unique invite code';
                END IF;
            END;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_chat_insert_set_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_chat_insert_set_expiration"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.creator_id IS NULL AND NEW.creator_session_token IS NOT NULL THEN
        NEW.expires_at := NOW() + INTERVAL '7 days';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_chat_insert_set_expiration"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_cycle_winner_set"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_chat_id BIGINT;
    new_cycle_id BIGINT;
BEGIN
    IF NEW.winning_proposition_id IS NULL OR OLD.winning_proposition_id IS NOT NULL THEN
        RETURN NEW;
    END IF;
    
    v_chat_id := NEW.chat_id;
    
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;
    
    INSERT INTO iterations (cycle_id, custom_id, phase)
    VALUES (new_cycle_id, 1, 'waiting');
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_cycle_winner_set"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_iteration_winner_set"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    prev_winner_id BIGINT;
    v_cycle_id BIGINT;
    v_chat_id BIGINT;
    new_iteration_id BIGINT;
BEGIN
    IF NEW.winning_proposition_id IS NULL OR 
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;
    
    v_cycle_id := NEW.cycle_id;
    SELECT chat_id INTO v_chat_id FROM cycles WHERE id = v_cycle_id;
    NEW.completed_at := NOW();
    
    SELECT winning_proposition_id INTO prev_winner_id
    FROM iterations
    WHERE cycle_id = v_cycle_id
    AND custom_id = NEW.custom_id - 1;
    
    IF prev_winner_id IS NOT NULL AND prev_winner_id = NEW.winning_proposition_id THEN
        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW()
        WHERE id = v_cycle_id;
    ELSE
        INSERT INTO iterations (cycle_id, custom_id, phase)
        VALUES (v_cycle_id, get_next_custom_id(v_cycle_id), 'waiting')
        RETURNING id INTO new_iteration_id;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_iteration_winner_set"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_proposition_update_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE chats
    SET last_activity_at = NOW(),
        expires_at = CASE 
            WHEN creator_session_token IS NOT NULL AND creator_id IS NULL 
            THEN NOW() + INTERVAL '7 days'
            ELSE expires_at
        END
    WHERE id = (
        SELECT c.chat_id 
        FROM cycles c 
        JOIN iterations i ON i.cycle_id = c.id 
        WHERE i.id = NEW.iteration_id
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_proposition_update_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_rating_update_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE chats
    SET last_activity_at = NOW(),
        expires_at = CASE 
            WHEN creator_session_token IS NOT NULL AND creator_id IS NULL 
            THEN NOW() + INTERVAL '7 days'
            ELSE expires_at
        END
    WHERE id = (
        SELECT c.chat_id 
        FROM cycles c 
        JOIN iterations i ON i.cycle_id = c.id 
        JOIN propositions p ON p.iteration_id = i.id
        WHERE p.id = NEW.proposition_id
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_rating_update_activity"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "initial_message" "text" NOT NULL,
    "description" "text",
    "invite_code" character(6),
    "access_method" "text" DEFAULT 'code'::"text" NOT NULL,
    "require_auth" boolean DEFAULT false NOT NULL,
    "require_approval" boolean DEFAULT false NOT NULL,
    "creator_id" "uuid",
    "creator_session_token" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "is_official" boolean DEFAULT false NOT NULL,
    "expires_at" timestamp with time zone,
    "last_activity_at" timestamp with time zone DEFAULT "now"(),
    "start_mode" "text" DEFAULT 'manual'::"text" NOT NULL,
    "auto_start_participant_count" integer DEFAULT 5,
    "proposing_duration_seconds" integer DEFAULT 86400 NOT NULL,
    "rating_duration_seconds" integer DEFAULT 86400 NOT NULL,
    "proposing_minimum" integer DEFAULT 2 NOT NULL,
    "rating_minimum" integer DEFAULT 2 NOT NULL,
    "proposing_threshold_percent" integer,
    "proposing_threshold_count" integer DEFAULT 5,
    "rating_threshold_percent" integer,
    "rating_threshold_count" integer DEFAULT 5,
    "enable_ai_participant" boolean DEFAULT false NOT NULL,
    "ai_propositions_count" integer DEFAULT 3,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chats_access_method_check" CHECK (("access_method" = ANY (ARRAY['code'::"text", 'invite_only'::"text"]))),
    CONSTRAINT "chats_ai_propositions_count_check" CHECK ((("ai_propositions_count" >= 1) AND ("ai_propositions_count" <= 10))),
    CONSTRAINT "chats_proposing_duration_seconds_check" CHECK (("proposing_duration_seconds" >= 60)),
    CONSTRAINT "chats_proposing_minimum_check" CHECK (("proposing_minimum" >= 1)),
    CONSTRAINT "chats_proposing_threshold_count_check" CHECK (("proposing_threshold_count" >= 1)),
    CONSTRAINT "chats_proposing_threshold_percent_check" CHECK ((("proposing_threshold_percent" >= 0) AND ("proposing_threshold_percent" <= 100))),
    CONSTRAINT "chats_rating_duration_seconds_check" CHECK (("rating_duration_seconds" >= 60)),
    CONSTRAINT "chats_rating_minimum_check" CHECK (("rating_minimum" >= 1)),
    CONSTRAINT "chats_rating_threshold_count_check" CHECK (("rating_threshold_count" >= 1)),
    CONSTRAINT "chats_rating_threshold_percent_check" CHECK ((("rating_threshold_percent" >= 0) AND ("rating_threshold_percent" <= 100))),
    CONSTRAINT "chats_start_mode_check" CHECK (("start_mode" = ANY (ARRAY['manual'::"text", 'auto'::"text"])))
);


ALTER TABLE "public"."chats" OWNER TO "postgres";


ALTER TABLE "public"."chats" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."chats_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."cycles" (
    "id" bigint NOT NULL,
    "chat_id" bigint NOT NULL,
    "winning_proposition_id" bigint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone
);


ALTER TABLE "public"."cycles" OWNER TO "postgres";


ALTER TABLE "public"."cycles" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."cycles_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."invites" (
    "id" bigint NOT NULL,
    "chat_id" bigint NOT NULL,
    "email" "text" NOT NULL,
    "invite_token" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invited_by" bigint,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "invites_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."invites" OWNER TO "postgres";


ALTER TABLE "public"."invites" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."invites_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."iterations" (
    "id" bigint NOT NULL,
    "cycle_id" bigint NOT NULL,
    "custom_id" integer NOT NULL,
    "phase" "text" DEFAULT 'waiting'::"text" NOT NULL,
    "phase_started_at" timestamp with time zone,
    "phase_ends_at" timestamp with time zone,
    "winning_proposition_id" bigint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    CONSTRAINT "iterations_phase_check" CHECK (("phase" = ANY (ARRAY['waiting'::"text", 'proposing'::"text", 'rating'::"text"])))
);


ALTER TABLE "public"."iterations" OWNER TO "postgres";


ALTER TABLE "public"."iterations" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."iterations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."join_requests" (
    "id" bigint NOT NULL,
    "chat_id" bigint NOT NULL,
    "user_id" "uuid",
    "session_token" "uuid",
    "display_name" "text" NOT NULL,
    "is_authenticated" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    CONSTRAINT "has_identity" CHECK ((("user_id" IS NOT NULL) OR ("session_token" IS NOT NULL))),
    CONSTRAINT "join_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'denied'::"text"])))
);


ALTER TABLE "public"."join_requests" OWNER TO "postgres";


ALTER TABLE "public"."join_requests" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."join_requests_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."kv_store_490463bc" (
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL
);


ALTER TABLE "public"."kv_store_490463bc" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."participants" (
    "id" bigint NOT NULL,
    "chat_id" bigint NOT NULL,
    "user_id" "uuid",
    "session_token" "uuid",
    "display_name" "text" NOT NULL,
    "is_host" boolean DEFAULT false NOT NULL,
    "is_authenticated" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "has_identity" CHECK ((("user_id" IS NOT NULL) OR ("session_token" IS NOT NULL))),
    CONSTRAINT "participants_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'kicked'::"text", 'left'::"text"])))
);


ALTER TABLE "public"."participants" OWNER TO "postgres";


ALTER TABLE "public"."participants" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."participants_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."proposition_ratings" (
    "id" bigint NOT NULL,
    "proposition_id" bigint NOT NULL,
    "rating" numeric(10,6) NOT NULL,
    "rank" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."proposition_ratings" OWNER TO "postgres";


ALTER TABLE "public"."proposition_ratings" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."proposition_ratings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."propositions" (
    "id" bigint NOT NULL,
    "iteration_id" bigint NOT NULL,
    "participant_id" bigint,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "propositions_content_check" CHECK (("length"("content") <= 500))
);


ALTER TABLE "public"."propositions" OWNER TO "postgres";


ALTER TABLE "public"."propositions" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."propositions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."ratings" (
    "id" bigint NOT NULL,
    "proposition_id" bigint NOT NULL,
    "participant_id" bigint,
    "session_token" "uuid",
    "rating" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ratings_rating_check" CHECK ((("rating" >= 0) AND ("rating" <= 100)))
);


ALTER TABLE "public"."ratings" OWNER TO "postgres";


ALTER TABLE "public"."ratings" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."ratings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "display_name" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_invite_code_key" UNIQUE ("invite_code");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cycles"
    ADD CONSTRAINT "cycles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invites"
    ADD CONSTRAINT "invites_invite_token_key" UNIQUE ("invite_token");



ALTER TABLE ONLY "public"."invites"
    ADD CONSTRAINT "invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."iterations"
    ADD CONSTRAINT "iterations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."join_requests"
    ADD CONSTRAINT "join_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kv_store_490463bc"
    ADD CONSTRAINT "kv_store_490463bc_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."participants"
    ADD CONSTRAINT "participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."proposition_ratings"
    ADD CONSTRAINT "proposition_ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."proposition_ratings"
    ADD CONSTRAINT "proposition_ratings_proposition_id_key" UNIQUE ("proposition_id");



ALTER TABLE ONLY "public"."propositions"
    ADD CONSTRAINT "propositions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ratings"
    ADD CONSTRAINT "ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."iterations"
    ADD CONSTRAINT "unique_custom_id_per_cycle" UNIQUE ("cycle_id", "custom_id");



ALTER TABLE ONLY "public"."invites"
    ADD CONSTRAINT "unique_email_per_chat" UNIQUE ("chat_id", "email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_chats_creator_session" ON "public"."chats" USING "btree" ("creator_session_token") WHERE ("creator_session_token" IS NOT NULL);



CREATE INDEX "idx_chats_invite_code" ON "public"."chats" USING "btree" ("invite_code");



CREATE UNIQUE INDEX "idx_chats_single_official" ON "public"."chats" USING "btree" ("is_official") WHERE ("is_official" = true);



CREATE INDEX "idx_cycles_chat" ON "public"."cycles" USING "btree" ("chat_id");



CREATE INDEX "idx_iterations_cycle" ON "public"."iterations" USING "btree" ("cycle_id");



CREATE INDEX "idx_participants_chat" ON "public"."participants" USING "btree" ("chat_id");



CREATE INDEX "idx_participants_session" ON "public"."participants" USING "btree" ("session_token") WHERE ("session_token" IS NOT NULL);



CREATE INDEX "idx_participants_user" ON "public"."participants" USING "btree" ("user_id") WHERE ("user_id" IS NOT NULL);



CREATE INDEX "idx_propositions_iteration" ON "public"."propositions" USING "btree" ("iteration_id");



CREATE INDEX "idx_ratings_proposition" ON "public"."ratings" USING "btree" ("proposition_id");



CREATE UNIQUE INDEX "idx_unique_rating_per_participant" ON "public"."ratings" USING "btree" ("proposition_id", "participant_id") WHERE ("participant_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_unique_rating_per_session" ON "public"."ratings" USING "btree" ("proposition_id", "session_token") WHERE ("session_token" IS NOT NULL);



CREATE UNIQUE INDEX "idx_unique_session_per_chat" ON "public"."participants" USING "btree" ("chat_id", "session_token") WHERE ("session_token" IS NOT NULL);



CREATE UNIQUE INDEX "idx_unique_user_per_chat" ON "public"."participants" USING "btree" ("chat_id", "user_id") WHERE ("user_id" IS NOT NULL);



CREATE INDEX "kv_store_490463bc_key_idx" ON "public"."kv_store_490463bc" USING "btree" ("key" "text_pattern_ops");



CREATE OR REPLACE TRIGGER "trg_chat_check_limit" BEFORE INSERT ON "public"."chats" FOR EACH ROW EXECUTE FUNCTION "public"."on_chat_check_limit"();



CREATE OR REPLACE TRIGGER "trg_chat_insert_set_code" BEFORE INSERT ON "public"."chats" FOR EACH ROW EXECUTE FUNCTION "public"."on_chat_insert_set_code"();



CREATE OR REPLACE TRIGGER "trg_chat_insert_set_expiration" BEFORE INSERT ON "public"."chats" FOR EACH ROW EXECUTE FUNCTION "public"."on_chat_insert_set_expiration"();



CREATE OR REPLACE TRIGGER "trg_cycle_winner_set" AFTER UPDATE OF "winning_proposition_id" ON "public"."cycles" FOR EACH ROW EXECUTE FUNCTION "public"."on_cycle_winner_set"();



CREATE OR REPLACE TRIGGER "trg_iteration_winner_set" BEFORE UPDATE OF "winning_proposition_id" ON "public"."iterations" FOR EACH ROW EXECUTE FUNCTION "public"."on_iteration_winner_set"();



CREATE OR REPLACE TRIGGER "trg_proposition_update_activity" AFTER INSERT ON "public"."propositions" FOR EACH ROW EXECUTE FUNCTION "public"."on_proposition_update_activity"();



CREATE OR REPLACE TRIGGER "trg_rating_update_activity" AFTER INSERT ON "public"."ratings" FOR EACH ROW EXECUTE FUNCTION "public"."on_rating_update_activity"();



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cycles"
    ADD CONSTRAINT "cycles_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invites"
    ADD CONSTRAINT "fk_invited_by" FOREIGN KEY ("invited_by") REFERENCES "public"."participants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."iterations"
    ADD CONSTRAINT "fk_iteration_winning_proposition" FOREIGN KEY ("winning_proposition_id") REFERENCES "public"."propositions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."propositions"
    ADD CONSTRAINT "fk_participant" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cycles"
    ADD CONSTRAINT "fk_winning_proposition" FOREIGN KEY ("winning_proposition_id") REFERENCES "public"."propositions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invites"
    ADD CONSTRAINT "invites_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."iterations"
    ADD CONSTRAINT "iterations_cycle_id_fkey" FOREIGN KEY ("cycle_id") REFERENCES "public"."cycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."join_requests"
    ADD CONSTRAINT "join_requests_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."join_requests"
    ADD CONSTRAINT "join_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."participants"
    ADD CONSTRAINT "participants_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."participants"
    ADD CONSTRAINT "participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."proposition_ratings"
    ADD CONSTRAINT "proposition_ratings_proposition_id_fkey" FOREIGN KEY ("proposition_id") REFERENCES "public"."propositions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."propositions"
    ADD CONSTRAINT "propositions_iteration_id_fkey" FOREIGN KEY ("iteration_id") REFERENCES "public"."iterations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ratings"
    ADD CONSTRAINT "ratings_participant_id_fkey" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ratings"
    ADD CONSTRAINT "ratings_proposition_id_fkey" FOREIGN KEY ("proposition_id") REFERENCES "public"."propositions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can create chats" ON "public"."chats" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can create join requests" ON "public"."join_requests" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can create propositions" ON "public"."propositions" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can join chats" ON "public"."participants" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can submit ratings" ON "public"."ratings" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can view active chats" ON "public"."chats" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Anyone can view cycles" ON "public"."cycles" FOR SELECT USING (true);



CREATE POLICY "Anyone can view invites" ON "public"."invites" FOR SELECT USING (true);



CREATE POLICY "Anyone can view iterations" ON "public"."iterations" FOR SELECT USING (true);



CREATE POLICY "Anyone can view own requests" ON "public"."join_requests" FOR SELECT USING (true);



CREATE POLICY "Anyone can view participants" ON "public"."participants" FOR SELECT USING (true);



CREATE POLICY "Anyone can view proposition ratings" ON "public"."proposition_ratings" FOR SELECT USING (true);



CREATE POLICY "Anyone can view propositions" ON "public"."propositions" FOR SELECT USING (true);



CREATE POLICY "Anyone can view ratings" ON "public"."ratings" FOR SELECT USING (true);



CREATE POLICY "Service role can manage cycles" ON "public"."cycles" USING (true);



CREATE POLICY "Service role can manage invites" ON "public"."invites" USING (true);



CREATE POLICY "Service role can manage iterations" ON "public"."iterations" USING (true);



CREATE POLICY "Service role can manage proposition ratings" ON "public"."proposition_ratings" USING (true);



CREATE POLICY "Service role can update chats" ON "public"."chats" FOR UPDATE USING (true);



CREATE POLICY "Service role can update join requests" ON "public"."join_requests" FOR UPDATE USING (true);



CREATE POLICY "Service role can update participants" ON "public"."participants" FOR UPDATE USING (true);



CREATE POLICY "Users can update own profile" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view own profile" ON "public"."users" FOR SELECT USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cycles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."iterations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."join_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."kv_store_490463bc" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."participants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."proposition_ratings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."propositions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ratings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."_add"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_add"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_add"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_add"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_add"("text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_add"("text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_add"("text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_add"("text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_alike"(boolean, "anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_alike"(boolean, "anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_alike"(boolean, "anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_alike"(boolean, "anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", "name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", "name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", "name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ancestor_of"("name", "name", "name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_are"("text", "name"[], "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_are"("text", "name"[], "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_are"("text", "name"[], "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_are"("text", "name"[], "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_areni"("text", "text"[], "text"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_areni"("text", "text"[], "text"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_areni"("text", "text"[], "text"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_areni"("text", "text"[], "text"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_array_to_sorted_string"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_array_to_sorted_string"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_array_to_sorted_string"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_array_to_sorted_string"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_assets_are"("text", "text"[], "text"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_assets_are"("text", "text"[], "text"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_assets_are"("text", "text"[], "text"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_assets_are"("text", "text"[], "text"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cast_exists"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "name", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "name", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "name", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cdi"("name", "name", "name", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cexists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cexists"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cexists"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ckeys"("name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ckeys"("name", "name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", "name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", "name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ckeys"("name", "name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_cleanup"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_cleanup"() TO "anon";
GRANT ALL ON FUNCTION "public"."_cleanup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cleanup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_cmp_types"("oid", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_cmp_types"("oid", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_cmp_types"("oid", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cmp_types"("oid", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "name", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "name", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "name", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_col_is_null"("name", "name", "name", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_constraint"("name", character, "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_constraint"("name", character, "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_constraint"("name", character, "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_constraint"("name", character, "name"[], "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_constraint"("name", "name", character, "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_constraint"("name", "name", character, "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_constraint"("name", "name", character, "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_constraint"("name", "name", character, "name"[], "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_contract_on"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_contract_on"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_contract_on"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_contract_on"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_currtest"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_currtest"() TO "anon";
GRANT ALL ON FUNCTION "public"."_currtest"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_currtest"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_db_privs"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_db_privs"() TO "anon";
GRANT ALL ON FUNCTION "public"."_db_privs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_db_privs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_def_is"("text", "text", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_def_is"("text", "text", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_def_is"("text", "text", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_def_is"("text", "text", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_definer"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_definer"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_definer"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_definer"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_definer"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_definer"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_definer"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_definer"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_dexists"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_dexists"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_dexists"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dexists"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_dexists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_dexists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_dexists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dexists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_do_ne"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_do_ne"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_do_ne"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_do_ne"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_docomp"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_docomp"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_docomp"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_docomp"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_error_diag"("text", "text", "text", "text", "text", "text", "text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_error_diag"("text", "text", "text", "text", "text", "text", "text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_error_diag"("text", "text", "text", "text", "text", "text", "text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_error_diag"("text", "text", "text", "text", "text", "text", "text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_expand_context"(character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_expand_context"(character) TO "anon";
GRANT ALL ON FUNCTION "public"."_expand_context"(character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_expand_context"(character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_expand_on"(character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_expand_on"(character) TO "anon";
GRANT ALL ON FUNCTION "public"."_expand_on"(character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_expand_on"(character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_expand_vol"(character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_expand_vol"(character) TO "anon";
GRANT ALL ON FUNCTION "public"."_expand_vol"(character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_expand_vol"(character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ext_exists"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ext_exists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ext_exists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_extensions"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_extensions"() TO "anon";
GRANT ALL ON FUNCTION "public"."_extensions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extensions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_extensions"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_extensions"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_extensions"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extensions"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_extras"(character[], "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_extras"(character, "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_extras"(character[], "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extras"(character[], "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_extras"(character, "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_extras"(character, "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_finish"(integer, integer, integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_finish"(integer, integer, integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_finish"(integer, integer, integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_finish"(integer, integer, integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fkexists"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_fprivs_are"("text", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_fprivs_are"("text", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_fprivs_are"("text", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fprivs_are"("text", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "anyelement", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "anyelement", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "anyelement", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "anyelement", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], "anyelement", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], "anyelement", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], "anyelement", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_func_compare"("name", "name", "name"[], "anyelement", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_funkargs"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_funkargs"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_funkargs"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_funkargs"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_ac_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_ac_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_ac_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_ac_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_col_ns_type"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_col_ns_type"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_col_ns_type"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_col_ns_type"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_col_privs"("name", "text", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_col_privs"("name", "text", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_col_privs"("name", "text", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_col_privs"("name", "text", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_col_type"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_context"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_context"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_context"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_context"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_db_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_db_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_db_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_db_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_db_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_db_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_db_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_db_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_dtype"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_dtype"("name", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_dtype"("name", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_fdw_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_fdw_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_fdw_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_fdw_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_func_owner"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_func_privs"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_func_privs"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_func_privs"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_func_privs"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_index_owner"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_lang_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_lang_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_lang_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_lang_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_language_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_language_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_language_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_language_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_latest"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_latest"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_latest"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_latest"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_latest"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_latest"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_get_latest"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_latest"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_note"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_note"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_get_note"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_note"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_note"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_note"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_note"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_note"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_opclass_owner"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character[], "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_rel_owner"(character, "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_schema_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_schema_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_schema_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_schema_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_schema_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_schema_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_schema_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_schema_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_sequence_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_sequence_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_sequence_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_sequence_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_server_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_server_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_server_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_server_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_table_privs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_table_privs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_table_privs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_table_privs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_tablespace_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_tablespace_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_tablespace_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_tablespace_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_tablespaceprivs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_tablespaceprivs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_tablespaceprivs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_tablespaceprivs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_type_owner"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_get_type_owner"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_get_type_owner"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_got_func"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_got_func"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_got_func"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_got_func"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_got_func"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_got_func"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_got_func"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_got_func"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_grolist"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_grolist"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_grolist"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_grolist"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_def"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_def"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_def"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_group"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_group"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_has_group"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_group"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_role"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_role"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_has_role"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_role"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_type"("name", character[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_type"("name", character[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_has_type"("name", character[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_type"("name", character[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_type"("name", "name", character[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_type"("name", "name", character[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_has_type"("name", "name", character[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_type"("name", "name", character[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_has_user"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_has_user"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_has_user"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_has_user"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_hasc"("name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_hasc"("name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_hasc"("name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_hasc"("name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_hasc"("name", "name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_hasc"("name", "name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_hasc"("name", "name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_hasc"("name", "name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_have_index"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_have_index"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_have_index"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ident_array_to_sorted_string"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ident_array_to_sorted_string"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_ident_array_to_sorted_string"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ident_array_to_sorted_string"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ident_array_to_string"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ident_array_to_string"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_ident_array_to_string"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ident_array_to_string"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ikeys"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_inherited"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_inherited"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_inherited"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_inherited"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_inherited"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_inherited"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_inherited"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_inherited"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_indexed"("name", "name", "text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_indexed"("name", "name", "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_is_indexed"("name", "name", "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_indexed"("name", "name", "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_instead"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_schema"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_schema"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_schema"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_schema"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_super"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_super"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_super"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_super"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_trusted"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_trusted"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_trusted"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_trusted"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_verbose"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_is_verbose"() TO "anon";
GRANT ALL ON FUNCTION "public"."_is_verbose"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_verbose"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_keys"("name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_keys"("name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_keys"("name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_keys"("name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_keys"("name", "name", character) TO "postgres";
GRANT ALL ON FUNCTION "public"."_keys"("name", "name", character) TO "anon";
GRANT ALL ON FUNCTION "public"."_keys"("name", "name", character) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_keys"("name", "name", character) TO "service_role";



GRANT ALL ON FUNCTION "public"."_lang"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_lang"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_lang"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lang"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_lang"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_lang"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_lang"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lang"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_missing"(character[], "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_missing"(character, "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_missing"(character[], "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_missing"(character[], "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_missing"(character, "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_missing"(character, "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_nosuch"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_nosuch"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_nosuch"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_nosuch"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_op_exists"("name", "name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_opc_exists"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_opc_exists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_opc_exists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_partof"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_partof"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_partof"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_parts"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_parts"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_parts"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_parts"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_parts"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_parts"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_parts"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_parts"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_pg_sv_column_array"("oid", smallint[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_pg_sv_column_array"("oid", smallint[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_pg_sv_column_array"("oid", smallint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_pg_sv_column_array"("oid", smallint[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_pg_sv_table_accessible"("oid", "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."_pg_sv_table_accessible"("oid", "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."_pg_sv_table_accessible"("oid", "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_pg_sv_table_accessible"("oid", "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."_pg_sv_type_array"("oid"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_pg_sv_type_array"("oid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_pg_sv_type_array"("oid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_pg_sv_type_array"("oid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_prokind"("p_oid" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."_prokind"("p_oid" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."_prokind"("p_oid" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_prokind"("p_oid" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."_query"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_query"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_query"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_query"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_quote_ident_like"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_quote_ident_like"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_quote_ident_like"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_quote_ident_like"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_refine_vol"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_refine_vol"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_refine_vol"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_refine_vol"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relcomp"("text", "anyarray", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "anyarray", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "anyarray", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "anyarray", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relcomp"("text", "text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relexists"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relexists"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_relexists"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relexists"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relexists"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relexists"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_relexists"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relexists"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relne"("text", "anyarray", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relne"("text", "anyarray", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_relne"("text", "anyarray", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relne"("text", "anyarray", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_relne"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_relne"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_relne"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_relne"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_returns"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_returns"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_returns"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_returns"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_returns"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_returns"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_returns"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_returns"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_rexists"(character, "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rexists"(character[], "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_rexists"(character, "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rexists"(character, "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_rule_on"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_runem"("text"[], boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_runem"("text"[], boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_runem"("text"[], boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_runem"("text"[], boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_runner"("text"[], "text"[], "text"[], "text"[], "text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_runner"("text"[], "text"[], "text"[], "text"[], "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_runner"("text"[], "text"[], "text"[], "text"[], "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_runner"("text"[], "text"[], "text"[], "text"[], "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_set"(integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_set"(integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_set"(integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_set"(integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_set"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_set"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_set"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_set"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_set"("text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_set"("text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_set"("text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_set"("text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_strict"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_strict"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_strict"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_strict"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_strict"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_strict"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_strict"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_strict"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_table_privs"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_table_privs"() TO "anon";
GRANT ALL ON FUNCTION "public"."_table_privs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_table_privs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_temptable"("anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_temptable"("anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_temptable"("anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_temptable"("anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_temptable"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_temptable"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_temptable"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_temptable"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_temptypes"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_temptypes"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."_temptypes"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_temptypes"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_time_trials"("text", integer, numeric) TO "postgres";
GRANT ALL ON FUNCTION "public"."_time_trials"("text", integer, numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."_time_trials"("text", integer, numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_time_trials"("text", integer, numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."_tlike"(boolean, "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_tlike"(boolean, "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_tlike"(boolean, "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_tlike"(boolean, "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_todo"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_todo"() TO "anon";
GRANT ALL ON FUNCTION "public"."_todo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_todo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_trig"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_trig"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_trig"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_type_func"("char", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_type_func"("char", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_types_are"("name"[], "text", character[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_types_are"("name"[], "text", character[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_types_are"("name"[], "text", character[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_types_are"("name"[], "text", character[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_types_are"("name", "name"[], "text", character[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_types_are"("name", "name"[], "text", character[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_types_are"("name", "name"[], "text", character[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_types_are"("name", "name"[], "text", character[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_unalike"(boolean, "anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_unalike"(boolean, "anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_unalike"(boolean, "anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_unalike"(boolean, "anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_vol"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_vol"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."_vol"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_vol"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_vol"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_vol"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."_vol"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_vol"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."add_result"(boolean, boolean, "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."add_result"(boolean, boolean, "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."add_result"(boolean, boolean, "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_result"(boolean, boolean, "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."alike"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."any_column_privs_are"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_eq"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_has"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_has"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_has"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_hasnt"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bag_ne"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."can"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."can"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."can"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."can"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."can"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cast_context_is"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."casts_are"("text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."casts_are"("text"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."casts_are"("text"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_test"("text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_test"("text", boolean, "text", "text", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cmp_ok"("anyelement", "text", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_default_is"("name", "name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_check"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_has_default"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_hasnt_default"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_fk"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_null"("table_name" "name", "column_name" "name", "description" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_null"("table_name" "name", "column_name" "name", "description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_null"("table_name" "name", "column_name" "name", "description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_null"("table_name" "name", "column_name" "name", "description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_pk"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_is_unique"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_fk"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_isnt_pk"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_not_null"("table_name" "name", "column_name" "name", "description" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_not_null"("table_name" "name", "column_name" "name", "description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_not_null"("table_name" "name", "column_name" "name", "description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_not_null"("table_name" "name", "column_name" "name", "description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_not_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_not_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_not_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_not_null"("schema_name" "name", "table_name" "name", "column_name" "name", "description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."col_type_is"("name", "name", "name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."collect_tap"(VARIADIC "text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."collect_tap"(VARIADIC "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."collect_tap"(VARIADIC "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."collect_tap"(VARIADIC "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."collect_tap"(character varying[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."collect_tap"(character varying[]) TO "anon";
GRANT ALL ON FUNCTION "public"."collect_tap"(character varying[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."collect_tap"(character varying[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."column_privs_are"("name", "name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."columns_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."composite_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."database_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."db_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."diag"(VARIADIC "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."diag"("msg" "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."diag"("msg" "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."diag"("msg" "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."diag"("msg" "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."diag"("msg" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."diag"("msg" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."diag"("msg" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."diag"("msg" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."diag_test_name"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."diag_test_name"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."diag_test_name"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."diag_test_name"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."display_oper"("name", "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."display_oper"("name", "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."display_oper"("name", "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."display_oper"("name", "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."do_tap"() TO "postgres";
GRANT ALL ON FUNCTION "public"."do_tap"() TO "anon";
GRANT ALL ON FUNCTION "public"."do_tap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."do_tap"() TO "service_role";



GRANT ALL ON FUNCTION "public"."do_tap"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."do_tap"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."do_tap"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."do_tap"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."do_tap"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."do_tap"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."do_tap"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."do_tap"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."do_tap"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."do_tap"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."do_tap"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."do_tap"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."doesnt_imatch"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."doesnt_match"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_is"("name", "text", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domain_type_isnt"("name", "text", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domains_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."domains_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domains_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."domains_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."enum_has_labels"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."enums_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."enums_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."enums_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."enums_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."extensions_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."extensions_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."extensions_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."extensions_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fail"() TO "postgres";
GRANT ALL ON FUNCTION "public"."fail"() TO "anon";
GRANT ALL ON FUNCTION "public"."fail"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fail"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fail"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fail"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."fail"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fail"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fdw_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."findfuncs"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."findfuncs"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."findfuncs"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."findfuncs"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."findfuncs"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."findfuncs"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."findfuncs"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."findfuncs"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."findfuncs"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."finish"("exception_on_failure" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."finish"("exception_on_failure" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."finish"("exception_on_failure" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."finish"("exception_on_failure" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name"[], "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name"[], "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fk_ok"("name", "name", "name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_table_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."foreign_tables_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name"[], "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_lang_is"("name", "name", "name"[], "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name"[], "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name") TO "anon";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_owner_is"("name", "name", "name"[], "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name"[], "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_privs_are"("name", "name", "name"[], "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name"[], "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."function_returns"("name", "name", "name"[], "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."functions_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."functions_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."functions_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."functions_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."groups_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."groups_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."groups_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_cast"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_check"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_check"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_check"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_check"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_check"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_check"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_check"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_check"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_check"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_check"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_check"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_check"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_column"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_column"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_composite"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_composite"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_composite"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_composite"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_composite"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_composite"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_composite"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_domain"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_domain"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_domain"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_domain"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_domain"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_domain"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_domain"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_domain"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_enum"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_enum"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_enum"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_enum"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_enum"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_enum"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_enum"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_enum"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_extension"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_extension"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_extension"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_extension"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_extension"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_extension"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_extension"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_extension"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_fk"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_fk"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_fk"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_fk"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_fk"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_fk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_fk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_foreign_table"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_foreign_table"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_function"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_group"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_group"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_group"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_group"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_group"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_group"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_group"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_group"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_index"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inherited_tables"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_language"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_language"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_language"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_language"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_language"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_language"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_language"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_language"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_leftop"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_materialized_view"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_materialized_view"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_opclass"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_opclass"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_opclass"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_opclass"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_opclass"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_opclass"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_operator"("name", "name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_pk"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_pk"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_pk"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_pk"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_pk"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_pk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_pk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_relation"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_relation"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_relation"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_relation"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_relation"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_relation"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_relation"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rightop"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_role"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_role"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rule"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_rule"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_schema"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_schema"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_schema"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_schema"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_schema"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_schema"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_schema"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_schema"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_sequence"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_sequence"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_sequence"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_sequence"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_sequence"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_sequence"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_table"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_table"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_table"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_table"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_table"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_table"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_table"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_table"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_table"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_table"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_table"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_tablespace"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_tablespace"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_trigger"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_type"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_type"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_type"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_type"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_type"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_type"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_type"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_type"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_type"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_type"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_type"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_unique"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_unique"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_unique"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_unique"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_unique"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_unique"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_unique"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_user"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_user"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_user"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_user"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_user"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_user"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_user"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_user"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_view"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_view"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_view"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_view"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_view"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_view"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_view"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_view"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_view"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."has_view"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_view"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_cast"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_column"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_composite"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_composite"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_domain"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_domain"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_enum"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_enum"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_extension"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_extension"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_fk"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_fk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_foreign_table"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_function"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_group"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_group"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_group"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_index"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_inherited_tables"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_language"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_language"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_language"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_leftop"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_materialized_view"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_opclass"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_operator"("name", "name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_pk"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_pk"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_relation"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_relation"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rightop"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_role"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_role"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_role"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_rule"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_schema"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_schema"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_schema"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_sequence"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_table"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_table"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_tablespace"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_trigger"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_type"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_type"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_user"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_user"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_user"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_view"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hasnt_view"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ialike"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."imatches"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."in_todo"() TO "postgres";
GRANT ALL ON FUNCTION "public"."in_todo"() TO "anon";
GRANT ALL ON FUNCTION "public"."in_todo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."in_todo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_primary"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_primary"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_type"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_unique"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_is_unique"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index_owner_is"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."indexes_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is"("anyelement", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_aggregate"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_ancestor_of"("name", "name", "name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_clustered"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_clustered"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_clustered"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_clustered"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_clustered"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_definer"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_descendent_of"("name", "name", "name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_empty"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_empty"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_empty"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_empty"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_empty"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_empty"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_empty"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_empty"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_indexed"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_normal_function"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partition_of"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partitioned"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_partitioned"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_procedure"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_strict"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_superuser"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_superuser"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_superuser"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_superuser"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_superuser"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_superuser"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_superuser"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_superuser"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_window"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype") TO "postgres";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype") TO "anon";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype") TO "service_role";



GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isa_ok"("anyelement", "regtype", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt"("anyelement", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_aggregate"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_ancestor_of"("name", "name", "name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_definer"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_descendent_of"("name", "name", "name", "name", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_empty"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_empty"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_empty"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_member_of"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_normal_function"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_partitioned"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_procedure"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_strict"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_superuser"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_superuser"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_superuser"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."isnt_window"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."language_is_trusted"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."language_is_trusted"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_is_trusted"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."language_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."languages_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."languages_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."languages_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lives_ok"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lives_ok"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."lives_ok"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lives_ok"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lives_ok"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lives_ok"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lives_ok"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lives_ok"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."matches"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_view_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."materialized_views_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."no_plan"() TO "postgres";
GRANT ALL ON FUNCTION "public"."no_plan"() TO "anon";
GRANT ALL ON FUNCTION "public"."no_plan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."no_plan"() TO "service_role";



GRANT ALL ON FUNCTION "public"."num_failed"() TO "postgres";
GRANT ALL ON FUNCTION "public"."num_failed"() TO "anon";
GRANT ALL ON FUNCTION "public"."num_failed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."num_failed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ok"(boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."ok"(boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."ok"(boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ok"(boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."ok"(boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."ok"(boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ok"(boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ok"(boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."on_auth_user_created"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_auth_user_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_auth_user_created"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_chat_check_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_chat_check_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_chat_check_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_chat_insert_set_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_chat_insert_set_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_chat_insert_set_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_chat_insert_set_expiration"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_chat_insert_set_expiration"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_chat_insert_set_expiration"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_cycle_winner_set"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_cycle_winner_set"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_cycle_winner_set"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_iteration_winner_set"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_iteration_winner_set"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_iteration_winner_set"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_proposition_update_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_proposition_update_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_proposition_update_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_rating_update_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_rating_update_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_rating_update_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclass_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."opclasses_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."operators_are"("text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."operators_are"("text"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."operators_are"("text"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."operators_are"("name", "text"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."os_name"() TO "postgres";
GRANT ALL ON FUNCTION "public"."os_name"() TO "anon";
GRANT ALL ON FUNCTION "public"."os_name"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."os_name"() TO "service_role";



GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."partitions_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pass"() TO "postgres";
GRANT ALL ON FUNCTION "public"."pass"() TO "anon";
GRANT ALL ON FUNCTION "public"."pass"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."pass"() TO "service_role";



GRANT ALL ON FUNCTION "public"."pass"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pass"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."pass"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pass"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric) TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_ok"("text", numeric, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric) TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."performs_within"("text", numeric, numeric, integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pg_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."pg_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."pg_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."pg_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."pg_version_num"() TO "postgres";
GRANT ALL ON FUNCTION "public"."pg_version_num"() TO "anon";
GRANT ALL ON FUNCTION "public"."pg_version_num"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."pg_version_num"() TO "service_role";



GRANT ALL ON FUNCTION "public"."pgtap_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."pgtap_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."pgtap_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgtap_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."plan"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."plan"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."plan"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."plan"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policies_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_cmd_is"("name", "name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."policy_roles_are"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."relation_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("refcursor", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_eq"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_eq"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("refcursor", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "refcursor", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."results_ne"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."results_ne"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."roles_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."roles_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."roles_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."row_eq"("text", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_instead"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rule_is_on"("name", "name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rules_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."runtests"() TO "postgres";
GRANT ALL ON FUNCTION "public"."runtests"() TO "anon";
GRANT ALL ON FUNCTION "public"."runtests"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."runtests"() TO "service_role";



GRANT ALL ON FUNCTION "public"."runtests"("name") TO "postgres";
GRANT ALL ON FUNCTION "public"."runtests"("name") TO "anon";
GRANT ALL ON FUNCTION "public"."runtests"("name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."runtests"("name") TO "service_role";



GRANT ALL ON FUNCTION "public"."runtests"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."runtests"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."runtests"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."runtests"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."runtests"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."runtests"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."runtests"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."runtests"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."schema_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."schema_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."schemas_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."schemas_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."schemas_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequence_privs_are"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequences_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sequences_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequences_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sequences_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."server_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_eq"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_eq"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_eq"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_has"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_has"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_has"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_hasnt"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_ne"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "anyarray", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_ne"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_ne"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."skip"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."skip"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."skip"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."skip"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."skip"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."skip"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."skip"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."skip"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."skip"(integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."skip"(integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."skip"(integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."skip"(integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."skip"("why" "text", "how_many" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."skip"("why" "text", "how_many" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."skip"("why" "text", "how_many" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."skip"("why" "text", "how_many" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."table_privs_are"("name", "name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tables_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."tables_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tables_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tables_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespace_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespace_privs_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tablespaces_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ilike"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_imatching"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_like"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_like"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_like"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_matching"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", character, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", character, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", character, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", character, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."throws_ok"("text", integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."todo"("how_many" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."todo"("why" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."todo"("why" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."todo"("why" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo"("why" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."todo"("how_many" integer, "why" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer, "why" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer, "why" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo"("how_many" integer, "why" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."todo"("why" "text", "how_many" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."todo"("why" "text", "how_many" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."todo"("why" "text", "how_many" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo"("why" "text", "how_many" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."todo_end"() TO "postgres";
GRANT ALL ON FUNCTION "public"."todo_end"() TO "anon";
GRANT ALL ON FUNCTION "public"."todo_end"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo_end"() TO "service_role";



GRANT ALL ON FUNCTION "public"."todo_start"() TO "postgres";
GRANT ALL ON FUNCTION "public"."todo_start"() TO "anon";
GRANT ALL ON FUNCTION "public"."todo_start"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo_start"() TO "service_role";



GRANT ALL ON FUNCTION "public"."todo_start"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."todo_start"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."todo_start"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."todo_start"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_is"("name", "name", "name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."triggers_are"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."type_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."types_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."types_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."types_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."types_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."types_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."types_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."types_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."types_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."types_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unalike"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unialike"("anyelement", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."users_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."users_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."users_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."users_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."users_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."users_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."users_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."users_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name") TO "postgres";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name") TO "anon";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name") TO "authenticated";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name") TO "service_role";



GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."view_owner_is"("name", "name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."views_are"("name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."views_are"("name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."views_are"("name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."views_are"("name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."views_are"("name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."views_are"("name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."views_are"("name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."views_are"("name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."views_are"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name"[], "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."volatility_is"("name", "name", "name"[], "text", "text") TO "service_role";


















GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";



GRANT ALL ON SEQUENCE "public"."chats_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."chats_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."chats_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cycles" TO "anon";
GRANT ALL ON TABLE "public"."cycles" TO "authenticated";
GRANT ALL ON TABLE "public"."cycles" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cycles_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cycles_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cycles_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."invites" TO "anon";
GRANT ALL ON TABLE "public"."invites" TO "authenticated";
GRANT ALL ON TABLE "public"."invites" TO "service_role";



GRANT ALL ON SEQUENCE "public"."invites_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."invites_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."invites_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."iterations" TO "anon";
GRANT ALL ON TABLE "public"."iterations" TO "authenticated";
GRANT ALL ON TABLE "public"."iterations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."iterations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."iterations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."iterations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."join_requests" TO "anon";
GRANT ALL ON TABLE "public"."join_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."join_requests" TO "service_role";



GRANT ALL ON SEQUENCE "public"."join_requests_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."join_requests_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."join_requests_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."kv_store_490463bc" TO "anon";
GRANT ALL ON TABLE "public"."kv_store_490463bc" TO "authenticated";
GRANT ALL ON TABLE "public"."kv_store_490463bc" TO "service_role";



GRANT ALL ON TABLE "public"."participants" TO "anon";
GRANT ALL ON TABLE "public"."participants" TO "authenticated";
GRANT ALL ON TABLE "public"."participants" TO "service_role";



GRANT ALL ON SEQUENCE "public"."participants_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."participants_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."participants_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."proposition_ratings" TO "anon";
GRANT ALL ON TABLE "public"."proposition_ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."proposition_ratings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."proposition_ratings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."proposition_ratings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."proposition_ratings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."propositions" TO "anon";
GRANT ALL ON TABLE "public"."propositions" TO "authenticated";
GRANT ALL ON TABLE "public"."propositions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."propositions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."propositions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."propositions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ratings" TO "anon";
GRANT ALL ON TABLE "public"."ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."ratings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ratings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ratings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ratings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

CREATE TRIGGER trg_auth_user_created AFTER INSERT OR UPDATE ON auth.users FOR EACH ROW EXECUTE FUNCTION public.on_auth_user_created();


