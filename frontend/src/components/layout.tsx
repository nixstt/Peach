import type { ReactNode } from "react";

export function Layout({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto flex min-h-screen max-w-5xl flex-col gap-8 p-6">{children}</div>
  );
}
