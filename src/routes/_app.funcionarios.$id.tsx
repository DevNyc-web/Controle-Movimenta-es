import { createFileRoute, useNavigate, useParams, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { FuncionarioForm } from "@/components/FuncionarioForm";
import { ChevronLeft } from "lucide-react";

export const Route = createFileRoute("/_app/funcionarios/$id")({
  component: EditarFuncionario,
});

function EditarFuncionario() {
  const { id } = useParams({ from: "/_app/funcionarios/$id" });
  const navigate = useNavigate();
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    supabase.from("funcionarios").select("*").eq("id", id).maybeSingle().then(({ data }) => setData(data));
  }, [id]);

  if (!data) return <div className="text-sm text-muted-foreground">Carregando...</div>;

  return (
    <div className="space-y-8 max-w-3xl">
      <Link to="/funcionarios" className="inline-flex items-center gap-1 text-xs text-oak-dark hover:underline">
        <ChevronLeft className="size-3" /> Voltar
      </Link>
      <div>
        <h1 className="text-3xl font-light tracking-tight">{data.nome}</h1>
        <p className="text-muted-foreground mt-1">Editar dados do colaborador.</p>
      </div>
      <FuncionarioForm initial={data} onDone={() => navigate({ to: "/funcionarios" })} />
    </div>
  );
}
