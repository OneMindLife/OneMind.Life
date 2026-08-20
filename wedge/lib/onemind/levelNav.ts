// Pure level-navigation logic for the tree chat: how the committed-choices map
// changes when you descend into an opinion, jump up the breadcrumb path, or
// deep-link onto a proposition. Kept free of React so it's unit-testable in
// isolation (see levelNav.test.ts); useLevelNavigation wraps it with state.
//
// `choices` maps a level key → the chosen proposition id at that level. A level
// key is `-roundId` for a root round position, or the parent proposition id for
// a tree node.

export type Choices = Record<number, number>;

/// Descend into an opinion's thread: commit `propId` as the choice at `key`.
export function descendChoices(
  choices: Choices,
  key: number,
  propId: number,
): Choices {
  return { ...choices, [key]: propId };
}

/// Jump UP the breadcrumb path to crumb `i` (a chain index; -1 = root/home).
/// `committedKeys` is the ordered list of level keys along the committed path
/// (chain[i] was chosen at committedKeys[i]). Keep the choices for levels 0..i
/// and DROP everything deeper — plus any stale off-path keys — so re-descending
/// the same node doesn't auto-jump past where you landed.
export function jumpChoices(
  choices: Choices,
  committedKeys: number[],
  i: number,
): Choices {
  const keep = new Set(committedKeys.slice(0, i + 1));
  const next: Choices = {};
  for (const k of Object.keys(choices)) {
    const nk = Number(k);
    if (keep.has(nk)) next[nk] = choices[nk];
  }
  return next;
}

/// Deep-link: pre-commit the root→target path so the walk descends onto the
/// target proposition. `path` is ordered root-first; each entry's proposition is
/// the choice at the previous entry's node (and the first at its round's root).
export function pathChoices(
  choices: Choices,
  path: { round_id: number; proposition_id: number }[],
): Choices {
  if (path.length === 0) return choices;
  const next = { ...choices };
  next[-path[0].round_id] = path[0].proposition_id;
  for (let i = 0; i < path.length - 1; i++)
    next[path[i].proposition_id] = path[i + 1].proposition_id;
  return next;
}
