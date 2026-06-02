import { Outlet, createRootRoute, HeadContent, Scripts } from "@tanstack/react-router";
import { SetupRequired } from "@/components/SetupRequired";
import { AuthProvider } from "@/lib/auth";
import { isSupabaseConfigured } from "@/lib/env";
import { Toaster } from "@/components/ui/sonner";
import appCss from "../styles.css?url";

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Movimentação Operacional" },
      { name: "description", content: "Sistema corporativo de Movimentação Operacional para RH e gestores." },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" },
      { rel: "stylesheet", href: "https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" },
    ],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: () => (
    <div className="flex min-h-dvh items-center justify-center bg-background px-4">
      <div className="text-center">
        <h1 className="text-7xl font-light text-primary">404</h1>
        <p className="mt-4 text-muted-foreground">Página não encontrada.</p>
        <a href="/" className="mt-6 inline-flex rounded-xl bg-primary px-5 py-2.5 text-sm text-primary-foreground">Voltar</a>
      </div>
    </div>
  ),
});

function RootShell({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className="dark">
      <head><HeadContent /></head>
      <body className="min-h-dvh antialiased">{children}<Scripts /></body>
    </html>
  );
}

function RootComponent() {
  if (!isSupabaseConfigured()) {
    return (
      <>
        <SetupRequired />
        <Toaster />
      </>
    );
  }

  return (
    <AuthProvider>
      <Outlet />
      <Toaster />
    </AuthProvider>
  );
}
