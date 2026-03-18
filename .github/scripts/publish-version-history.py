#!/usr/bin/env python3
"""Publish RELEASE_NOTES.md to a Version_history subpage on a MediaWiki wiki.

Usage: python3 publish-version-history.py <page-title>

Requires environment variables: WIKI_API_URL, WIKI_BOT_USER, WIKI_BOT_PASSWORD
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request
import http.cookiejar

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <page-title>", file=sys.stderr)
    sys.exit(2)

wiki_page = sys.argv[1]
api = os.environ["WIKI_API_URL"]
user = os.environ["WIKI_BOT_USER"]
password = os.environ["WIKI_BOT_PASSWORD"]

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))


def post(params):
    data = urllib.parse.urlencode(params).encode()
    r = opener.open(urllib.request.Request(api, data))
    return json.loads(r.read())


def get(params):
    url = api + "?" + urllib.parse.urlencode(params)
    r = opener.open(url)
    return json.loads(r.read())


# Convert RELEASE_NOTES.md to wikitext (newest first)
lines = []
with open("RELEASE_NOTES.md") as f:
    for line in f:
        line = line.rstrip()
        if not line.startswith("- "):
            continue
        parts = line[2:].split(" - ", 2)
        if len(parts) != 3:
            continue
        version, date, desc = parts
        desc = re.sub(r"`([^`]+)`", r"<code>\1</code>", desc)
        lines.append(f"* '''{version}''' — {date} — {desc}")
lines.reverse()
content = "\n".join(lines) + "\n"

# Login
r = post({"action": "query", "meta": "tokens", "type": "login", "format": "json"})
token = r["query"]["tokens"]["logintoken"]
post({"action": "login", "lgname": user, "lgpassword": password, "lgtoken": token, "format": "json"})
r = get({"action": "query", "meta": "tokens", "format": "json"})
csrf = r["query"]["tokens"]["csrftoken"]

# Publish
r = post({
    "action": "edit",
    "title": wiki_page,
    "text": content,
    "summary": "Update from RELEASE_NOTES.md",
    "token": csrf,
    "format": "json",
})
result = r.get("edit", {}).get("result", "FAILED")
print(f"{wiki_page}: {result}")
if result != "Success":
    raise SystemExit(1)
