import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import ExcelJS from "exceljs";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { toast } from "sonner";
import { Upload, ArrowLeft, CheckCircle2, AlertTriangle } from "lucide-react";
import { normalizarEmpresa } from "@/lib/empresas";
import { abasDoWorkbook, cargoReconhecido, celulaTexto, detectarColunas, extrairLinhas } from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/funcionarios/importar")({
  component: ImportarFuncionarios,
});

type Row = {
  nome: string;
  re: string;
  cargo: string;
  cargo_original: string;
  empresa_origem: string;
  empresa: string | null;
  turno: string;
  cpf: string | null;
  data_admissao: string | null;
  status_ativo: boolean;
  status: string;
  usa_banco_horas: boolean;
};

function ImportarFuncionarios() {
  const { isGestor } = useAuth();
  const navigate = useNavigate();
  const [rows, setRows] = useState<Row[]>([]);
  const [errors, setErrors] = useState<string[]>([]);
  const [fileName, setFileName] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ inserted: number; failed: number } | null>(null);

  if (!isGestor) {
    return <div className="text-sm text-muted-foreground">Apenas Gestores podem importar funcionários.</div>;
  }

  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setFileName(file.name);
    setResult(null);
    setErrors([]);
    setRows([]);

    try {
      const buf = await file.arrayBuffer();
      const wb = new ExcelJS.Workbook();
      await wb.xlsx.load(buf);
      const collected: Row[] = [];
      const errs: string[] = [];

      for (const aba of abasDoWorkbook(wb)) {
        const d = detectarColunas(aba.matriz);
        if (d.linhaCabecalho < 0 || d.colunas.re === undefined || d.colunas.cargo === undefined) {
          errs.push(`Aba "${aba.nome}": não foi possível localizar a linha de cabeçalho (Nome/Código/Cargo).`);
          continue;
        }
        // empresa pode estar na primeira(s) linha(s) (cabeçalho do relatório)
        const empresaHeader = aba.matriz.slice(0, 3).map((l) => celulaTexto(l?.[0])).find((v) => v.length > 3) ?? "";
        const { linhas, ignoradas } = extrairLinhas(aba.matriz, d.linhaCabecalho, d.colunas, aba.nome);
        if (ignoradas.length > 0) errs.push(`Aba "${aba.nome}": ${ignoradas.length} linha(s) ignorada(s) (cabeçalhos repetidos, totais ou títulos).`);

        for (const l of linhas) {
          if (!l.nome || !l.re) {
            errs.push(`Linha ${l.origem}: sem nome ou código; não importada.`);
            continue;
          }
          const cargo = cargoReconhecido(l.cargo);
          if (!cargo) {
            errs.push(`Linha ${l.origem}: cargo "${l.cargo}" não reconhecido; não importada.`);
            continue;
          }
          const empresa = l.empresa || empresaHeader || aba.nome;
          collected.push({
            nome: l.nome,
            re: l.re,
            cargo,
            cargo_original: l.cargo,
            empresa_origem: empresa || cargo,
            empresa: normalizarEmpresa(empresa), // só grava empresa reconhecida; senão fica vazia para revisão
            turno: "Integral",
            cpf: l.cpf || null,
            data_admissao: l.admissao,
            status_ativo: true,
            status: "ativo",
            usa_banco_horas: false,
          });
        }
      }

      setRows(collected);
      setErrors(errs);
      if (collected.length === 0) toast.error("Nenhuma linha válida encontrada.");
      else toast.success(`${collected.length} linhas prontas para importar.`);
    } catch (err: any) {
      toast.error("Falha ao ler XLSX: " + err.message);
    }
  }

  async function handleImport() {
    if (rows.length === 0) return;
    setLoading(true);
    setResult(null);

    const BATCH = 100;
    let inserted = 0;
    let failed = 0;
    const failMsgs: string[] = [];

    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH).map(({ cargo_original, empresa_origem, ...rest }) => rest);
      const { error, count } = await supabase.from("funcionarios").insert(chunk, { count: "exact" });
      if (error) {
        failed += chunk.length;
        failMsgs.push(`Lote ${i / BATCH + 1}: ${error.message}`);
      } else {
        inserted += count ?? chunk.length;
      }
    }

    setLoading(false);
    setResult({ inserted, failed });
    if (failMsgs.length) setErrors((prev) => [...prev, ...failMsgs]);
    if (failed === 0) toast.success(`${inserted} funcionários importados.`);
    else toast.warning(`${inserted} importados, ${failed} falharam.`);
  }

  return (
    <div className="space-y-8 max-w-5xl">
      <div className="flex items-center justify-between">
        <div>
          <Link to="/funcionarios" className="text-xs text-oak-dark/60 hover:underline inline-flex items-center gap-1">
            <ArrowLeft className="size-3" /> Voltar
          </Link>
          <h1 className="text-3xl font-light tracking-tight mt-2">Importar funcionários</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            Envie planilhas XLSX. Colunas esperadas: <strong>Nome</strong>, <strong>Código</strong> (RE), <strong>Cargo</strong>, e opcionalmente CPF, Data Admissão, Empresa.
          </p>
        </div>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-8 space-y-6">
        <div>
          <label className="block">
            <div className="border-2 border-dashed border-oak-medium rounded-2xl p-10 text-center cursor-pointer hover:bg-sand/30 transition">
              <Upload className="size-8 mx-auto text-oak-dark/60" />
              <div className="mt-3 text-sm font-medium">Clique para selecionar arquivo XLSX</div>
              <div className="text-xs text-oak-dark/50 mt-1">{fileName || "Nenhum arquivo selecionado"}</div>
            </div>
            <input type="file" accept=".xlsx" onChange={handleFile} className="hidden" />
          </label>
        </div>

        <div className="bg-sand/40 rounded-xl p-4 text-xs space-y-1">
          <div className="font-semibold uppercase tracking-widest text-[10px] text-oak-dark/60">Regras de mapeamento</div>
          <div>• Vigilante → <strong>Vigilante</strong></div>
          <div>• Limpeza, Zelador, Serviços Gerais → <strong>ASG</strong></div>
          <div>• Portaria, Porteiro, Vigia, Controlador de Acesso, Monitoramento, Bombeiro, Inspetor, Vistoria → <strong>Porteiro</strong></div>
          <div>• Recepcionista → <strong>Recepcionista</strong></div>
          <div>• Manutenção, Instalador, Técnico → <strong>Manutencista</strong></div>
          <div>• Cargo não reconhecido: a linha <strong>não é importada</strong> e aparece nos avisos.</div>
          <div>• Turno: <strong>Integral</strong> (padrão). RE duplicado entre empresas é permitido.</div>
        </div>

        {rows.length > 0 && (
          <>
            <div className="flex flex-col gap-4 border-t border-oak-light pt-6 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="text-2xl font-light">{rows.length}</div>
                <div className="text-xs text-oak-dark/60 uppercase tracking-widest">linhas prontas</div>
              </div>
              <button
                onClick={handleImport}
                disabled={loading}
                className="w-full sm:w-auto px-6 py-3 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl hover:opacity-90 disabled:opacity-50"
              >
                {loading ? "Importando..." : `Importar ${rows.length} funcionários`}
              </button>
            </div>

            <div className="max-h-96 overflow-auto border border-oak-light rounded-xl">
              <table className="w-full text-xs">
                <thead className="bg-sand/50 sticky top-0">
                  <tr>
                    <th className="px-3 py-2 text-left">Nome</th>
                    <th className="px-3 py-2 text-left">RE</th>
                    <th className="px-3 py-2 text-left">Cargo original</th>
                    <th className="px-3 py-2 text-left">Cargo mapeado</th>
                    <th className="px-3 py-2 text-left">Empresa (planilha)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-oak-light">
                  {rows.slice(0, 200).map((r, i) => (
                    <tr key={i}>
                      <td className="px-3 py-1.5">{r.nome}</td>
                      <td className="px-3 py-1.5 tabular-nums">{r.re}</td>
                      <td className="px-3 py-1.5 text-oak-dark/60">{r.cargo_original}</td>
                      <td className="px-3 py-1.5 font-medium">{r.cargo}</td>
                      <td className="px-3 py-1.5 text-oak-dark/60">{r.empresa ?? <span className="text-amber-700">não reconhecida ({r.empresa_origem}) — ficará vazia</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {rows.length > 200 && (
                <div className="p-2 text-center text-xs text-oak-dark/50">Mostrando 200 de {rows.length}.</div>
              )}
            </div>
          </>
        )}

        {result && (
          <div className="border-t border-oak-light pt-6 flex flex-col gap-3 text-sm sm:flex-row sm:items-center">
            <CheckCircle2 className="size-5 text-emerald-600" />
            <span><strong>{result.inserted}</strong> inseridos. <strong>{result.failed}</strong> falharam.</span>
            <button onClick={() => navigate({ to: "/funcionarios" })} className="w-full sm:w-auto sm:ml-auto px-4 py-2 bg-oak-medium/30 rounded-xl text-xs font-medium">
              Ver funcionários
            </button>
          </div>
        )}

        {errors.length > 0 && (
          <div className="border-t border-oak-light pt-6">
            <div className="flex items-center gap-2 text-sm font-medium text-amber-700">
              <AlertTriangle className="size-4" /> {errors.length} aviso(s)
            </div>
            <ul className="mt-2 space-y-1 text-xs text-amber-800 max-h-40 overflow-auto">
              {errors.slice(0, 50).map((e, i) => <li key={i}>• {e}</li>)}
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}
