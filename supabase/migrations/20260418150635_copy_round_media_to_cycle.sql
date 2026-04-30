-- When a cycle converges (completed_at set), copy audio_url and video_url
-- from the cycle's rounds onto the cycle itself so the permanent convergence
-- card can surface them.
--
-- Audio: take the most recent round's audio_url (every official round generates
-- its own ElevenLabs mp3, so the final winning round's audio matches the
-- cycle's winning proposition text).
--
-- Video: take the most recent round in the cycle that has a non-null
-- video_url. Round videos are populated manually today; the last round with a
-- video is the most representative of the converged idea.

CREATE OR REPLACE FUNCTION trigger_copy_round_media_to_cycle()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.completed_at IS NULL THEN RETURN NEW; END IF;
  IF OLD.completed_at IS NOT NULL THEN RETURN NEW; END IF;

  IF NEW.audio_url IS NULL THEN
    SELECT audio_url INTO NEW.audio_url
    FROM rounds
    WHERE cycle_id = NEW.id AND audio_url IS NOT NULL
    ORDER BY custom_id DESC
    LIMIT 1;
  END IF;

  IF NEW.video_url IS NULL THEN
    SELECT video_url INTO NEW.video_url
    FROM rounds
    WHERE cycle_id = NEW.id AND video_url IS NOT NULL
    ORDER BY custom_id DESC
    LIMIT 1;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS copy_round_media_to_cycle_trigger ON cycles;
CREATE TRIGGER copy_round_media_to_cycle_trigger
BEFORE UPDATE OF completed_at ON cycles
FOR EACH ROW
EXECUTE FUNCTION trigger_copy_round_media_to_cycle();
