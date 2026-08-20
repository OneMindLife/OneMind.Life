"use client";

import { useEffect, useState } from "react";
import { loadBootstrap } from "@/lib/onemind/chat";
import { AppShell, Rail } from "../components/ui";

// Legacy route. The old Flutter app deep-linked here, incl. /home?chat_id=<id>.
// The wedge is code-based (/c/<code>), so:
//   /home?chat_id=<id> → resolve the chat's invite_code (via the DEFINER
//                        bootstrap) → /c/<code>
//   /home              → the landing (there's no dashboard in the wedge)
export default function HomeRedirect() {
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const id = Number(new URLSearchParams(window.location.search).get("chat_id"));
    if (!id) {
      window.location.replace("/");
      return;
    }
    let alive = true;
    (async () => {
      try {
        const data = await loadBootstrap(id);
        const code = data?.chat?.invite_code;
        if (!alive) return;
        if (code) window.location.replace(`/c/${code}`);
        else setFailed(true);
      } catch {
        if (alive) setFailed(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  return (
    <AppShell>
      <Rail />
      <div className="center-status">
        {failed ? (
          <>
            <div className="big">Chat not found</div>
            <a href="/create" className="btn" style={{ marginTop: 8 }}>
              Start a new decision
            </a>
          </>
        ) : (
          <>
            <div className="spin" style={{ width: 16, height: 16 }} />
            <div className="small">Opening…</div>
          </>
        )}
      </div>
    </AppShell>
  );
}
