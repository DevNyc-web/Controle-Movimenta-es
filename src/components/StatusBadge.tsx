import { cn } from "@/lib/utils";

const styles = {
  PENDENTE: "bg-amber-50 text-amber-700 border-amber-200",
  APROVADA: "bg-emerald-50 text-emerald-700 border-emerald-200",
  NEGADA: "bg-rose-50 text-rose-700 border-rose-200",
  CANCELADA: "bg-stone-100 text-stone-600 border-stone-200",
  CANCELAMENTO_SOLICITADO: "bg-orange-50 text-orange-700 border-orange-200",
} as const;

const labels: Record<keyof typeof styles, string> = {
  PENDENTE: "Pendente",
  APROVADA: "Aprovada",
  NEGADA: "Negada",
  CANCELADA: "Cancelada",
  CANCELAMENTO_SOLICITADO: "Cancelamento solicitado",
};

export function StatusBadge({ status, className }: { status: keyof typeof styles; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase tracking-wider border",
        styles[status],
        className
      )}
    >
      {labels[status]}
    </span>
  );
}
