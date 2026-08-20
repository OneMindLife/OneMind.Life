"use client";

import { SendIcon } from "./icons";
import css from "../TreeChat.module.css";

/// The composer's send control. While the post is in flight the arrow becomes a
/// circular progress indicator IN PLACE — the button itself is the status, so
/// the user gets immediate "it's sending" feedback with no layout shift (the
/// spinner is sized to the icon). Shared by every composer (compose sheet,
/// inline, leaf) so the sending affordance is identical everywhere.
export function SendButton({
  sending,
  disabled = false,
  onSend,
  label = "Send",
}: {
  sending: boolean;
  /// Non-sending reasons to block (e.g. empty draft).
  disabled?: boolean;
  onSend: () => void;
  label?: string;
}) {
  return (
    <button
      className={css.sendBtn}
      onClick={onSend}
      disabled={sending || disabled}
      type="button"
      aria-label={sending ? "Sending…" : label}
      aria-busy={sending}
    >
      {sending ? <span className={css.sendSpinner} aria-hidden /> : <SendIcon />}
    </button>
  );
}
