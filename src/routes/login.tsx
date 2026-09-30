import { createFileRoute } from "@tanstack/react-router";
import { useState, useEffect, type FormEvent } from "react";
import { useAuth } from "@/lib/auth";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Eye, EyeOff, Loader2 } from "lucide-react";
import logoOficial from "@/assets/logo-grupo-mc-oficial.png";
import fachada from "@/assets/fachada.jpg";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const { signIn } = useAuth();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) window.location.replace("/");
    });
  }, []);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    const { error: signInError } = await signIn(username, password);
    if (signInError) {
      setLoading(false);
      setError("Usuário ou senha inválidos");
      toast.error("Usuário ou senha inválidos");
      return;
    }
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      setLoading(false);
      setError("Sessão não carregada. Tente novamente.");
      toast.error("Login validado, mas a sessão não foi carregada. Tente novamente.");
      return;
    }
    toast.success("Bem-vindo!");
    window.location.assign("/");
  };

  return (
    <div className="min-h-dvh flex flex-col md:flex-row">

      {/* ── Painel de marca ──────────────────────────────────── */}
      <div className="relative md:w-[48%] flex flex-col items-center justify-center shrink-0 overflow-hidden min-h-52 md:min-h-dvh">

        {/* Fachada como background */}
        <img
          src={fachada}
          alt=""
          aria-hidden="true"
          className="absolute inset-0 w-full h-full object-cover object-center"
        />

        {/* Overlay gradiente para legibilidade */}
        <div className="absolute inset-0 bg-gradient-to-b from-black/70 via-black/50 to-black/80" />

        {/* Conteúdo */}
        <div className="relative z-10 flex flex-col items-center justify-center gap-5 px-10 py-14 text-center w-full h-full">
          <img
            src={logoOficial}
            alt="Grupo MC"
            className="w-28 md:w-36 object-contain drop-shadow-2xl"
          />
          <div className="space-y-1">
            <h2 className="text-white text-2xl md:text-3xl font-semibold tracking-tight drop-shadow">
              Grupo MC
            </h2>
            <p className="text-white/70 text-sm md:text-base font-light tracking-wide">
              Segurança e Serviços
            </p>
          </div>

          <div className="flex items-center gap-3 mt-1">
            <div className="h-px w-10 bg-white/25" />
            <span className="text-white/45 text-[10px] tracking-widest uppercase">
              Gestão de Movimentações
            </span>
            <div className="h-px w-10 bg-white/25" />
          </div>
        </div>

        <p className="absolute bottom-5 left-0 right-0 text-center text-white/25 text-[10px] tracking-widest uppercase z-10">
          Grupo MC © {new Date().getFullYear()}
        </p>
      </div>

      {/* ── Painel do formulário ─────────────────────────────── */}
      <div className="flex-1 flex items-center justify-center bg-canvas px-6 py-16 md:px-16">
        <div className="w-full max-w-sm space-y-10">

          <div>
            <p className="text-[10px] font-bold text-oak-dark/40 uppercase tracking-widest mb-3">
              Acesso corporativo
            </p>
            <h1 className="text-[2rem] font-light tracking-tight leading-none">
              Faça seu login
            </h1>
            <p className="text-sm text-muted-foreground mt-2">
              Informe suas credenciais para continuar
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">

            <div className="space-y-1.5">
              <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">
                Usuário
              </label>
              <input
                type="text"
                required
                autoComplete="username"
                autoFocus
                value={username}
                onChange={(e) => { setUsername(e.target.value); setError(""); }}
                className="w-full px-4 py-3.5 bg-sand rounded-2xl text-sm border border-transparent focus:outline-none focus:border-oak-medium focus:ring-2 focus:ring-oak-dark/10 transition-all placeholder:text-oak-dark/30"
                placeholder="seu usuário"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">
                Senha
              </label>
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  required
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => { setPassword(e.target.value); setError(""); }}
                  className="w-full px-4 py-3.5 pr-12 bg-sand rounded-2xl text-sm border border-transparent focus:outline-none focus:border-oak-medium focus:ring-2 focus:ring-oak-dark/10 transition-all placeholder:text-oak-dark/30"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  tabIndex={-1}
                  onClick={() => setShowPassword((v) => !v)}
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-oak-dark/35 hover:text-oak-dark/65 transition-colors"
                >
                  {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                </button>
              </div>
            </div>

            {error && (
              <p className="text-xs text-rose-700 bg-rose-50 border border-rose-100 px-4 py-3 rounded-xl leading-relaxed">
                {error}
              </p>
            )}

            <button
              type="submit"
              disabled={loading || !username || !password}
              className="w-full flex items-center justify-center gap-2 bg-oak-dark text-primary-foreground py-3.5 rounded-2xl text-sm font-medium hover:opacity-90 active:scale-[0.99] transition-all disabled:opacity-40 disabled:cursor-not-allowed mt-2"
            >
              {loading ? (
                <>
                  <Loader2 className="size-4 animate-spin" />
                  Verificando...
                </>
              ) : (
                "Entrar"
              )}
            </button>

          </form>

        </div>
      </div>

    </div>
  );
}
