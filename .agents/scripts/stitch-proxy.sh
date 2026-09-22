#!/bin/zsh
cd /Users/saman/Desktop/project-root
export STITCH_API_KEY="$(grep '^STITCH_API_KEY=' .env | cut -d '=' -f2-)"
exec npx @_davideast/stitch-mcp proxy
