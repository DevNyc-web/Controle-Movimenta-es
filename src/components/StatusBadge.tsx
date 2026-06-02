import { cn } from "@/lib/utils";

const styles = {
  PENDENTE: "bg-amber-500/15 text-amber-300 border-amber-500/35",
  APROVADA: "bg-emerald-500/15 text-emerald-300 border-emerald-500/35",
  NEGADA: "bg-rose-500/15 text-rose-300 border-rose-500/35",
  CANCELADA: "bg-muted text-muted-foreground border-border",
} as const;

export function StatusBadge({ status, className }: { status: keyof typeof styles; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase tracking-wider border",
        styles[status],
        className
      )}
    >
      {status}
    </span>
  );
}
