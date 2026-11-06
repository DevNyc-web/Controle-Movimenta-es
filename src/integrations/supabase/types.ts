export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          created_at: string
          description: string | null
          entity_id: string | null
          entity_type: string
          id: string
          new_data: Json | null
          observacao: string | null
          old_data: Json | null
          role: string | null
          user_id: string | null
          username: string | null
        }
        Insert: {
          action: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type: string
          id?: string
          new_data?: Json | null
          observacao?: string | null
          old_data?: Json | null
          role?: string | null
          user_id?: string | null
          username?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type?: string
          id?: string
          new_data?: Json | null
          observacao?: string | null
          old_data?: Json | null
          role?: string | null
          user_id?: string | null
          username?: string | null
        }
        Relationships: []
      }
      ft: {
        Row: {
          aprovado_por: string | null
          created_at: string
          data_cancelamento: string | null
          data_ft: string
          data_lancamento: string
          escala_servico: string | null
          funcionario_faltante_id: string | null
          funcionario_id: string
          horas_compensadas: number
          horas_trabalhadas: number
          id: string
          lancado_por: string | null
          motivo: string | null
          numero_ft: string
          pagamento_em_folha: boolean
          retroativa_autorizada_em: string | null
          retroativa_autorizada_por: string | null
          retroativa_justificativa: string | null
          observacao: string | null
          posto_falta: string | null
          status: Database["public"]["Enums"]["ft_status"]
          tipo_folga: string | null
          updated_at: string
          valor_pago: number
        }
        Insert: {
          aprovado_por?: string | null
          created_at?: string
          data_cancelamento?: string | null
          data_ft: string
          data_lancamento?: string
          escala_servico?: string | null
          funcionario_faltante_id?: string | null
          funcionario_id: string
          horas_compensadas?: number
          horas_trabalhadas?: number
          id?: string
          lancado_por?: string | null
          motivo?: string | null
          numero_ft?: string
          pagamento_em_folha?: boolean
          retroativa_autorizada_em?: string | null
          retroativa_autorizada_por?: string | null
          retroativa_justificativa?: string | null
          observacao?: string | null
          posto_falta?: string | null
          status?: Database["public"]["Enums"]["ft_status"]
          tipo_folga?: string | null
          updated_at?: string
          valor_pago?: number
        }
        Update: {
          aprovado_por?: string | null
          created_at?: string
          data_cancelamento?: string | null
          data_ft?: string
          data_lancamento?: string
          escala_servico?: string | null
          funcionario_faltante_id?: string | null
          funcionario_id?: string
          horas_compensadas?: number
          horas_trabalhadas?: number
          id?: string
          lancado_por?: string | null
          motivo?: string | null
          numero_ft?: string
          pagamento_em_folha?: boolean
          retroativa_autorizada_em?: string | null
          retroativa_autorizada_por?: string | null
          retroativa_justificativa?: string | null
          observacao?: string | null
          posto_falta?: string | null
          status?: Database["public"]["Enums"]["ft_status"]
          tipo_folga?: string | null
          updated_at?: string
          valor_pago?: number
        }
        Relationships: [
          {
            foreignKeyName: "ft_funcionario_faltante_id_fkey"
            columns: ["funcionario_faltante_id"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ft_funcionario_id_fkey"
            columns: ["funcionario_id"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["id"]
          },
        ]
      }
      ft_cancelamento_solicitacoes: {
        Row: {
          created_at: string
          data_decisao: string | null
          decidido_por: string | null
          ft_id: string
          id: string
          motivo: string
          observacao: string | null
          solicitado_por: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          data_decisao?: string | null
          decidido_por?: string | null
          ft_id: string
          id?: string
          motivo: string
          observacao?: string | null
          solicitado_por: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          data_decisao?: string | null
          decidido_por?: string | null
          ft_id?: string
          id?: string
          motivo?: string
          observacao?: string | null
          solicitado_por?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ft_cancelamento_solicitacoes_ft_id_fkey"
            columns: ["ft_id"]
            isOneToOne: false
            referencedRelation: "ft"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ft_cancelamento_solicitacoes_solicitado_por_fkey"
            columns: ["solicitado_por"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ft_cancelamento_solicitacoes_decidido_por_fkey"
            columns: ["decidido_por"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      ft_historico: {
        Row: {
          acao: string
          alterado_por: string | null
          created_at: string
          ft_id: string
          id: string
          observacao: string | null
          status_anterior: Database["public"]["Enums"]["ft_status"] | null
          status_novo: Database["public"]["Enums"]["ft_status"] | null
        }
        Insert: {
          acao: string
          alterado_por?: string | null
          created_at?: string
          ft_id: string
          id?: string
          observacao?: string | null
          status_anterior?: Database["public"]["Enums"]["ft_status"] | null
          status_novo?: Database["public"]["Enums"]["ft_status"] | null
        }
        Update: {
          acao?: string
          alterado_por?: string | null
          created_at?: string
          ft_id?: string
          id?: string
          observacao?: string | null
          status_anterior?: Database["public"]["Enums"]["ft_status"] | null
          status_novo?: Database["public"]["Enums"]["ft_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "ft_historico_ft_id_fkey"
            columns: ["ft_id"]
            isOneToOne: false
            referencedRelation: "ft"
            referencedColumns: ["id"]
          },
        ]
      }
      conferencias: {
        Row: {
          arquivo_abas: string[]
          arquivo_nome: string
          criada_em: string
          criada_por: string
          encerrada_em: string | null
          encerrada_por: string | null
          id: string
          linhas_ignoradas: number
          mapeamento: Json
          motivo_descarte: string | null
          resultado: Json | null
          resumo: Json
          status: string
          total_impresso: number | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      conferencia_itens: {
        Row: {
          acao: string | null
          acao_sugerida: string | null
          atual: Json | null
          conferencia_id: string
          dados: Json | null
          decidido_em: string | null
          decidido_por: string | null
          decisao: string
          folha: Json | null
          funcionario_id: string | null
          id: string
          justificativa: string | null
          motivo: string
          novo_funcionario_id: string | null
          opcoes: string[]
          ordem: number
          origens: string[]
          resultado: string | null
          resultado_detalhe: string | null
          tipo: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      funcionario_inatividades: {
        Row: {
          anulacao_fts: Json | null
          anulacao_justificativa: string | null
          anulada_em: string | null
          anulada_por: string | null
          fim: string | null
          funcionario_id: string
          id: string
          inativado_em: string
          inativado_por: string | null
          inicio: string
          motivo_reativacao: string | null
          reativado_em: string | null
          reativado_por: string | null
        }
        Insert: {
          anulacao_fts?: Json | null
          anulacao_justificativa?: string | null
          anulada_em?: string | null
          anulada_por?: string | null
          fim?: string | null
          funcionario_id: string
          id?: string
          inativado_em?: string
          inativado_por?: string | null
          inicio: string
          motivo_reativacao?: string | null
          reativado_em?: string | null
          reativado_por?: string | null
        }
        Update: {
          anulacao_fts?: Json | null
          anulacao_justificativa?: string | null
          anulada_em?: string | null
          anulada_por?: string | null
          fim?: string | null
          funcionario_id?: string
          id?: string
          inativado_em?: string
          inativado_por?: string | null
          inicio?: string
          motivo_reativacao?: string | null
          reativado_em?: string | null
          reativado_por?: string | null
        }
        Relationships: []
      }
      funcionarios: {
        Row: {
          banco_horas: number
          cargo: string
          cpf: string | null
          created_at: string
          data_admissao: string | null
          empresa: string | null
          id: string
          nome: string
          re: string
          setor: string | null
          status: string
          status_ativo: boolean
          supervisor: string | null
          data_inativacao: string | null
          inativado_por: string | null
          reativacao_motivo: string | null
          turno: string
          updated_at: string
          usa_banco_horas: boolean
        }
        Insert: {
          banco_horas?: number
          cargo: string
          cpf?: string | null
          created_at?: string
          data_admissao?: string | null
          empresa?: string | null
          id?: string
          nome: string
          re: string
          setor?: string | null
          status?: string
          status_ativo?: boolean
          supervisor?: string | null
          data_inativacao?: string | null
          inativado_por?: string | null
          reativacao_motivo?: string | null
          turno: string
          updated_at?: string
          usa_banco_horas?: boolean
        }
        Update: {
          banco_horas?: number
          cargo?: string
          cpf?: string | null
          created_at?: string
          data_admissao?: string | null
          empresa?: string | null
          id?: string
          nome?: string
          re?: string
          setor?: string | null
          status?: string
          status_ativo?: boolean
          supervisor?: string | null
          data_inativacao?: string | null
          inativado_por?: string | null
          reativacao_motivo?: string | null
          turno?: string
          updated_at?: string
          usa_banco_horas?: boolean
        }
        Relationships: []
      }
      profiles: {
        Row: {
          ativo: boolean
          created_at: string
          email: string
          id: string
          nome: string
          updated_at: string
          username: string | null
        }
        Insert: {
          ativo?: boolean
          created_at?: string
          email: string
          id: string
          nome: string
          updated_at?: string
          username?: string | null
        }
        Update: {
          ativo?: boolean
          created_at?: string
          email?: string
          id?: string
          nome?: string
          updated_at?: string
          username?: string | null
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      anular_inatividade: {
        Args: { _justificativa: string; _periodo_id: string }
        Returns: undefined
      }
      aprovar_cancelamento: {
        Args: { _solicitacao_id: string; _obs?: string }
        Returns: undefined
      }
      conferencia_aplicar: {
        Args: { _confirmacao: string; _id: string }
        Returns: Json
      }
      conferencia_criar: {
        Args: { _arquivo: Json; _itens: Json; _resumo: Json }
        Returns: string
      }
      conferencia_decidir: {
        Args: { _acao?: string; _dados?: Json; _decisao: string; _item: string; _justificativa?: string }
        Returns: undefined
      }
      conferencia_descartar: {
        Args: { _id: string; _motivo: string }
        Returns: undefined
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      log_audit: {
        Args: {
          _action: string
          _description?: string
          _entity_id: string
          _entity_type: string
          _new?: Json
          _obs?: string
          _old?: Json
        }
        Returns: undefined
      }
      rejeitar_cancelamento: {
        Args: { _solicitacao_id: string; _obs?: string }
        Returns: undefined
      }
      valor_folga_por_cargo: { Args: { _cargo: string }; Returns: number }
    }
    Enums: {
      app_role: "admin" | "gestor" | "rh" | "apontamento" | "supervisor"
      ft_status: "PENDENTE" | "APROVADA" | "NEGADA" | "CANCELADA" | "CANCELAMENTO_SOLICITADO"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "gestor", "rh", "apontamento", "supervisor"],
      ft_status: ["PENDENTE", "APROVADA", "NEGADA", "CANCELADA", "CANCELAMENTO_SOLICITADO"],
    },
  },
} as const
