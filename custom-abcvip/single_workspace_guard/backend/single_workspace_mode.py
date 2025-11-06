import os
from django.db import transaction, connection
from django.db.models.signals import pre_save, post_migrate, post_save
from django.dispatch import receiver
from django.core.exceptions import ValidationError
from django.utils.text import slugify
from django.contrib.auth import get_user_model

SINGLE_MODE = os.getenv("SINGLE_WORKSPACE_MODE", "false").lower() == "true"
WS_NAME = os.getenv("SINGLE_WORKSPACE_NAME", "OnlyOne")
WS_SLUG = os.getenv("SINGLE_WORKSPACE_SLUG", slugify(WS_NAME))

def _Workspace():
    from plane.db.models import Workspace
    return Workspace

def _Member():
    try:
        from plane.db.models import WorkspaceMember as Member
    except Exception:
        from plane.db.models import ProjectMember as Member
    return Member

def _Instance():
    try:
        from plane.license.models import Instance
        return Instance
    except Exception:
        return None

def _advisory_lock(key: int = 0x5A5A0A11) -> bool:
    with connection.cursor() as cur:
        cur.execute("SELECT pg_try_advisory_lock(%s);", [int(key)])
        return bool(cur.fetchone()[0])

def _ensure_workspace() -> object:
    Workspace = _Workspace()
    ws, _ = Workspace.objects.get_or_create(slug=WS_SLUG, defaults={"name": WS_NAME})
    changed = False
    if ws.name != WS_NAME:
        ws.name = WS_NAME; changed = True
    if ws.slug != WS_SLUG:
        ws.slug = WS_SLUG; changed = True
    if changed:
        ws.save()
    return ws

def _enforce_single_workspace():
    Workspace = _Workspace()
    if not Workspace.objects.exists():
        _ensure_workspace()
        return
    keeper = Workspace.objects.filter(slug=WS_SLUG).first() or Workspace.objects.order_by("id").first()
    with transaction.atomic():
        Workspace.objects.exclude(id=keeper.id).delete()
        if keeper.name != WS_NAME or keeper.slug != WS_SLUG:
            keeper.name = WS_NAME
            keeper.slug = WS_SLUG
            keeper.save()
    Instance = _Instance()
    if Instance:
        ins = Instance.objects.first()
        if ins:
            if hasattr(ins, "is_setup_done"):
                ins.is_setup_done = True
            if hasattr(ins, "is_signup_screen_visited"):
                ins.is_signup_screen_visited = True
            ins.save()

def _add_user_to_ws(user):
    if not SINGLE_MODE or not user or not getattr(user, "id", None):
        return
    ws = _ensure_workspace()
    Member = _Member()
    Member.objects.get_or_create(workspace=ws, member=user, defaults={"role": 10})

def install_single_workspace_guards():
    if not SINGLE_MODE:
        return

    Workspace = _Workspace()

    @receiver(pre_save, sender=Workspace, weak=False, dispatch_uid="sw_prevent_create")
    def _prevent_create(sender, instance, **kwargs):
        if instance.pk is None and sender.objects.exists():
            raise ValidationError("Single Workspace mode: cannot create new workspace.")
        instance.name = WS_NAME
        instance.slug = WS_SLUG

    @receiver(post_migrate, weak=False, dispatch_uid="sw_post_migrate")
    def _after_migrate(sender, **kwargs):
        try:
            if _advisory_lock():
                _enforce_single_workspace()
        except Exception as e:
            print("[single-workspace] post_migrate error:", repr(e))

    # Enforce ngay khi import
    try:
        if _advisory_lock():
            _enforce_single_workspace()
    except Exception as e:
        print("[single-workspace] initial enforce error:", repr(e))

    # Auto-add ALL existing users on first boot
    try:
        U = get_user_model()
        for u in U.objects.all():
            _add_user_to_ws(u)
    except Exception as e:
        print("[single-workspace] backfill members error:", repr(e))

    # Auto-add when user is created
    @receiver(post_save, sender=get_user_model(), weak=False, dispatch_uid="sw_on_user_create")
    def _on_user_create(sender, instance, created, **kwargs):
        if created:
            _add_user_to_ws(instance)

# Activate when module is imported by Django
install_single_workspace_guards()
