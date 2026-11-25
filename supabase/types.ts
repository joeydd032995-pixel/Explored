/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

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
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      app_metrics: {
        Row: {
          created_at: string
          day: string
          id: string
          metric: string
          user_id: string
          value: number
        }
        Insert: {
          created_at?: string
          day?: string
          id?: string
          metric: string
          user_id: string
          value?: number
        }
        Update: {
          created_at?: string
          day?: string
          id?: string
          metric?: string
          user_id?: string
          value?: number
        }
        Relationships: []
      }
      boundaries_admin: {
        Row: {
          fetched_at: string
          geom: unknown
          id: string
          level: number
          name: string
          source: string
          total_cells: number | null
          version: number
        }
        Insert: {
          fetched_at?: string
          geom: unknown
          id: string
          level: number
          name: string
          source: string
          total_cells?: number | null
          version?: number
        }
        Update: {
          fetched_at?: string
          geom?: unknown
          id?: string
          level?: number
          name?: string
          source?: string
          total_cells?: number | null
          version?: number
        }
        Relationships: []
      }
      boundary_releases: {
        Row: {
          changed_entities: Json
          released_at: string
          version: string
        }
        Insert: {
          changed_entities?: Json
          released_at?: string
          version: string
        }
        Update: {
          changed_entities?: Json
          released_at?: string
          version?: string
        }
        Relationships: []
      }
      camera_points: {
        Row: {
          confidence: number
          confirmations: number
          created_at: string
          geom: unknown
          id: string
          kind: string
          last_verified: number
          lat: number
          lng: number
          note: string
          reporter_user_id: string | null
          source: string
          status: string
        }
        Insert: {
          confidence?: number
          confirmations?: number
          created_at?: string
          geom?: unknown
          id: string
          kind: string
          last_verified?: number
          lat: number
          lng: number
          note?: string
          reporter_user_id?: string | null
          source?: string
          status?: string
        }
        Update: {
          confidence?: number
          confirmations?: number
          created_at?: string
          geom?: unknown
          id?: string
          kind?: string
          last_verified?: number
          lat?: number
          lng?: number
          note?: string
          reporter_user_id?: string | null
          source?: string
          status?: string
        }
        Relationships: []
      }
      cell_claims: {
        Row: {
          cell: string
          device: string
          entity_id: string
          entity_level: number
          first_seen: number
          last_seen: number
          user_id: string
          visits: number
        }
        Insert: {
          cell: string
          device?: string
          entity_id: string
          entity_level: number
          first_seen: number
          last_seen: number
          user_id: string
          visits?: number
        }
        Update: {
          cell?: string
          device?: string
          entity_id?: string
          entity_level?: number
          first_seen?: number
          last_seen?: number
          user_id?: string
          visits?: number
        }
        Relationships: []
      }
      game_events: {
        Row: {
          created_at: string
          id: string
          kind: string
          payload: Json
          session_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          payload?: Json
          session_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          payload?: Json
          session_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_events_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "game_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      game_players: {
        Row: {
          color: string
          display_name: string
          last_ping: number
          lat: number | null
          lng: number | null
          score: number
          session_id: string
          user_id: string
        }
        Insert: {
          color?: string
          display_name?: string
          last_ping?: number
          lat?: number | null
          lng?: number | null
          score?: number
          session_id: string
          user_id: string
        }
        Update: {
          color?: string
          display_name?: string
          last_ping?: number
          lat?: number | null
          lng?: number | null
          score?: number
          session_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_players_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "game_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      game_sessions: {
        Row: {
          created_at: string
          duration_s: number
          ended_at: string | null
          host_name: string
          host_user_id: string
          id: string
          invite_code: string
          mode: string
          params: Json
          started_at: string | null
          status: string
        }
        Insert: {
          created_at?: string
          duration_s?: number
          ended_at?: string | null
          host_name?: string
          host_user_id: string
          id?: string
          invite_code: string
          mode: string
          params?: Json
          started_at?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          duration_s?: number
          ended_at?: string | null
          host_name?: string
          host_user_id?: string
          id?: string
          invite_code?: string
          mode?: string
          params?: Json
          started_at?: string | null
          status?: string
        }
        Relationships: []
      }
      hazard_reports: {
        Row: {
          confirmations: number
          created_at: number
          expires_at: number
          geom: unknown
          id: string
          kind: string
          lat: number
          lng: number
          reporter_user_id: string | null
        }
        Insert: {
          confirmations?: number
          created_at: number
          expires_at: number
          geom?: unknown
          id: string
          kind: string
          lat: number
          lng: number
          reporter_user_id?: string | null
        }
        Update: {
          confirmations?: number
          created_at?: number
          expires_at?: number
          geom?: unknown
          id?: string
          kind?: string
          lat?: number
          lng?: number
          reporter_user_id?: string | null
        }
        Relationships: []
      }
      overlay_definitions: {
        Row: {
          category: string
          coordinate_system: string
          created_at: string
          creator_user_id: string
          id: string
          installs: number
          installs_month: number
          name: string
          price_usd: number | null
          pricing: string
          rating_avg: number
          rating_count: number
          reported_count: number
          spec: Json
          status: string
          store_product_id: string | null
          summary: string
          system_image: string
          updated_at: string
          version: number
          visibility: string
        }
        Insert: {
          category?: string
          coordinate_system?: string
          created_at?: string
          creator_user_id: string
          id?: string
          installs?: number
          installs_month?: number
          name: string
          price_usd?: number | null
          pricing?: string
          rating_avg?: number
          rating_count?: number
          reported_count?: number
          spec: Json
          status?: string
          store_product_id?: string | null
          summary?: string
          system_image?: string
          updated_at?: string
          version?: number
          visibility?: string
        }
        Update: {
          category?: string
          coordinate_system?: string
          created_at?: string
          creator_user_id?: string
          id?: string
          installs?: number
          installs_month?: number
          name?: string
          price_usd?: number | null
          pricing?: string
          rating_avg?: number
          rating_count?: number
          reported_count?: number
          spec?: Json
          status?: string
          store_product_id?: string | null
          summary?: string
          system_image?: string
          updated_at?: string
          version?: number
          visibility?: string
        }
        Relationships: []
      }
      overlay_install_events: {
        Row: {
          day: string
          overlay_id: string
          user_id: string
        }
        Insert: {
          day?: string
          overlay_id: string
          user_id: string
        }
        Update: {
          day?: string
          overlay_id?: string
          user_id?: string
        }
        Relationships: []
      }
      overlay_reports: {
        Row: {
          created_at: string
          id: string
          overlay_id: string
          reason: string
          reporter_user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          overlay_id: string
          reason?: string
          reporter_user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          overlay_id?: string
          reason?: string
          reporter_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "overlay_reports_overlay_id_fkey"
            columns: ["overlay_id"]
            isOneToOne: false
            referencedRelation: "overlay_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      overlay_reviews: {
        Row: {
          body: string
          created_at: string
          id: string
          overlay_id: string
          rating: number
          updated_at: string
          user_id: string
        }
        Insert: {
          body?: string
          created_at?: string
          id?: string
          overlay_id: string
          rating: number
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          overlay_id?: string
          rating?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "overlay_reviews_overlay_id_fkey"
            columns: ["overlay_id"]
            isOneToOne: false
            referencedRelation: "overlay_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      social_events: {
        Row: {
          created_at: string
          id: string
          kind: string
          title: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          title: string
          user_id: string
          username?: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          title?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      boundary_entity_at: {
        Args: { p_lat: number; p_level: number; p_lng: number }
        Returns: {
          id: string
          name: string
          source: string
          version: number
        }[]
      }
      confirm_hazard_report: {
        Args: { p_new_expiry: number; p_report_id: string }
        Returns: undefined
      }
      delete_my_cell_claims: { Args: { p_user_id: string }; Returns: undefined }
      entity_progress: {
        Args: { p_entity_id: string; p_level: number; p_user: string }
        Returns: {
          claimed: number
          percent: number
          total: number
        }[]
      }
      increment_overlay_installs: {
        Args: { p_overlay_id: string }
        Returns: undefined
      }
      overlay_active_users: { Args: { p_overlay_id: string }; Returns: number }
      overlay_daily_installs: {
        Args: { p_days?: number; p_overlay_id: string }
        Returns: {
          day: string
          installs: number
        }[]
      }
      upsert_cell_claim: {
        Args: {
          p_cell: string
          p_entity_id: string
          p_first_seen: number
          p_last_seen: number
          p_level: number
          p_user_id: string
          p_visits: number
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
