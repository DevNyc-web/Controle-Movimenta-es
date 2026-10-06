import ExcelJS from "exceljs";
import { agruparPorFuncionario, totaisGerais, grupoExcedeu, linhaExcedeu, LABEL_FOLHA, type FtRow } from "./relatorio.ts";

const fmtData = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}`;
const fill = (argb: string) => ({ type: "pattern" as const, pattern: "solid" as const, fgColor: { argb } });
const hair = { style: "hair" as const, color: { argb: "FFE5DDC9" } };
const dark = { style: "thin" as const, color: { argb: "FF3D3022" } };
const STATUS_COLOR: Record<string, string> = { APROVADA: "FF1B7A4D", PENDENTE: "FFB07A1A", NEGADA: "FFB23A48", CANCELADA: "FF6B5B45" };
const STATUS_BG: Record<string, string> = { APROVADA: "FFD9F0E3", PENDENTE: "FFFCEFD0", NEGADA: "FFF7DAD9", CANCELADA: "FFE8E2D5" };
const VERMELHO = "FFC00000"; // limite mensal excedido
const BRL = '"R$ "#,##0.00';
const HRS = '0.0" h"';

/** Planilha agrupada: por funcionário (cabeçalho, FTs, TOTAL do funcionário, linha em branco) + TOTAL GERAL.
 *  `excedidos` = chaves funcionario_id|AAAA-MM com mais de 4 movimentações (ver mesesExcedidos): só muda a cor do nome. */
export function buildWorkbook(items: any[], start: string, end: string, emitidoEm: string, excedidos: ReadonlySet<string> = new Set()): ExcelJS.Workbook {
  const rows = items as FtRow[];
  const totals = totaisGerais(rows);
  const wb = new ExcelJS.Workbook();
  wb.creator = "Movimentação Operacional";
  wb.created = new Date();
  const ws = wb.addWorksheet("Relatório", { views: [{ state: "frozen", ySplit: 6 }] });

  const banner = (ref: string, value: string, style: Partial<ExcelJS.Cell>) => {
    ws.mergeCells(ref);
    Object.assign(ws.getCell(ref.split(":")[0]), { value, ...style });
  };
  banner("A1:J1", "MOVIMENTAÇÃO OPERACIONAL", { font: { name: "Calibri", size: 18, bold: true, color: { argb: "FFFFFFFF" } }, alignment: { horizontal: "center", vertical: "middle" }, fill: fill("FF3D3022") });
  ws.getRow(1).height = 36;
  banner("A2:J2", `Relatório Gerencial — Período: ${fmtData(start)} a ${fmtData(end)}`, { font: { name: "Calibri", size: 11, italic: true, color: { argb: "FF6B5B45" } }, alignment: { horizontal: "center" }, fill: fill("FFEFE6D6") });
  ws.getRow(2).height = 22;
  banner("A3:J3", emitidoEm, { font: { name: "Calibri", size: 9, color: { argb: "FF999999" } }, alignment: { horizontal: "right" } });
  banner(
    "A5:J5",
    `Total: ${totals.total}   |   Aprovadas: ${totals.APROVADA}   |   Pendentes: ${totals.PENDENTE}   |   Negadas/Canceladas: ${totals.NEGADA + totals.CANCELADA}   |   Horas trabalhadas: ${totals.horas}h   |   Valor total: R$ ${totals.valor.toFixed(2)}`,
    { font: { name: "Calibri", size: 10, bold: true, color: { argb: "FF3D3022" } }, alignment: { horizontal: "center", vertical: "middle" }, fill: fill("FFF7F1E5") },
  );
  ws.getRow(5).height = 24;

  const headers = ["Data", "Colaborador", "RE", "Cargo", "Funcionário faltante", "Posto da falta", "Escala", "Horas Trab.", "Valor (R$)", "Status"];
  const headerRow = ws.getRow(6);
  headers.forEach((h, idx) => {
    Object.assign(headerRow.getCell(idx + 1), { value: h, font: { name: "Calibri", size: 10, bold: true, color: { argb: "FFFFFFFF" } }, fill: fill("FF6B5B45"), alignment: { horizontal: "center", vertical: "middle" }, border: { top: dark, bottom: dark, left: dark, right: dark } });
  });
  headerRow.height = 28;

  for (const g of agruparPorFuncionario(rows)) {
    const gr = ws.addRow([`${g.nome}  —  RE ${g.re}`]);
    ws.mergeCells(gr.number, 1, gr.number, 10);
    Object.assign(gr.getCell(1), { font: { name: "Calibri", size: 11, bold: true, color: { argb: grupoExcedeu(g, excedidos) ? VERMELHO : "FF3D3022" } }, fill: fill("FFE5DDC9"), alignment: { horizontal: "left", vertical: "middle" } });
    gr.height = 22;

    g.items.forEach((i: any, idx) => {
      const folha = !!i.pagamento_em_folha;
      const row = ws.addRow([
        fmtData(i.data_ft), i.funcionario?.nome ?? "—", i.funcionario?.re ?? "—", i.funcionario?.cargo ?? "—",
        i.funcionario_faltante?.nome ?? "—", i.posto_falta ?? "—", i.escala_servico ?? i.tipo_folga ?? "—",
        Number(i.horas_trabalhadas), folha ? LABEL_FOLHA : Number(i.valor_pago ?? 0), i.status,
      ]);
      row.eachCell((cell, col) => {
        cell.font = { name: "Calibri", size: 10 };
        cell.alignment = { vertical: "middle", horizontal: col === 2 || col === 5 || col === 6 ? "left" : "center", wrapText: true };
        cell.border = { top: hair, bottom: hair, left: hair, right: hair };
        if (idx % 2 === 1) cell.fill = fill("FFFAF6EE");
        if (col === 8) cell.numFmt = HRS;
        if (col === 9 && !folha) cell.numFmt = BRL;
      });
      if (linhaExcedeu(i, excedidos)) row.getCell(2).font = { name: "Calibri", size: 10, bold: true, color: { argb: VERMELHO } };
      if (folha) row.getCell(9).font = { name: "Calibri", size: 9, bold: true, color: { argb: "FF6B5B45" } };
      const sc = row.getCell(10);
      sc.font = { name: "Calibri", size: 9, bold: true, color: { argb: STATUS_COLOR[i.status] ?? "FF333333" } };
      sc.fill = fill(STATUS_BG[i.status] ?? "FFEEEEEE");
    });

    const sub = ws.addRow(["", "", "", "", "", "", `TOTAL ${g.nome}`, g.horas, g.valor, `${g.items.length} reg.`]);
    sub.eachCell((cell) => {
      cell.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FF3D3022" } };
      cell.fill = fill("FFEFE6D6");
      cell.alignment = { horizontal: "center", vertical: "middle" };
      cell.border = { top: { style: "thin", color: { argb: "FF6B5B45" } } };
    });
    sub.getCell(7).alignment = { horizontal: "right", vertical: "middle" };
    sub.getCell(8).numFmt = HRS;
    sub.getCell(9).numFmt = BRL;
    sub.height = 22;
    ws.addRow([]); // separação entre funcionários
  }

  if (rows.length) {
    const tot = ws.addRow(["", "", "", "", "", "", "TOTAL GERAL", totals.horas, totals.valor, `${totals.total} reg.`]);
    tot.eachCell((cell) => {
      cell.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FFFFFFFF" } };
      cell.fill = fill("FF3D3022");
      cell.alignment = { horizontal: "center", vertical: "middle" };
      cell.border = { top: { style: "medium", color: { argb: "FF3D3022" } } };
    });
    tot.getCell(8).numFmt = HRS;
    tot.getCell(9).numFmt = BRL;
    tot.height = 24;
  }

  [12, 32, 10, 16, 26, 22, 12, 13, 14, 14].forEach((w, i) => (ws.getColumn(i + 1).width = w));
  ws.addRow([]);
  const foot = ws.addRow(["Documento gerado automaticamente pelo sistema Movimentação Operacional"]);
  ws.mergeCells(`A${foot.number}:J${foot.number}`);
  Object.assign(foot.getCell(1), { font: { name: "Calibri", size: 9, italic: true, color: { argb: "FF999999" } }, alignment: { horizontal: "center" } });

  ws.pageSetup = { orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0, margins: { left: 0.4, right: 0.4, top: 0.5, bottom: 0.5, header: 0.3, footer: 0.3 } };
  ws.headerFooter.oddFooter = "&CMovimentação Operacional — Página &P de &N";
  return wb;
}
