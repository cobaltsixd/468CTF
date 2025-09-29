#!/usr/bin/env bash
# intentionally calls 'sh' without full path to show PATH hijack vector
sh -c 'echo "[notes] backing up..." && tar -cf /tmp/notes.tar /etc/hosts >/dev/null 2>&1 && echo done'
