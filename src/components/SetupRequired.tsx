import { SUPABASE_SETUP_MESSAGE } from "@/lib/env";

export function SetupRequired() {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-background px-4">
      <div className="max-w-lg rounded-3xl border border-border bg-card p-8 shadow-lg">
        <h1 className="text-2xl font-light tracking-tight">Configuração necessária</h1>
        <p className="mt-3 text-sm text-muted-foreground">{SUPABASE_SETUP_MESSAGE}</p>
        <ol className="mt-6 list-decimal space-y-2 pl-5 text-sm text-muted-foreground">
          <li>
            Na pasta             <code className="rounded bg-muted px-1">folha-certa-main</code>, copie{" "}
            <code className="rounded bg-muted px-1">.env.example</code> para{" "}
            <code className="rounded bg-muted px-1">.env</code>
          </li>
          <li>Cole a URL e a chave publicável (anon/publishable) do seu projeto Supabase</li>
          <li>Pare o servidor (Ctrl+C) e rode de novo: npm run dev</li>
        </ol>
        <a
          href="/login"
          className="mt-8 inline-flex rounded-xl bg-primary px-5 py-2.5 text-sm text-primary-foreground"
        >
          Ir para login
        </a>
      </div>
    </div>
  );
}

export function AuthLoading() {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-background">
      <p className="text-sm text-muted-foreground">Carregando...</p>
    </div>
  );
}
