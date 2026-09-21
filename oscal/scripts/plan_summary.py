#!/usr/bin/env python3
"""
Reviewer-facing rollup of a Terraform plan (#474, folds in #285).

Turns `terraform show -json <plan>` into a concise summary a reviewer can scan
without reading the whole plan: a headline (how many changes, are any
destructive) + a per-resource table (Resource | Add/Delete/Change | Changes).

The headline calls out destructive changes LOUDLY — a delete, or a replace of a
resource type that does NOT naturally revision. Replaces of revisioning types
(e.g. aws_ecs_task_definition, which mints a new revision on every change) are
benign and are labelled as such rather than as destroys.

Usage (stdin -> stdout):
    terraform show -json tfplan | python3 oscal/scripts/plan_summary.py
    python3 oscal/scripts/plan_summary.py < plan.json >> summary.md
"""

import json
import sys

# Resource types where a "replace" (create+delete) is a benign new revision /
# version bump, not a destructive teardown — don't count these as destructive.
REVISIONING_TYPES = {
    "aws_ecs_task_definition",
    "aws_iam_policy",            # new version via create/delete of the version
    "aws_launch_template",
}


def _actions(change):
    return change.get("actions", [])


def classify(change):
    """-> one of: create, update, delete, replace, no-op."""
    a = _actions(change)
    if a == ["no-op"] or a == []:
        return "no-op"
    if "create" in a and "delete" in a:
        return "replace"
    if a == ["create"]:
        return "create"
    if a == ["delete"]:
        return "delete"
    if a == ["update"]:
        return "update"
    return "+".join(a)


def changed_keys(change):
    """Top-level attribute keys that differ before->after (for 'what changed')."""
    before = change.get("before") or {}
    after = change.get("after") or {}
    keys = set(before) | set(after)
    return sorted(k for k in keys if before.get(k) != after.get(k))


def describe(kind, change):
    if kind == "create":
        return "created"
    if kind == "delete":
        return "**deleted**"
    keys = changed_keys(change)
    shown = ", ".join(keys[:6]) + ("…" if len(keys) > 6 else "")
    if kind == "replace":
        return f"replaced (forces new; changed: {shown or 'n/a'})"
    return f"changed: {shown or 'n/a'}"


def is_destructive(rtype, kind):
    if kind == "delete":
        return True
    if kind == "replace":
        return rtype not in REVISIONING_TYPES
    return False


ADCH = {"create": "add", "delete": "delete", "update": "change",
        "replace": "change"}


def build(plan):
    rcs = [rc for rc in plan.get("resource_changes", [])
           if classify(rc.get("change", {})) != "no-op"]
    rows, destructive, benign_replace = [], [], []
    counts = {"create": 0, "update": 0, "replace": 0, "delete": 0, "other": 0}
    for rc in rcs:
        change = rc.get("change", {})
        kind = classify(change)
        counts[kind if kind in counts else "other"] += 1
        rtype = rc.get("type", "")
        rows.append((rc.get("address", "?"), ADCH.get(kind, kind), describe(kind, change)))
        if is_destructive(rtype, kind):
            destructive.append(rc.get("address", "?"))
        elif kind == "replace":
            benign_replace.append(rc.get("address", "?"))

    out = ["## Plan rollup", ""]
    if not rcs:
        out += ["**No changes.** Infrastructure matches configuration.", ""]
        return "\n".join(out)

    out.append(
        f"**{len(rcs)}** resource change(s): "
        f"{counts['create']} add · {counts['update']} in-place · "
        f"{counts['replace']} replace · {counts['delete']} delete"
    )
    out.append("")
    if destructive:
        out.append(f"### 🔴 Destructive: {len(destructive)} "
                   "(delete / replace of non-revisioning resources)")
        for a in destructive:
            out.append(f"- `{a}`")
    else:
        out.append("### ✅ Destructive (delete / non-revisioning replace): 0")
    if benign_replace:
        out.append(f"\n> {len(benign_replace)} replace(s) are benign revisions "
                   "(task-def/policy-version/etc.), not teardowns.")
    out += ["", "| Resource | Add / Delete / Change | Changes |",
            "|---|---|---|"]
    for addr, adch, desc in rows:
        out.append(f"| `{addr}` | {adch} | {desc} |")
    out.append("")
    return "\n".join(out)


def main():
    # stdin -> stdout only (no CLI file paths → no path-injection surface; the
    # workflow pipes `terraform show -json … | plan_summary.py >> $STEP_SUMMARY`).
    raw = sys.stdin.read()
    if not raw.strip():
        sys.stderr.write("plan_summary: empty input\n")
    else:
        print(build(json.loads(raw)))


if __name__ == "__main__":
    main()
