export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      activity_log: {
        Row: {
          action: string
          actor_id: string
          entity_id: string
          entity_type: string
          id: string
          snapshot_json: Json | null
          timestamp: string
          trip_id: string
        }
        Insert: {
          action: string
          actor_id: string
          entity_id: string
          entity_type: string
          id?: string
          snapshot_json?: Json | null
          timestamp?: string
          trip_id: string
        }
        Update: {
          action?: string
          actor_id?: string
          entity_id?: string
          entity_type?: string
          id?: string
          snapshot_json?: Json | null
          timestamp?: string
          trip_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_log_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      categories: {
        Row: {
          created_at: string
          deleted_at: string | null
          icon: string
          id: string
          is_default: boolean
          name: string
          trip_id: string | null
          updated_at: string
          write_id: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          icon: string
          id?: string
          is_default?: boolean
          name: string
          trip_id?: string | null
          updated_at?: string
          write_id?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          icon?: string
          id?: string
          is_default?: boolean
          name?: string
          trip_id?: string | null
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "categories_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_payments: {
        Row: {
          amount_paid: number
          created_at: string
          expense_id: string
          payment_mode: string
          trip_person_id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          amount_paid: number
          created_at?: string
          expense_id: string
          payment_mode: string
          trip_person_id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          amount_paid?: number
          created_at?: string
          expense_id?: string
          payment_mode?: string
          trip_person_id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_payments_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_payments_trip_person_id_fkey"
            columns: ["trip_person_id"]
            isOneToOne: false
            referencedRelation: "trip_people"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_splits: {
        Row: {
          amount_owed: number
          created_at: string
          expense_id: string
          percentage: number | null
          share_units: number | null
          split_type: string
          trip_person_id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          amount_owed: number
          created_at?: string
          expense_id: string
          percentage?: number | null
          share_units?: number | null
          split_type: string
          trip_person_id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          amount_owed?: number
          created_at?: string
          expense_id?: string
          percentage?: number | null
          share_units?: number | null
          split_type?: string
          trip_person_id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_splits_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_splits_trip_person_id_fkey"
            columns: ["trip_person_id"]
            isOneToOne: false
            referencedRelation: "trip_people"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          amount: number
          category_id: string | null
          created_at: string
          created_by: string
          currency: string
          deleted_at: string | null
          description: string
          expense_date: string
          id: string
          last_edited_by: string | null
          payment_method: string
          receipt_storage_path: string | null
          trip_id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          amount: number
          category_id?: string | null
          created_at?: string
          created_by: string
          currency: string
          deleted_at?: string | null
          description: string
          expense_date: string
          id?: string
          last_edited_by?: string | null
          payment_method?: string
          receipt_storage_path?: string | null
          trip_id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          amount?: number
          category_id?: string | null
          created_at?: string
          created_by?: string
          currency?: string
          deleted_at?: string | null
          description?: string
          expense_date?: string
          id?: string
          last_edited_by?: string | null
          payment_method?: string
          receipt_storage_path?: string | null
          trip_id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expenses_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_last_edited_by_fkey"
            columns: ["last_edited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_last_edited_by_fkey"
            columns: ["last_edited_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          activity_last_seen_at: string | null
          avatar_url: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          activity_last_seen_at?: string | null
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name: string
          id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          activity_last_seen_at?: string | null
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: []
      }
      push_devices: {
        Row: {
          apns_token: string
          created_at: string
          device_name: string | null
          id: string
          last_seen_at: string
          updated_at: string
          user_id: string
          write_id: string
        }
        Insert: {
          apns_token: string
          created_at?: string
          device_name?: string | null
          id?: string
          last_seen_at?: string
          updated_at?: string
          user_id: string
          write_id?: string
        }
        Update: {
          apns_token?: string
          created_at?: string
          device_name?: string | null
          id?: string
          last_seen_at?: string
          updated_at?: string
          user_id?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_devices_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_devices_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      settlements: {
        Row: {
          amount: number
          created_at: string
          created_by: string
          currency: string
          deleted_at: string | null
          from_person_id: string
          id: string
          note: string | null
          settled_at: string
          to_person_id: string
          trip_id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by: string
          currency: string
          deleted_at?: string | null
          from_person_id: string
          id?: string
          note?: string | null
          settled_at?: string
          to_person_id: string
          trip_id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string
          currency?: string
          deleted_at?: string | null
          from_person_id?: string
          id?: string
          note?: string | null
          settled_at?: string
          to_person_id?: string
          trip_id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "settlements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settlements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settlements_from_person_id_fkey"
            columns: ["from_person_id"]
            isOneToOne: false
            referencedRelation: "trip_people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settlements_to_person_id_fkey"
            columns: ["to_person_id"]
            isOneToOne: false
            referencedRelation: "trip_people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settlements_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      trip_invites: {
        Row: {
          created_at: string
          created_by: string
          id: string
          revoked_at: string | null
          token: string
          trip_id: string
          updated_at: string
          write_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          revoked_at?: string | null
          token: string
          trip_id: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          revoked_at?: string | null
          token?: string
          trip_id?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trip_invites_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_invites_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_invites_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      trip_mute_prefs: {
        Row: {
          created_at: string
          muted_at: string
          trip_id: string
          updated_at: string
          user_id: string
          write_id: string
        }
        Insert: {
          created_at?: string
          muted_at?: string
          trip_id: string
          updated_at?: string
          user_id: string
          write_id?: string
        }
        Update: {
          created_at?: string
          muted_at?: string
          trip_id?: string
          updated_at?: string
          user_id?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trip_mute_prefs_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_mute_prefs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_mute_prefs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trip_people: {
        Row: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }
        Insert: {
          created_at?: string
          display_name: string
          email: string
          id?: string
          invited_by?: string | null
          joined_at?: string | null
          removed_at?: string | null
          trip_id: string
          updated_at?: string
          user_id?: string | null
          write_id?: string
        }
        Update: {
          created_at?: string
          display_name?: string
          email?: string
          id?: string
          invited_by?: string | null
          joined_at?: string | null
          removed_at?: string | null
          trip_id?: string
          updated_at?: string
          user_id?: string | null
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trip_people_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_people_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_people_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_people_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_people_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      trips: {
        Row: {
          created_at: string
          created_by: string
          deleted_at: string | null
          id: string
          kind: string
          last_activity_at: string
          member_signature: string | null
          name: string
          updated_at: string
          write_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          deleted_at?: string | null
          id?: string
          kind?: string
          last_activity_at?: string
          member_signature?: string | null
          name: string
          updated_at?: string
          write_id?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          deleted_at?: string | null
          id?: string
          kind?: string
          last_activity_at?: string
          member_signature?: string | null
          name?: string
          updated_at?: string
          write_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trips_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trips_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "visible_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      visible_profiles: {
        Row: {
          avatar_url: string | null
          created_at: string | null
          display_name: string | null
          id: string | null
          updated_at: string | null
          write_id: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          updated_at?: string | null
          write_id?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          updated_at?: string | null
          write_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      activity_read_cursor: { Args: never; Returns: string }
      add_trip_person_by_email: {
        Args: {
          p_display_name?: string
          p_email: string
          p_person_id?: string
          p_trip_id: string
        }
        Returns: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }
        SetofOptions: {
          from: "*"
          to: "trip_people"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_trip_people_for_current_email: {
        Args: never
        Returns: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "trip_people"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      create_expense_with_payments_and_splits: {
        Args: { p_expense: Json; p_payments: Json; p_splits: Json }
        Returns: string
      }
      create_trip_with_self: {
        Args: { p_name: string; p_person_id: string; p_trip_id: string }
        Returns: {
          person_id: string
          trip_id: string
        }[]
      }
      delete_account_data: {
        Args: { p_user: string }
        Returns: {
          receipt_path: string
        }[]
      }
      ensure_current_profile: {
        Args: { p_avatar_url?: string; p_display_name?: string }
        Returns: {
          activity_last_seen_at: string | null
          avatar_url: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          id: string
          updated_at: string
          write_id: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_or_create_trip_invite: {
        Args: { p_trip_id: string }
        Returns: {
          created_at: string
          created_by: string
          id: string
          revoked_at: string | null
          token: string
          trip_id: string
          updated_at: string
          write_id: string
        }
        SetofOptions: {
          from: "*"
          to: "trip_invites"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      join_trip_with_invite: {
        Args: { p_person_id?: string; p_token: string }
        Returns: {
          person_id: string
          trip_id: string
          trip_name: string
        }[]
      }
      mark_activity_seen: { Args: { p_seen_at?: string }; Returns: string }
      purge_soft_deleted_records: {
        Args: { p_cutoff?: string }
        Returns: {
          deleted_count: number
          table_name: string
        }[]
      }
      push_targets_for_activity: {
        Args: { p_activity_id: string }
        Returns: {
          apns_token: string
          badge: number
          push_device_id: string
          user_id: string
        }[]
      }
      register_push_device: {
        Args: { p_apns_token: string; p_device_name?: string }
        Returns: undefined
      }
      remove_trip_person: {
        Args: { p_person_id: string }
        Returns: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }
        SetofOptions: {
          from: "*"
          to: "trip_people"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_or_create_non_group_container: {
        Args: { p_participants: Json }
        Returns: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "trip_people"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      revoke_trip_invite: { Args: { p_trip_id: string }; Returns: undefined }
      suggest_trip_people: {
        Args: { p_limit?: number; p_query?: string }
        Returns: {
          display_name: string
          email: string
          user_id: string
        }[]
      }
      unread_activity_count: { Args: { p_user: string }; Returns: number }
      update_trip_person_email: {
        Args: { p_email: string; p_person_id: string }
        Returns: {
          created_at: string
          display_name: string
          email: string
          id: string
          invited_by: string | null
          joined_at: string | null
          removed_at: string | null
          trip_id: string
          updated_at: string
          user_id: string | null
          write_id: string
        }
        SetofOptions: {
          from: "*"
          to: "trip_people"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      validate_expense_payment_total: {
        Args: { p_expense_id: string }
        Returns: undefined
      }
      validate_expense_split_total: {
        Args: { p_expense_id: string }
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
    Enums: {},
  },
} as const

