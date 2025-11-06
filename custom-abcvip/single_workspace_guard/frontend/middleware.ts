import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

const SINGLE_MODE =
  (process.env.NEXT_PUBLIC_SINGLE_WORKSPACE_MODE || "false").toLowerCase() === "true"
const WS_SLUG = process.env.NEXT_PUBLIC_SINGLE_WORKSPACE_SLUG || "onlyone"

// SPACE app info
const SPACE_BASE_URL  = (process.env.NEXT_PUBLIC_SPACE_BASE_URL || "").trim()
const SPACE_BASE_PATH = (process.env.NEXT_PUBLIC_SPACE_BASE_PATH || "/spaces").replace(/\/+$/,"")

const ONBOARDING = ["/onboarding", "/onboarding/", "/create-workspace", "/create-workspace/"]

function targetWorkspaceURL(req: NextRequest) {
  // Khi đã tách domain cho SPACE, path trên SPACE là "/{slug}/" (không có /spaces)
  if (SPACE_BASE_URL) {
    try {
      const base = new URL(SPACE_BASE_URL.replace(/\/+$/,""))
      base.pathname = `/${WS_SLUG}/`
      return base.toString()
    } catch { /* fallback bên dưới */ }
  }
  // Fallback: cùng domain => dùng basePath "/spaces"
  const url = req.nextUrl.clone()
  url.pathname = `${SPACE_BASE_PATH}/${WS_SLUG}/`
  return url
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl

  // 1) Chặn trực diện /workspaces/* trên WEB → chuyển sang SPACE
  if (SINGLE_MODE && pathname.startsWith("/workspaces/")) {
    return NextResponse.redirect(targetWorkspaceURL(req), 307)
  }

  // 2) Root & onboarding → SPACE
  if (SINGLE_MODE && (pathname === "/" || pathname === "" ||
      ONBOARDING.some(p => pathname === p || pathname.startsWith(p)))) {
    return NextResponse.redirect(targetWorkspaceURL(req), 307)
  }

  // 3) Nếu vào /spaces/* trên WEB mà chưa có session → đẩy sang sign-in của WEB
  const hasSession = req.cookies.get("sessionid") || req.cookies.get("jwt") || req.cookies.get("csrftoken")
  if (pathname.startsWith("/spaces/") && !hasSession) {
    const url = req.nextUrl.clone()
    url.pathname = "/auth/sign-in/"
    url.searchParams.set("next", pathname)
    return NextResponse.redirect(url, 302)
  }

  return NextResponse.next()
}

// ⚠️ Matcher mới – chuẩn Next: bỏ qua _next/static, _next/image, favicon.ico, api
export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml|manifest.webmanifest|api).*)",
  ],
}
