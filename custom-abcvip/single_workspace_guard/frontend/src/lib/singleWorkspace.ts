export const SINGLE_MODE =
  (process.env.NEXT_PUBLIC_SINGLE_WORKSPACE_MODE || "false").toLowerCase() === "true"
export const SINGLE_SLUG = process.env.NEXT_PUBLIC_SINGLE_WORKSPACE_SLUG || "onlyone"
