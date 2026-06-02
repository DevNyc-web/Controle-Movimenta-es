const PLACEHOLDER_MARKERS = ["SEU_PROJECT", "sb_publishable_...", "sb_secret_..."];

function envValue(key: string): string | undefined {
  const v = import.meta.env[key];
  return typeof v === "string" && v.trim() !== "" ? v.trim() : undefined;
}

export function getPublicSupabaseEnv() {
  return {
    url: envValue("VITE_SUPABASE_URL") ?? envValue("SUPABASE_URL"),
    publishableKey:
      envValue("VITE_SUPABASE_PUBLISHABLE_KEY") ?? envValue("SUPABASE_PUBLISHABLE_KEY"),
  };
}

export function isSupabaseConfigured(): boolean {
  const { url, publishableKey } = getPublicSupabaseEnv();
  if (!url || !publishableKey) return false;
  const combined = `${url} ${publishableKey}`;
  return !PLACEHOLDER_MARKERS.some((marker) => combined.includes(marker));
}

export const SUPABASE_SETUP_MESSAGE =
  "Configure o Supabase: copie .env.example para .env e preencha VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY (painel Supabase → Settings → API). Reinicie o servidor (npm run dev).";
