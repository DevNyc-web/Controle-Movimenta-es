import { extrairLinhas, type Campo, type Colunas, type Matriz } from "./importacao-funcionarios";

/** nome: "arquivo / aba" com vários arquivos, para achar a linha certa quando as abas têm o mesmo nome. */
export type Aba = { id: string; nome: string; matriz: Matriz; linha: number; colunas: Colunas; duvida: boolean; usar: boolean; oculta?: boolean };
export type CampoMapa = { campo: Campo; label: string; obrigatorio?: boolean };

export const leituraDa = (a: Aba) => extrairLinhas(a.matriz, a.linha, a.colunas, a.nome);
export const mapeada = (a: Aba) => a.linha >= 0 && a.colunas.cpf !== undefined && a.colunas.nome !== undefined && a.colunas.cpf !== a.colunas.nome;
