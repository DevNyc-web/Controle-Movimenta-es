import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { StatusBadge } from "@/components/StatusBadge";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import ExcelJS from "exceljs";
import { FileSpreadsheet } from "lucide-react";
import { POSTOS_FALTA } from "@/lib/postos";

export const Route = createFileRoute("/_app/relatorios")({
  component: Relatorios,
});

const CARGOS = ["", "Vigilante", "Porteiro", "ASG", "Recepcionista", "Manutencista", "Freelancer"];

function Relatorios() {
  const today = new Date();
  const first = new Date(today.getFullYear(), today.getMonth(), 1);
  const last = new Date(today.getFullYear(), today.getMonth() + 1, 0);

  const [start, setStart] = useState(first.toISOString().split("T")[0]);
  const [end, setEnd] = useState(last.toISOString().split("T")[0]);
  const [nome, setNome] = useState("");
  const [cargo, setCargo] = useState("");
  const [posto, setPosto] = useState("");
  const [raw, setRaw] = useState<any[]>([]);
  const [exporting, setExporting] = useState(false);

  useEffect(() => { load(); }, [start, end]);
  async function load() {
    const { data } = await supabase
      .from("ft")
      .select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, re, setor, cargo), funcionario_faltante:funcionarios!ft_funcionario_faltante_id_fkey(nome, re)")
      .gte("data_ft", start)
      .lte("data_ft", end)
      .order("data_ft");
    setRaw(data ?? []);
  }

  const items = useMemo(() => raw.filter((i) => {
    if (nome && !(i.funcionario?.nome ?? "").toLowerCase().includes(nome.toLowerCase())) return false;
    if (cargo && i.funcionario?.cargo !== cargo) return false;
    if (posto && i.posto_falta !== posto) return false;
    return true;
  }), [raw, nome, cargo, posto]);

  const totals = items.reduce(
    (acc, i) => {
      acc.total++;
      acc.horas += Number(i.horas_trabalhadas);
      acc.valor += Number(i.valor_pago ?? 0);
      acc[i.status] = (acc[i.status] ?? 0) + 1;
      return acc;
    },
    { total: 0, horas: 0, valor: 0, PENDENTE: 0, APROVADA: 0, NEGADA: 0, CANCELADA: 0 } as any
  );

  async function exportExcel() {
    setExporting(true);
    try {
      const wb = new ExcelJS.Workbook();
      wb.creator = "Movimentação Operacional";
      wb.created = new Date();
      const ws = wb.addWorksheet("Relatório", { views: [{ state: "frozen", ySplit: 6 }] });

      const periodLabel = `${format(new Date(start + "T00:00:00"), "dd/MM/yyyy")} a ${format(new Date(end + "T00:00:00"), "dd/MM/yyyy")}`;

      ws.mergeCells("A1:J1");
      const title = ws.getCell("A1");
      title.value = "MOVIMENTAÇÃO OPERACIONAL";
      title.font = { name: "Calibri", size: 18, bold: true, color: { argb: "FFFFFFFF" } };
      title.alignment = { horizontal: "center", vertical: "middle" };
      title.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF3D3022" } };
      ws.getRow(1).height = 36;

      ws.mergeCells("A2:J2");
      const sub = ws.getCell("A2");
      sub.value = `Relatório Gerencial — Período: ${periodLabel}`;
      sub.font = { name: "Calibri", size: 11, italic: true, color: { argb: "FF6B5B45" } };
      sub.alignment = { horizontal: "center" };
      sub.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFE6D6" } };
      ws.getRow(2).height = 22;

      ws.mergeCells("A3:J3");
      const gen = ws.getCell("A3");
      gen.value = `Emitido em ${format(new Date(), "dd 'de' MMMM 'de' yyyy 'às' HH:mm", { locale: ptBR })}`;
      gen.font = { name: "Calibri", size: 9, color: { argb: "FF999999" } };
      gen.alignment = { horizontal: "right" };

      ws.mergeCells("A5:J5");
      const sumTitle = ws.getCell("A5");
      sumTitle.value = `Total: ${totals.total}   |   Aprovadas: ${totals.APROVADA}   |   Pendentes: ${totals.PENDENTE}   |   Negadas/Canceladas: ${totals.NEGADA + totals.CANCELADA}   |   Horas trabalhadas: ${totals.horas}h   |   Valor total: R$ ${totals.valor.toFixed(2)}`;
      sumTitle.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FF3D3022" } };
      sumTitle.alignment = { horizontal: "center", vertical: "middle" };
      sumTitle.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF7F1E5" } };
      ws.getRow(5).height = 24;

      const headers = ["Data", "Colaborador", "RE", "Cargo", "Funcionário faltante", "Posto da falta", "Escala", "Horas Trab.", "Valor (R$)", "Status"];
      const headerRow = ws.getRow(6);
      headers.forEach((h, idx) => {
        const cell = headerRow.getCell(idx + 1);
        cell.value = h;
        cell.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FFFFFFFF" } };
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF6B5B45" } };
        cell.alignment = { horizontal: "center", vertical: "middle" };
        cell.border = {
          top: { style: "thin", color: { argb: "FF3D3022" } },
          bottom: { style: "thin", color: { argb: "FF3D3022" } },
          left: { style: "thin", color: { argb: "FF3D3022" } },
          right: { style: "thin", color: { argb: "FF3D3022" } },
        };
      });
      headerRow.height = 28;

      items.forEach((i, idx) => {
        const row = ws.addRow([
          format(new Date(i.data_ft + "T00:00:00"), "dd/MM/yyyy"),
          i.funcionario?.nome ?? "—",
          i.funcionario?.re ?? "—",
          i.funcionario?.cargo ?? "—",
          i.funcionario_faltante?.nome ?? "—",
          i.posto_falta ?? "—",
          i.escala_servico ?? i.tipo_folga ?? "—",
          Number(i.horas_trabalhadas),
          Number(i.valor_pago ?? 0),
          i.status,
        ]);
        const isOdd = idx % 2 === 1;
        row.eachCell((cell, col) => {
          cell.font = { name: "Calibri", size: 10 };
          cell.alignment = { vertical: "middle", horizontal: col === 2 || col === 5 || col === 6 ? "left" : "center", wrapText: true };
          cell.border = {
            top: { style: "hair", color: { argb: "FFE5DDC9" } },
            bottom: { style: "hair", color: { argb: "FFE5DDC9" } },
            left: { style: "hair", color: { argb: "FFE5DDC9" } },
            right: { style: "hair", color: { argb: "FFE5DDC9" } },
          };
          if (isOdd) cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFAF6EE" } };
          if (col === 8) cell.numFmt = '0.0" h"';
          if (col === 9) cell.numFmt = '"R$ "#,##0.00';
        });

        const statusColors: Record<string, string> = { APROVADA: "FF1B7A4D", PENDENTE: "FFB07A1A", NEGADA: "FFB23A48", CANCELADA: "FF6B5B45" };
        const statusBg: Record<string, string> = { APROVADA: "FFD9F0E3", PENDENTE: "FFFCEFD0", NEGADA: "FFF7DAD9", CANCELADA: "FFE8E2D5" };
        const statusCell = row.getCell(10);
        statusCell.font = { name: "Calibri", size: 9, bold: true, color: { argb: statusColors[i.status] ?? "FF333333" } };
        statusCell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: statusBg[i.status] ?? "FFEEEEEE" } };
        statusCell.alignment = { horizontal: "center", vertical: "middle" };
      });

      if (items.length) {
        const totRow = ws.addRow(["", "", "", "", "", "", "TOTAIS", totals.horas, totals.valor, `${totals.total} reg.`]);
        totRow.eachCell((cell) => {
          cell.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FFFFFFFF" } };
          cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF3D3022" } };
          cell.alignment = { horizontal: "center", vertical: "middle" };
          cell.border = { top: { style: "medium", color: { argb: "FF3D3022" } } };
        });
        totRow.getCell(8).numFmt = '0.0" h"';
        totRow.getCell(9).numFmt = '"R$ "#,##0.00';
        totRow.height = 24;
      }

      const widths = [12, 32, 10, 16, 26, 22, 12, 13, 14, 14];
      widths.forEach((w, i) => (ws.getColumn(i + 1).width = w));

      ws.addRow([]);
      const footRow = ws.addRow([`Documento gerado automaticamente pelo sistema Movimentação Operacional`]);
      ws.mergeCells(`A${footRow.number}:J${footRow.number}`);
      footRow.getCell(1).font = { name: "Calibri", size: 9, italic: true, color: { argb: "FF999999" } };
      footRow.getCell(1).alignment = { horizontal: "center" };

      ws.pageSetup = {
        orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0,
        margins: { left: 0.4, right: 0.4, top: 0.5, bottom: 0.5, header: 0.3, footer: 0.3 },
      };
      ws.headerFooter.oddFooter = "&CMovimentação Operacional — Página &P de &N";

      const buf = await wb.xlsx.writeBuffer();
      const blob = new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `movimentacao_operacional_${start}_${end}.xlsx`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Relatórios</h1>
        <p className="text-muted-foreground mt-1">Consolidado de Movimentações Operacionais por período.</p>
      </div>

      <div className="bg-card border border-border rounded-3xl p-6 flex flex-wrap items-end gap-5">
        <div>
          <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Início</label>
          <input type="date" value={start} onChange={(e) => setStart(e.target.value)} className="mt-2 px-4 py-2.5 bg-muted border border-border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
        </div>
        <div>
          <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Fim</label>
          <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="mt-2 px-4 py-2.5 bg-muted border border-border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
        </div>
        <div>
          <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Nome</label>
          <input type="text" value={nome} onChange={(e) => setNome(e.target.value)} placeholder="buscar..." className="mt-2 px-4 py-2.5 bg-muted border border-border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
        </div>
        <div>
          <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Cargo</label>
          <select value={cargo} onChange={(e) => setCargo(e.target.value)} className="mt-2 px-4 py-2.5 bg-muted border border-border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-ring">
            {CARGOS.map((c) => <option key={c} value={c}>{c || "Todos"}</option>)}
          </select>
        </div>
        <div className="min-w-[200px] flex-1">
          <label className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Posto da falta</label>
          <select value={posto} onChange={(e) => setPosto(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-muted border border-border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-ring">
            <option value="">Todos</option>
            {POSTOS_FALTA.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        </div>
        <button onClick={exportExcel} disabled={exporting || items.length === 0} className="ml-auto inline-flex items-center gap-2 px-5 py-2.5 bg-primary text-primary-foreground rounded-xl text-sm font-medium hover:opacity-90 disabled:opacity-50">
          <FileSpreadsheet className="size-4" />
          {exporting ? "Gerando..." : "Exportar Excel"}
        </button>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Stat label="Total" value={totals.total} />
        <Stat label="Horas trab." value={`${totals.horas}h`} />
        <Stat label="Valor total" value={`R$ ${totals.valor.toFixed(2)}`} />
        <Stat label="Aprovadas" value={totals.APROVADA} />
        <Stat label="Pendentes" value={totals.PENDENTE} />
      </div>

      <div className="bg-card border border-border rounded-3xl overflow-hidden">
        {items.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhuma movimentação no período.</div>
        ) : (
          <table className="w-full text-left">
            <thead>
              <tr className="table-head-row">
                <Th>Data</Th><Th>Colaborador</Th><Th>Cargo</Th><Th>Funcionário faltante</Th><Th>Posto</Th><Th>Horas</Th><Th>Valor</Th><Th>Status</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {items.map((i) => (
                <tr key={i.id}>
                  <td className="px-6 py-4 text-sm tabular-nums">{format(new Date(i.data_ft + "T00:00:00"), "dd/MM/yy")}</td>
                  <td className="px-6 py-4 text-sm font-medium">{i.funcionario?.nome}</td>
                  <td className="px-6 py-4 text-sm">{i.funcionario?.cargo ?? "—"}</td>
                  <td className="px-6 py-4 text-sm">{i.funcionario_faltante?.nome ?? "—"}</td>
                  <td className="px-6 py-4 text-sm max-w-[180px] truncate" title={i.posto_falta ?? ""}>{i.posto_falta ?? "—"}</td>
                  <td className="px-6 py-4 text-sm tabular-nums">{i.horas_trabalhadas}h</td>
                  <td className="px-6 py-4 text-sm tabular-nums">R$ {Number(i.valor_pago ?? 0).toFixed(2)}</td>
                  <td className="px-6 py-4"><StatusBadge status={i.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-card border border-border p-5 rounded-2xl">
      <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">{label}</p>
      <p className="text-2xl font-light tabular-nums mt-2">{value}</p>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-6 py-4 text-[10px] font-bold text-muted-foreground uppercase tracking-widest">{children}</th>;
}
