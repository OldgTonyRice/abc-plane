"use client";

import { useSearchParams, usePathname, useRouter } from "next/navigation";
import { useState, useEffect, useRef } from "react";

export default function SearchInput({ placeholder = "Search issues…" }: { placeholder?: string }) {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const { replace } = useRouter();

  const initial = searchParams.get("search") ?? "";
  const [value, setValue] = useState(initial);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => setValue(initial), [initial]);

  // debounce thủ công 250ms
  const updateURL = (next: string) => {
    const params = new URLSearchParams(searchParams);
    if (next) params.set("search", next);
    else params.delete("search");
    params.delete("page"); // reset page khi gõ search
    replace(`${pathname}?${params.toString()}`);
  };

  useEffect(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => updateURL(value), 250);
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, [value]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="relative min-w-[260px]">
      <input
        className="w-full rounded-xl border border-neutral-200 bg-white/60 dark:bg-neutral-900/60 px-3 py-2
                   outline-none focus:ring-2 ring-offset-0 ring-neutral-300 dark:ring-neutral-700"
        placeholder={placeholder}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        aria-label="Search issues"
      />
      <svg className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 opacity-60" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd"
          d="M12.9 14.32a8 8 0 111.414-1.414l3.386 3.386a1 1 0 01-1.414 1.414l-3.386-3.386zM14 8a6 6 0 11-12 0 6 6 0 0112 0z"
          clipRule="evenodd" />
      </svg>
    </div>
  );
}
