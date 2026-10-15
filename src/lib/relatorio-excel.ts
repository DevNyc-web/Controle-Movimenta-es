import ExcelJS from "exceljs";
import { agruparPorFuncionario, totaisGerais, grupoExcedeu, linhaExcedeu, rotuloStatusFiltro, LABEL_FOLHA, type FtRow } from "./relatorio.ts";

const fmtData = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}`;
const fill = (argb: string) => ({ type: "pattern" as const, pattern: "solid" as const, fgColor: { argb } });
const hair = { style: "hair" as const, color: { argb: "FFE5DDC9" } };
const dark = { style: "thin" as const, color: { argb: "FF3D3022" } };
const STATUS_COLOR: Record<string, string> = { APROVADA: "FF1B7A4D", PENDENTE: "FFB07A1A", NEGADA: "FFB23A48", CANCELADA: "FF6B5B45" };
const STATUS_BG: Record<string, string> = { APROVADA: "FFD9F0E3", PENDENTE: "FFFCEFD0", NEGADA: "FFF7DAD9", CANCELADA: "FFE8E2D5" };
const VERMELHO = "FFC00000"; // limite mensal excedido
const BRL = '"R$ "#,##0.00';
const HRS = '0.0" h"';
const font = (size: number, extra: Partial<ExcelJS.Font> = {}): Partial<ExcelJS.Font> => ({ name: "Calibri", size, ...extra });
const ALTURA = 15; // linhas de uma só linha de texto (subtítulo, subtotal). Linhas de FT: altura automática (quebra de linha)
const HEADER = 4; // linha do cabeçalho da tabela (repetida em cada página impressa)

/** Planilha agrupada e compacta para impressão (A4 retrato, 1 página de largura): por funcionário (cabeçalho, FTs,
 *  TOTAL do funcionário) + TOTAL GERAL. Mesmas colunas, valores, formatos e totais do layout anterior.
 *  `excedidos` = chaves funcionario_id|AAAA-MM com mais de 4 movimentações (ver mesesExcedidos): só muda a cor do nome.
 *  `status` = filtro de status da tela ("" = todos); só aparece no subtítulo — `items` já vem filtrado. */
export function buildWorkbook(items: any[], start: string, end: string, emitidoEm: string, excedidos: ReadonlySet<string> = new Set(), status = ""): ExcelJS.Workbook {
  const rows = items as FtRow[];
  const totals = totaisGerais(rows);
  const wb = new ExcelJS.Workbook();
  wb.creator = "Movimentação Operacional";
  wb.created = new Date();
  const ws = wb.addWorksheet("Relatório", { views: [{ state: "frozen", ySplit: HEADER }] });

  const banner = (ref: string, value: string, style: Partial<ExcelJS.Cell>) => {
    ws.mergeCells(ref);
    Object.assign(ws.getCell(ref.split(":")[0]), { value, ...style });
  };
  banner("A1:E1", "MOVIMENTAÇÃO OPERACIONAL", { font: font(13, { bold: true, color: { argb: "FFFFFFFF" } }), alignment: { horizontal: "left", vertical: "middle" }, fill: fill("FF3D3022") });
  banner("F1:J1", emitidoEm, { font: font(9, { color: { argb: "FFE5DDC9" } }), alignment: { horizontal: "right", vertical: "middle" }, fill: fill("FF3D3022") });
  ws.getRow(1).height = 18;
  banner("A2:J2", `Relatório Gerencial — Período: ${fmtData(start)} a ${fmtData(end)}${status ? ` — Status: ${rotuloStatusFiltro(status)}` : ""}`, { font: font(10, { italic: true, color: { argb: "FF6B5B45" } }), alignment: { horizontal: "center", vertical: "middle" }, fill: fill("FFEFE6D6") });
  banner(
    "A3:J3",
    `Total: ${totals.total}   |   Aprovadas: ${totals.APROVADA}   |   Pendentes: ${totals.PENDENTE}   |   Negadas/Canceladas: ${totals.NEGADA + totals.CANCELADA}   |   Horas trabalhadas: ${totals.horas}h   |   Valor total: R$ ${totals.valor.toFixed(2)}`,
    { font: font(10, { bold: true, color: { argb: "FF3D3022" } }), alignment: { horizontal: "center", vertical: "middle", wrapText: true }, fill: fill("FFF7F1E5") },
  );
  ws.getRow(2).height = ALTURA;
  ws.getRow(3).height = 28; // célula mesclada não ajusta altura sozinha: espaço para 2 linhas se o resumo quebrar

  const headers = ["Data", "Colaborador", "RE", "Cargo", "Funcionário faltante", "Posto da falta", "Escala", "Horas Trab.", "Valor (R$)", "Status"];
  const headerRow = ws.getRow(HEADER);
  headers.forEach((h, idx) => {
    Object.assign(headerRow.getCell(idx + 1), { value: h, font: font(10, { bold: true, color: { argb: "FFFFFFFF" } }), fill: fill("FF6B5B45"), alignment: { horizontal: "center", vertical: "middle", wrapText: true }, border: { top: dark, bottom: dark, left: dark, right: dark } });
  });
  headerRow.height = 28; // 2 linhas ("Horas Trab." quebra)

  for (const g of agruparPorFuncionario(rows)) {
    const gr = ws.addRow([`${g.nome}  —  RE ${g.re}`]);
    ws.mergeCells(gr.number, 1, gr.number, 10);
    Object.assign(gr.getCell(1), { font: font(11, { bold: true, color: { argb: grupoExcedeu(g, excedidos) ? VERMELHO : "FF3D3022" } }), fill: fill("FFE5DDC9"), alignment: { horizontal: "left", vertical: "middle" } });
    gr.height = 17;

    g.items.forEach((i: any, idx) => {
      const folha = !!i.pagamento_em_folha;
      const row = ws.addRow([
        fmtData(i.data_ft), i.funcionario?.nome ?? "—", i.funcionario?.re ?? "—", i.funcionario?.cargo ?? "—",
        i.funcionario_faltante?.nome ?? "—", i.posto_falta ?? "—", i.escala_servico ?? i.tipo_folga ?? "—",
        Number(i.horas_trabalhadas), folha ? LABEL_FOLHA : Number(i.valor_pago ?? 0), i.status,
      ]);
      // Sem altura fixa: Excel/LibreOffice/Sheets ajustam a altura; texto longo quebra em 2+ linhas (nunca encolhe nem corta).
      row.eachCell((cell, col) => {
        cell.font = font(10);
        cell.alignment = { vertical: "middle", horizontal: col === 2 || col === 5 || col === 6 ? "left" : "center", wrapText: true };
        cell.border = { top: hair, bottom: hair, left: hair, right: hair };
        if (idx % 2 === 1) cell.fill = fill("FFFAF6EE");
        if (col === 8) cell.numFmt = HRS;
        if (col === 9 && !folha) cell.numFmt = BRL;
      });
      if (linhaExcedeu(i, excedidos)) row.getCell(2).font = font(10, { color: { argb: VERMELHO } }); // só a cor (sem negrito)
      if (folha) row.getCell(9).font = font(9, { bold: true, color: { argb: "FF6B5B45" } });
      const sc = row.getCell(10);
      sc.font = font(9, { bold: true, color: { argb: STATUS_COLOR[i.status] ?? "FF333333" } });
      sc.fill = fill(STATUS_BG[i.status] ?? "FFEEEEEE");
    });

    // Sem linha em branco entre funcionários: a borda do subtotal + a faixa do próximo cabeçalho já separam.
    // Colunas 1-6 vazias (null) para o rótulo, alinhado à direita, poder transbordar para a esquerda.
    const sub = ws.addRow([null, null, null, null, null, null, `TOTAL ${g.nome}`, g.horas, g.valor, `${g.items.length} reg.`]);
    sub.eachCell({ includeEmpty: true }, (cell) => {
      cell.font = font(10, { bold: true, color: { argb: "FF3D3022" } });
      cell.fill = fill("FFEFE6D6");
      cell.alignment = { horizontal: "center", vertical: "middle" };
      cell.border = { top: { style: "thin", color: { argb: "FF6B5B45" } } };
    });
    sub.getCell(7).alignment = { horizontal: "right", vertical: "middle" };
    sub.getCell(8).numFmt = HRS;
    sub.getCell(9).numFmt = BRL;
    sub.height = ALTURA;
  }

  if (rows.length) {
    const tot = ws.addRow([null, null, null, null, null, null, "TOTAL GERAL", totals.horas, totals.valor, `${totals.total} reg.`]);
    tot.eachCell({ includeEmpty: true }, (cell) => {
      cell.font = font(11, { bold: true, color: { argb: "FFFFFFFF" } });
      cell.fill = fill("FF3D3022");
      cell.alignment = { horizontal: "center", vertical: "middle" };
      cell.border = { top: { style: "medium", color: { argb: "FF3D3022" } } };
    });
    tot.getCell(7).alignment = { horizontal: "right", vertical: "middle" };
    tot.getCell(8).numFmt = HRS;
    tot.getCell(9).numFmt = BRL;
    tot.height = 17;
  }

  // Larguras (soma 126 vs 171 antes; A4 retrato, ~8 pt impresso) medidas nos dados reais: data, RE (até 7), cargo (até 13),
  // valor, horas e status cabem em 1 linha; nome/faltante/posto quebram quando passam da mediana. "PAGAMENTO EM FOLHA" quebra em 2.
  [10, 24, 7, 12, 19, 20, 6, 8, 11, 9].forEach((w, i) => (ws.getColumn(i + 1).width = w));
  const foot = ws.addRow(["Documento gerado automaticamente pelo sistema Movimentação Operacional"]);
  ws.mergeCells(`A${foot.number}:J${foot.number}`);
  Object.assign(foot.getCell(1), { font: font(9, { italic: true, color: { argb: "FF999999" } }), alignment: { horizontal: "center" } });

  ws.pageSetup = {
    orientation: "portrait", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0, horizontalCentered: true,
    printTitlesRow: `${HEADER}:${HEADER}`,
    margins: { left: 0.25, right: 0.25, top: 0.4, bottom: 0.45, header: 0.15, footer: 0.2 },
  };
  ws.headerFooter.oddFooter = "&9&CMovimentação Operacional — Página &P de &N";
  return wb;
}
