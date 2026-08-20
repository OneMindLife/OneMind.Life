import type { ReactNode } from "react";

/// The full-height responsive content column (the prototype's .stage). Every
/// screen wraps its body in <AppShell>.
///
/// `pinned` locks the shell to exactly one viewport tall (vs the default
/// min-height that grows with content). Use it on phase screens that have a
/// bottom action bar that must stay put while an inner list scrolls — otherwise
/// a long list grows the page and the foot-bar scrolls off-screen. Do NOT use it
/// on landing/create/results, which must scroll the whole page.
export function AppShell({
  children,
  pinned,
  className,
}: {
  children: ReactNode;
  pinned?: boolean;
  className?: string;
}) {
  return (
    <main className={`app${pinned ? " pinned" : ""}${className ? ` ${className}` : ""}`}>
      {children}
    </main>
  );
}

/// Minimal legal footer for the landing layer (root + SEO pages). Plain <a>
/// (not Link) — terms/privacy are static pages, no client nav needed.
export function LegalFooter() {
  return (
    <footer className="legal-foot">
      <a href="/terms/">Terms</a>
      <span aria-hidden="true">·</span>
      <a href="/privacy/">Privacy</a>
    </footer>
  );
}

export function Logomark() {
  return (
    <div className="logomark">
      <div className="ring" />
      <div className="ring inner" />
      <div className="dot" />
    </div>
  );
}

export function Logotype() {
  return (
    <div className="logotype">
      <Logomark />
      <span>OneMind</span>
    </div>
  );
}

/// Top rail with just the wordmark (landing / create-root screens).
export function BrandRail() {
  return (
    <div className="rail">
      <Logotype />
    </div>
  );
}

/// Top rail with a back affordance on the left + optional right slot.
export function Rail({
  back,
  onBack,
  right,
}: {
  back?: string;
  onBack?: () => void;
  right?: ReactNode;
}) {
  return (
    <div className="rail">
      {back ? (
        <button className="back" onClick={onBack} type="button">
          <svg viewBox="0 0 10 10" fill="none" stroke="currentColor" strokeWidth={1.5}>
            <path d="M6 2 L3 5 L6 8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span>{back}</span>
        </button>
      ) : (
        // No back affordance on a quick room (it's reached by link and IS the
        // destination) — show the wordmark so the slot isn't empty.
        <Logotype />
      )}
      {right ?? null}
    </div>
  );
}

export function GroupPill({ value, label }: { value: ReactNode; label: string }) {
  return (
    <div className="group-pill">
      <span className="value">{value}</span>
      <span>{label}</span>
    </div>
  );
}

export function HostPill({ label }: { label?: string }) {
  return <div className="host-pill">{label ?? "You're the host"}</div>;
}

/// The italic-serif decision question. `plain` drops the divider/border.
export function ChatQuestion({
  q,
  plain,
  size,
  roomLabel,
}: {
  q: string;
  plain?: boolean;
  size?: number;
  roomLabel?: string;
}) {
  return (
    <div className={`chat-q${plain ? " plain" : ""}`}>
      {roomLabel && <div className="room-label">{roomLabel}</div>}
      <div className="q" style={size ? { fontSize: `${size}px` } : undefined}>
        &ldquo;{q}&rdquo;
      </div>
    </div>
  );
}

// ── shared inline icons (match the prototype's stroke set) ──

export const Arrow = () => (
  <svg viewBox="0 0 16 16">
    <path d="M3 8h10M9 4l4 4-4 4" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const Check = () => (
  <svg viewBox="0 0 16 16">
    <path d="M3 8l3 3 7-7" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const ChevR = () => (
  <svg viewBox="0 0 11 11">
    <path d="M2 5.5h7M6.5 3l2.5 2.5L6.5 8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const LockIcon = () => (
  <svg viewBox="0 0 14 14" fill="none" stroke="currentColor">
    <rect x="2.5" y="6" width="9" height="6" rx="1.2" />
    <path d="M4.5 6V4.3a2.5 2.5 0 015 0V6" strokeLinecap="round" />
  </svg>
);

export const ShareIcon = () => (
  <svg viewBox="0 0 14 14">
    <path
      d="M5 9l4-4M6 3.5l1-1a2.5 2.5 0 013.5 3.5l-1 1M8 10.5l-1 1A2.5 2.5 0 013.5 8l1-1"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

export const PeopleIcon = () => (
  <svg viewBox="0 0 16 16">
    <circle cx="5.5" cy="6" r="2.2" />
    <circle cx="11" cy="6" r="2.2" />
    <path
      d="M2 13c0-2 1.6-3.2 3.5-3.2S9 11 9 13M9.5 13c0-1.4.8-2.6 2-3"
      strokeLinecap="round"
    />
  </svg>
);
