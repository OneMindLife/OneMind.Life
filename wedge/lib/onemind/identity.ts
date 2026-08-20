import { supabase } from "@/lib/supabase/client";

// A friendly anonymous display name (adjective + animal), e.g. "Bright Seal".
// Mirrors the Flutter app's RandomNameGenerator in spirit (exact words differ).
const ADJ = [
  "Bright", "Brave", "Calm", "Clever", "Bold", "Gentle", "Swift", "Kind",
  "Lucky", "Merry", "Noble", "Quick", "Sunny", "Wise", "Warm", "Keen",
];
const ANIMAL = [
  "Seal", "Fox", "Owl", "Lark", "Otter", "Hawk", "Wren", "Deer",
  "Crane", "Heron", "Finch", "Bear", "Moose", "Robin", "Swan", "Lynx",
];

export function randomName(): string {
  const a = ADJ[Math.floor(Math.random() * ADJ.length)];
  const b = ANIMAL[Math.floor(Math.random() * ANIMAL.length)];
  return `${a} ${b}`;
}

/// Ensure the anon user has a display name (in auth metadata); returns it.
/// Mirrors AuthService.ensureDisplayName.
export async function ensureDisplayName(): Promise<string> {
  const { data } = await supabase.auth.getUser();
  const existing = data.user?.user_metadata?.display_name as string | undefined;
  if (existing && existing.trim().length > 0) return existing;
  const name = randomName();
  await supabase.auth.updateUser({ data: { display_name: name } });
  return name;
}
