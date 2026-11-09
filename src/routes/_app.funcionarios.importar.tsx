import { createFileRoute, redirect } from "@tanstack/react-router";

// O importador direto (sem revisão) foi substituído pela Importação oficial, que propõe e só aplica com aprovação do Gestor.
export const Route = createFileRoute("/_app/funcionarios/importar")({
  beforeLoad: () => {
    throw redirect({ to: "/conferencia" });
  },
});
