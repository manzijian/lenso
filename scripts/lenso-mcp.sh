#!/bin/bash
# LENSO MCP (Model Context Protocol) 启动器脚本
# 支持作为任何 MCP 客户端（Claude Desktop, Cursor, Antigravity 等）的执行入口

APP_PATH="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Debug/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP_PATH" ]; then
    APP_PATH="/Applications/lenso.app"
fi

EXEC="$APP_PATH/Contents/MacOS/lenso"
if [ ! -f "$EXEC" ]; then
    echo "LENSO executable not found at $EXEC" >&2
    exit 1
fi

exec "$EXEC" mcp "$@"
