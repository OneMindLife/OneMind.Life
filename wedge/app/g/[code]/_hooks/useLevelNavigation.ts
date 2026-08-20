"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  descendChoices,
  jumpChoices,
  pathChoices,
  type Choices,
} from "@/lib/onemind/levelNav";

export type NavDir = "fwd" | "back" | null;

/// Owns the tree chat's level navigation: the committed-choices map, the
/// push/pop direction, per-level scroll memory, and the list slide. The choice
/// math itself lives in the pure `levelNav` module (tested there); this hook is
/// the thin React shell that holds the state and runs the two effects.
///
/// Usage: call it, derive the walk from `choices`, then report the current
/// on-screen `levelKey` back via `rememberLevel(levelKey)` each render so the
/// scroll/slide effects and the nav handlers act on the right level.
export function useLevelNavigation() {
  /// Committed choice per level: key `-roundId` for root positions, parent
  /// proposition id for tree nodes.
  const [choices, setChoices] = useState<Choices>({});
  const [navDir, setNavDir] = useState<NavDir>(null);
  const scrollByLevel = useRef<Map<string, number>>(new Map());
  const levelKeyRef = useRef("root");
  const slideRef = useRef<HTMLDivElement>(null);
  const crumbRef = useRef<HTMLElement | null>(null);

  /// The caller computes the on-screen level key from the walk (which depends on
  /// `choices`), so it can't be a hook argument without a cycle — it's reported
  /// back each render instead. Ref write in render is safe (idempotent).
  const rememberLevel = useCallback((levelKey: string) => {
    levelKeyRef.current = levelKey;
  }, []);

  // After a level change: descend → top of the new list; Back → the exact scroll
  // position the parent list was at when you left it. (levelKeyRef holds the NEW
  // level's key by the time this runs post-commit.)
  useEffect(() => {
    if (navDir === "back") {
      window.scrollTo(0, scrollByLevel.current.get(levelKeyRef.current) ?? 0);
    } else if (navDir === "fwd") {
      window.scrollTo(0, 0);
    }
    // Keep the RIGHT edge of the path in view, so the crumb for the level you're
    // in is always the one you see (the bar scrolls left→right as you go deeper).
    const c = crumbRef.current;
    if (c) c.scrollLeft = c.scrollWidth;
  }, [choices, navDir]);

  // NO slide animation. Navigating used to slide the list in from the side
  // (240ms); it read as jitter on every tap and bought nothing — the spine and
  // the breadcrumb already show you where you moved. `navDir` is still tracked:
  // it drives the scroll restore above (descend → top, back → where you left).

  const saveScroll = () =>
    scrollByLevel.current.set(levelKeyRef.current, window.scrollY);

  /// Descend into an opinion's thread: remember this list's scroll, slide the
  /// child in from the right.
  const descend = useCallback((key: number, propId: number) => {
    saveScroll();
    setNavDir("fwd");
    setChoices((prev) => descendChoices(prev, key, propId));
  }, []);

  /// Jump UP the breadcrumb path to crumb `i` (chain index; -1 = root). Slides
  /// the target level in from the left; its saved scroll is restored above.
  const jumpTo = useCallback((committedKeys: number[], i: number) => {
    saveScroll();
    setNavDir("back");
    setChoices((prev) => jumpChoices(prev, committedKeys, i));
  }, []);

  /// Deep-link: pre-commit a root→target path so the walk descends onto it.
  const applyPath = useCallback(
    (path: { round_id: number; proposition_id: number }[]) => {
      setChoices((prev) => pathChoices(prev, path));
    },
    [],
  );

  return {
    choices,
    navDir,
    slideRef,
    crumbRef,
    rememberLevel,
    descend,
    jumpTo,
    applyPath,
  };
}
