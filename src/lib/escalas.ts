// ft.escala_servico é TEXT livre no banco (sem CHECK). Horas = duração integral do turno, sem desconto de intervalo.
// valor_pago NÃO depende das horas (é fixo por cargo, via trigger); as horas só alimentam relatórios/totais.
// data_ft é uma DATE única (dia em que o turno começa), então 22h às 06h não gera conflito de intervalo entre datas.
export const ESCALAS_HORAS: Record<string, number> = {
  "06x18": 12, "18x06": 12, "07x19": 12, "19x07": 12, "08x18": 10,
  "Horário das 06h às 16h": 10,
  "Horário das 08h às 16h": 8,
  "Horário das 22h às 06h": 8, // atravessa a meia-noite
};

export const ESCALAS = [...Object.keys(ESCALAS_HORAS), "Outros"];
