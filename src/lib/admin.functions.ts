import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

export const checkIsAdmin = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<{ isAdmin: boolean }> => {
    const { supabase, userId } = context;
    // Cast: `user_roles` table is created by the Phase scaffold migration; types
    // regenerate after the migration is approved.
    const { data, error } = await (supabase as unknown as {
      rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: boolean | null; error: unknown }>;
    }).rpc("has_role", { _user_id: userId, _role: "admin" });
    if (error) return { isAdmin: false };
    return { isAdmin: data === true };
  });
