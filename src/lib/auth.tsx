import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

export type Role = "gestor" | "apontamento" | "supervisor";

interface AuthContextValue {
  user: User | null;
  session: Session | null;
  username: string | null;
  roles: Role[];
  role: Role | null;
  loading: boolean;
  isGestor: boolean;
  isSupervisor: boolean;
  isApontamento: boolean;
  signIn: (username: string, password: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export const INTERNAL_EMAIL_DOMAIN = "interno.local";
export const usernameToEmail = (u: string) => {
  const normalized = u.trim().toLowerCase();
  return normalized.includes("@") ? normalized : `${normalized}@${INTERNAL_EMAIL_DOMAIN}`;
};

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [roles, setRoles] = useState<Role[]>([]);
  const [username, setUsername] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;

    async function applySession(sess: Session | null) {
      if (!mounted) return;
      setSession(sess);
      setUser(sess?.user ?? null);
      if (sess?.user) await loadProfile(sess.user.id);
      else {
        setRoles([]);
        setUsername(null);
      }
      if (mounted) setLoading(false);
    }

    const { data: sub } = supabase.auth.onAuthStateChange((_event, sess) => {
      setLoading(true);
      setTimeout(() => applySession(sess), 0);
    });

    supabase.auth.getSession().then(({ data }) => {
      applySession(data.session);
    });

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  async function loadProfile(userId: string) {
    const [{ data: rolesData }, { data: profileData }] = await Promise.all([
      supabase.from("user_roles").select("role").eq("user_id", userId),
      supabase.from("profiles").select("username, ativo").eq("id", userId).maybeSingle(),
    ]);
    if (profileData && (profileData as any).ativo === false) {
      await supabase.auth.signOut();
      return;
    }
    setRoles((rolesData ?? []).map((r) => r.role as Role));
    setUsername((profileData as any)?.username ?? null);
  }

  const signIn = async (uname: string, password: string) => {
    const email = usernameToEmail(uname);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error };
  };

  const signOut = async () => { await supabase.auth.signOut(); };

  const role: Role | null = roles[0] ?? null;
  const isGestor = roles.includes("gestor");
  const isSupervisor = roles.includes("supervisor");
  const isApontamento = roles.includes("apontamento");

  return (
    <AuthContext.Provider value={{ user, session, username, roles, role, loading, isGestor, isSupervisor, isApontamento, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}
