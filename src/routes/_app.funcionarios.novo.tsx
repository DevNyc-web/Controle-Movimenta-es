import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { FuncionarioForm } from "@/components/FuncionarioForm";

export const Route = createFileRoute("/_app/funcionarios/novo")({
  component: NovoFuncionario,
});

function NovoFuncionario() {
  const navigate = useNavigate();
  return (
    <div className="space-y-8 max-w-3xl">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Novo Funcionário</h1>
        <p className="text-muted-foreground mt-1">Cadastre um novo colaborador.</p>
      </div>
      <FuncionarioForm onDone={() => navigate({ to: "/funcionarios" })} />
    </div>
  );
}
