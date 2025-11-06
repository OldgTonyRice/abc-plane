# Single Workspace Feature

## Bật (local)
```bash
./custom-abcvip/single_workspace_guard/enable.sh
docker compose -f docker-compose.yml -f docker-compose.override.yml \
  -f custom-abcvip/single_workspace_guard/compose/override.addon.yml \
  up -d --build api web
