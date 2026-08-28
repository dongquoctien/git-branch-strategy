#!/usr/bin/env bash
#
# pr-attach-images.sh — upload images to GitHub and print Markdown to embed
# in a PR body / issue comment.
#
# GitHub has no official REST endpoint for attaching images to a PR body; the
# web UI uses uploads.github.com. This script drives that same endpoint with
# the token `gh` already holds, so screenshots can be embedded without opening
# a browser.
#
#   ⚠ The upload endpoint is UNDOCUMENTED and unsupported by GitHub. It can
#     break without notice. On failure this script exits non-zero and prints a
#     fallback; it never leaves a half-written PR body behind.
#
# Usage:
#   pr-attach-images.sh --repo OWNER/NAME [options] [FILE...]
#
# Options:
#   --repo OWNER/NAME    Target repo (default: origin of the current git repo)
#   --jira ISSUE-KEY     Also pull image attachments from this Jira issue
#   --jira-only NAMES    Comma-separated attachment filenames to take from Jira
#                        (default: every image on the issue)
#   --width N            Emit <img width="N"> instead of plain Markdown
#   --title TEXT         Heading printed above the images
#   --dry-run            Resolve and list what would be uploaded; upload nothing
#   -h, --help           Show this help
#
# Environment (Jira mode only):
#   JIRA_URL, JIRA_USERNAME, JIRA_API_TOKEN
#
# Output: Markdown on stdout. Progress and warnings go to stderr, so
#         `pr-attach-images.sh ... > body.md` yields a clean fragment.
#
# Exit codes: 0 ok · 1 usage/precondition · 2 upload failed · 3 Jira fetch failed

set -euo pipefail

REPO=""
JIRA_KEY=""
JIRA_ONLY=""
WIDTH=""
TITLE=""
DRY_RUN=0
FILES=()

die() { printf 'error: %s\n' "$*" >&2; exit "${2:-1}"; }
note() { printf '%s\n' "$*" >&2; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="${2:-}"; shift 2 ;;
    --jira)      JIRA_KEY="${2:-}"; shift 2 ;;
    --jira-only) JIRA_ONLY="${2:-}"; shift 2 ;;
    --width)     WIDTH="${2:-}"; shift 2 ;;
    --title)     TITLE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do FILES+=("$1"); shift; done ;;
    -*) die "unknown option: $1" ;;
    *)  FILES+=("$1"); shift ;;
  esac
done

command -v gh   >/dev/null 2>&1 || die "gh CLI not found"
command -v curl >/dev/null 2>&1 || die "curl not found"

if [[ -n "$WIDTH" && ! "$WIDTH" =~ ^[0-9]+$ ]]; then
  die "--width must be a positive integer, got: $WIDTH"
fi

# --- Resolve repo -----------------------------------------------------------
if [[ -z "$REPO" ]]; then
  ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$ORIGIN" ]] || die "no --repo given and no git origin found"
  case "$ORIGIN" in
    *bitbucket.org*)
      note "warning: origin is Bitbucket ($ORIGIN)."
      note "         Bitbucket has no equivalent upload endpoint, so images are"
      note "         not embedded. Link the Jira ticket in the PR body instead."
      exit 1 ;;
    *github.com*)
      REPO="$(sed -E 's#.*github\.com[:/]([^/]+/[^/]+?)(\.git)?/?$#\1#' <<<"$ORIGIN")" ;;
    *)
      die "origin is neither GitHub nor Bitbucket: $ORIGIN" ;;
  esac
fi

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

REPO_ID="$(gh api "repos/$REPO" --jq .id 2>/dev/null)" \
  || die "cannot read repo $REPO — check the name and your gh account"

TOKEN="$(gh auth token)"
[[ -n "$TOKEN" ]] || die "gh auth token returned empty"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- Collect Jira attachments ----------------------------------------------
if [[ -n "$JIRA_KEY" ]]; then
  : "${JIRA_URL:?JIRA_URL is required for --jira}"
  : "${JIRA_USERNAME:?JIRA_USERNAME is required for --jira}"
  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN is required for --jira}"

  JIRA_AUTH="$(printf '%s:%s' "$JIRA_USERNAME" "$JIRA_API_TOKEN" | base64 -w0 2>/dev/null \
               || printf '%s:%s' "$JIRA_USERNAME" "$JIRA_API_TOKEN" | base64)"

  note "fetching attachments from $JIRA_KEY ..."
  META="$WORKDIR/_issue.json"
  curl -sf -H "Authorization: Basic $JIRA_AUTH" -H "Accept: application/json" \
    "${JIRA_URL%/}/rest/api/3/issue/${JIRA_KEY}?fields=attachment" -o "$META" \
    || die "cannot fetch Jira issue $JIRA_KEY" 3

  # Jira sometimes reports mimeType null, so fall back to the file extension.
  ATTACHMENTS="$(
    ATT_FILTER="$JIRA_ONLY" python -c '
import json, os, sys
only = [n.strip() for n in os.environ.get("ATT_FILTER", "").split(",") if n.strip()]
exts = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
for att in data.get("fields", {}).get("attachment", []) or []:
    name = att.get("filename") or ""
    mime = att.get("mimeType") or ""
    if not (mime.startswith("image/") or name.lower().endswith(exts)):
        continue
    if only and name not in only:
        continue
    print(str(att.get("id")) + "\t" + name)
' "$META"
  )" || die "cannot parse Jira attachment list" 3

  if [[ -z "$ATTACHMENTS" ]]; then
    note "warning: no image attachments matched on $JIRA_KEY"
  fi

  # Strip CR: Python on Windows emits CRLF, which would otherwise end up
  # inside the filename and break the download path.
  while IFS=$'\t' read -r att_id att_name; do
    att_id="${att_id%$'\r'}"; att_name="${att_name%$'\r'}"
    [[ -n "$att_id" && -n "$att_name" ]] || continue
    dest="$WORKDIR/$att_name"
    # -L: the content endpoint 303-redirects to Media Services.
    if curl -sfL -H "Authorization: Basic $JIRA_AUTH" \
         "${JIRA_URL%/}/rest/api/3/attachment/content/$att_id" -o "$dest"; then
      FILES+=("$dest")
      note "  pulled $att_name"
    else
      note "  warning: failed to download $att_name (id=$att_id), skipping"
    fi
  done < <(printf '%s\n' "$ATTACHMENTS")
fi

[[ ${#FILES[@]} -gt 0 ]] || die "no images to upload"

# --- Upload -----------------------------------------------------------------
mime_for() {
  case "${1,,}" in
    *.png) echo image/png ;;
    *.jpg|*.jpeg) echo image/jpeg ;;
    *.gif) echo image/gif ;;
    *.webp) echo image/webp ;;
    *.bmp) echo image/bmp ;;
    *) echo "" ;;
  esac
}

urlencode() {
  python -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"
}

[[ -n "$TITLE" ]] && printf '### %s\n\n' "$TITLE"

failed=0
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { note "warning: not found, skipping: $f"; continue; }
  base="$(basename "$f")"
  mime="$(mime_for "$base")"
  if [[ -z "$mime" ]]; then
    note "warning: not a supported image type, skipping: $base"
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    note "would upload $base ($(wc -c <"$f") bytes) -> $REPO"
    continue
  fi

  resp="$(curl -s --fail-with-body \
      "https://uploads.github.com/user-attachments/assets?name=$(urlencode "$base")&content_type=$mime&repository_id=$REPO_ID" \
      -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json" \
      --data-binary "@$f" 2>&1)" || {
    note "error: upload failed for $base"
    note "       response: ${resp:0:300}"
    failed=1
    continue
  }

  url="$(python -c 'import sys,json;print(json.load(sys.stdin).get("url",""))' <<<"$resp" 2>/dev/null || true)"
  url="${url%$'\r'}"
  if [[ -z "$url" ]]; then
    note "error: no url in response for $base: ${resp:0:200}"
    failed=1
    continue
  fi

  if [[ -n "$WIDTH" ]]; then
    printf '<img src="%s" width="%s" alt="%s" />\n\n' "$url" "$WIDTH" "$base"
  else
    printf '![%s](%s)\n\n' "$base" "$url"
  fi
  note "  uploaded $base"
done

if [[ $failed -ne 0 ]]; then
  note ""
  note "One or more uploads failed. The uploads.github.com endpoint is"
  note "undocumented and may have changed. Fallback: commit the images under"
  note "docs/images/ and reference them by raw URL, or attach them to the Jira"
  note "ticket and link it from the PR body."
  exit 2
fi
