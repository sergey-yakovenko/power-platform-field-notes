#!/bin/bash
# Verification gate for every task: manifests parse, skills are well-formed, no project leakage.
set -e
cd "$(dirname "$0")/.."

python3 -m json.tool .claude-plugin/marketplace.json >/dev/null
python3 -m json.tool plugins/field-notes/.claude-plugin/plugin.json >/dev/null

shopt -s nullglob
for f in plugins/field-notes/skills/*/SKILL.md; do
  [ "$(head -1 "$f")" = "---" ] || { echo "FAIL no frontmatter: $f"; exit 1; }
  grep -q '^name:' "$f"        || { echo "FAIL no name: $f"; exit 1; }
  grep -q '^description:' "$f" || { echo "FAIL no description: $f"; exit 1; }
done

# Project-specific leakage: the extension carries platform truths only.
# (author frontmatter lines and the sanctioned scr_Example placeholder are exempt)
if grep -rInE 'sdc_|syc365|SYC365|Yakovenko|R2026|scr_[A-Z]|gblRelease|gblParticipation|gblProject|cmpListPane|cmpNavShell|cmpSaveBar|jti' plugins/field-notes/skills/ | grep -vE 'author: Sergey Yakovenko|scr_Example' ; then
  echo "FAIL project-specific leakage above"; exit 1
fi
echo "check.sh: OK"
