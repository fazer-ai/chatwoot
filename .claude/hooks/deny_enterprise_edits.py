#!/usr/bin/env python3
"""PreToolUse hook: enterprise/ and spec/enterprise/ stay identical to upstream, so the
agent is told where the change goes instead of editing them. Merging an upstream release
does not go through Edit/Write, so it is unaffected."""
import json
import os
import sys

event = json.load(sys.stdin)
tool_input = event.get('tool_input') or {}
path = tool_input.get('file_path') or tool_input.get('notebook_path') or ''
root = os.path.realpath(os.environ.get('CLAUDE_PROJECT_DIR') or event.get('cwd') or os.getcwd())
relative = os.path.relpath(os.path.realpath(os.path.join(root, path)), root)

if relative.split(os.sep)[0] == 'enterprise' or relative.startswith(os.path.join('spec', 'enterprise') + os.sep):
    reason = (
        f'{relative} is upstream Enterprise code and stays identical to the release in VERSION_CW '
        '(CI and the pre-commit hook check it). Put the change in fazer_ai_ee/ instead: a FazerAiEe:: '
        'module under fazer_ai_ee/app/<type>/fazer_ai_ee/ prepended over the class (see '
        'fazer_ai_ee/config/initializers/prepend_overrides.rb for Enterprise-only classes), a view '
        'under fazer_ai_ee/app/views, specs under fazer_ai_ee/spec. fazer_ai_ee/README.md has the details.'
    )
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'permissionDecisionReason': reason
    }}))
