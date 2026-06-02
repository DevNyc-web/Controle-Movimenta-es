import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { AppLayout } from "@/components/AppLayout";
import { AuthLoading, SetupRequired } from "@/components/SetupRequired";
import { isSupabaseConfigured } from "@/lib/env";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_app")({
  component: AppGuard,
});

function AppGuard() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!isSupabaseConfigured()) return;

    let mounted = true;
    supabase.auth
      .getSession()
      .then(({ data }) => {
        if (!mounted) return;
        if (!data.session) {
          window.location.replace("/login");
        } else {
          setReady(true);
        }
      })
      .catch(() => {
        if (mounted) window.location.replace("/login");
      });

    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") window.location.replace("/login");
    });
    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  if (!isSupabaseConfigured()) return <SetupRequired />;
  if (!ready) return <AuthLoading />;
  return <AppLayout />;
}
