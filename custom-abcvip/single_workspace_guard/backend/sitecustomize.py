cat > custom-abcvip/single_workspace_guard/backend/sitecustomize.py <<'PY'
import os

ENABLED = os.getenv("SINGLE_WORKSPACE_MODE", "false").lower() == "true"

def _as_list(val):
    if not val:
        return []
    return [x.strip() for x in val.split(",") if x.strip()]

def patch_settings():
    try:
        from django.conf import settings
    except Exception:
        return

    BASE_DOMAIN = os.getenv("BASE_DOMAIN", "task.planelocal")
    PROTOCOL    = os.getenv("APP_PROTOCOL", "http")   # dev: http
    PORT        = os.getenv("APP_PORT", "18080")
    SUBS        = _as_list(os.getenv("SUBDOMAINS", "task,space,admin"))

    # 1) hosts
    hosts = set(getattr(settings, "ALLOWED_HOSTS", []))
    hosts.update({f"{s}.{BASE_DOMAIN}" for s in SUBS})
    hosts.update({BASE_DOMAIN, "localhost", "127.0.0.1"})
    settings.ALLOWED_HOSTS = list(hosts)

    # 2) cookie domain dùng chung cho *.task.planelocal
    cookie_domain = "." + BASE_DOMAIN
    settings.SESSION_COOKIE_DOMAIN = cookie_domain
    settings.CSRF_COOKIE_DOMAIN    = cookie_domain

    # 3) cookie secure theo protocol
    is_https = (PROTOCOL == "https")
    settings.SESSION_COOKIE_SECURE = is_https
    settings.CSRF_COOKIE_SECURE    = is_https

    # 4) CSRF trusted origins (có cả bản có port)
    origins = []
    for s in SUBS:
        origins.append(f"{PROTOCOL}://{s}.{BASE_DOMAIN}")
        origins.append(f"{PROTOCOL}://{s}.{BASE_DOMAIN}:{PORT}")
    origins.append(f"{PROTOCOL}://{BASE_DOMAIN}")
    origins.append(f"{PROTOCOL}://{BASE_DOMAIN}:{PORT}")
    settings.CSRF_TRUSTED_ORIGINS = origins

    settings.SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https" if is_https else "http")

if ENABLED:
    try:
        import django
        _orig_setup = django.setup

        def _patched_setup(*args, **kwargs):
            res = _orig_setup(*args, **kwargs)
            try:
                patch_settings()
                print("[single-workspace] Settings patched (cookies/CSRF/hosts).")
            except Exception as e:
                print("[single-workspace] Settings patch error:", repr(e))
            try:
                from single_workspace_mode import install_single_workspace_guards
                install_single_workspace_guards()
                print("[single-workspace] Guard installed successfully.")
            except Exception as e:
                print("[single-workspace] Error installing guard:", repr(e))
            return res

        django.setup = _patched_setup
        print("[single-workspace] Mode ENABLED — will activate after django.setup().")
    except Exception as e:
        print("[single-workspace] Failed to patch django.setup:", repr(e))
else:
    print("[single-workspace] Mode DISABLED.")
PY
