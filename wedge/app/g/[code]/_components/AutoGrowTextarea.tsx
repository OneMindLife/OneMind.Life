"use client";

import { useLayoutEffect, useRef } from "react";
import css from "../TreeChat.module.css";

// Auto-growing composer input: wraps onto multiple lines as you type and grows
// to fit (up to the CSS max-height), then scrolls — so a long take stays
// readable instead of a single horizontally-scrolling line. Enter submits;
// Shift+Enter inserts a newline.
export function AutoGrowTextarea({
  value,
  onChange,
  onSubmit,
  placeholder,
  disabled,
  maxLength,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  onSubmit: () => void;
  placeholder: string;
  disabled?: boolean;
  maxLength?: number;
  autoFocus?: boolean;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);
  // Recompute height whenever the value changes (typing, or cleared after send).
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto"; // shrink first so deletions collapse the field
    el.style.height = `${el.scrollHeight}px`; // grow to content; CSS max-height caps it
  }, [value]);
  // Focus on mount when asked (compose sheet opens straight into typing).
  useLayoutEffect(() => {
    if (autoFocus) ref.current?.focus();
  }, [autoFocus]);
  return (
    <textarea
      ref={ref}
      className={css.composerInput}
      value={value}
      rows={1}
      onChange={(e) => onChange(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          onSubmit();
        }
      }}
      placeholder={placeholder}
      maxLength={maxLength}
      disabled={disabled}
    />
  );
}
