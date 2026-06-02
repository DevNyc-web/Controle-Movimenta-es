import { createFileRoute } from "@tanstack/react-router";
import { useState, useEffect, type FormEvent } from "react";
import { useAuth } from "@/lib/auth";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import logoGrupoMc from "@/assets/logo-grupo-mc.png";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const { signIn } = useAuth();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) window.location.replace("/");
    });
  }, []);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setLoading(true);
    const { error } = await signIn(username, password);
    if (error) {
      setLoading(false);
      toast.error("Usuário ou senha inválidos");
      return;
    }
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      setLoading(false);
      toast.error("Login validado, mas a sessão não foi carregada. Tente novamente.");
      return;
    }
    toast.success("Bem-vindo!");
    // full reload to ensure session is hydrated before protected screens run
    window.location.assign("/");
  };

  return (
    <div className="min-h-dvh flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-10">
          <img src={logoGrupoMc} alt="Grupo MC" className="mx-auto size-20 object-contain mb-4" />
          <h1 className="text-3xl font-light tracking-tight">Movimentação Operacional</h1>
          <p className="text-sm text-muted-foreground mt-2">Acesso restrito</p>
        </div>

        <div className="bg-card border border-border rounded-3xl p-8 shadow-lg">
          <form onSubmit={handleSubmit} className="space-y-5">
            <div>
              <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Usuário</label>
              <input
                type="text"
                required
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="mt-2 w-full px-4 py-3 bg-muted rounded-xl text-sm border border-border focus:outline-none focus:ring-2 focus:ring-ring"
                placeholder="seu usuário"
              />
            </div>
            <div>
              <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Senha</label>
              <input
                type="password"
                required
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-2 w-full px-4 py-3 bg-muted rounded-xl text-sm border border-border focus:outline-none focus:ring-2 focus:ring-ring"
                placeholder="••••••••"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full bg-primary text-primary-foreground py-3 rounded-xl text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {loading ? "Entrando..." : "Entrar"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
