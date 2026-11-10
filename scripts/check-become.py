#!/usr/bin/env python3
"""Check that Ansible becomes root where it must, and only there.

Ansible logs in to the nodes as the unprivileged ansible user, so a node play
without `become` fails at runtime, in the middle of a rebuild. Rules:

- every play that targets hosts other than the control host sets `become`;
- every task delegated to the control host (delegate_to: localhost or
  local_action) inside a play with become, or in a task file or role that such
  a play may include, sets `become` itself or on an enclosing block. Otherwise
  it inherits become: sudo inside the runner, and files it writes belong to root;
- every task delegated to a node from a control host play, or in a task file or
  role, sets `become` the same way: a control host play runs without it.

Usage: scripts/check-become.py [repository root]
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
ANSIBLE = ROOT / "ansible"
CONTROL = {"localhost", "127.0.0.1", "pimaster", "control"}
NOT_PLAYBOOKS = {"inventory.yml", "requirements.yml"}
TASK_LISTS = ("pre_tasks", "tasks", "post_tasks", "handlers")
BLOCK_LISTS = ("block", "rescue", "always")


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def delegated_locally(task):
    return "local_action" in task or str(task.get("delegate_to", "")).strip() in CONTROL


def delegated_to_node(task):
    target = task.get("delegate_to")
    return target is not None and str(target).strip() not in CONTROL


def check_tasks(tasks, where, become_set, errors, local=True, remote=True):
    """become_set: an enclosing block sets become. local/remote: check tasks
    delegated to the control host / to a node."""
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        name = task.get("name", "<unnamed>")
        own = "become" in task
        if any(key in task for key in BLOCK_LISTS):
            for key in BLOCK_LISTS:
                check_tasks(task.get(key), where, become_set or own, errors, local, remote)
            continue
        if own or become_set:
            continue
        if local and delegated_locally(task):
            errors.append(f"{where}: task '{name}' runs on the control host without become: false")
        if remote and delegated_to_node(task):
            errors.append(f"{where}: task '{name}' runs on {task['delegate_to']} without become")


def check_playbook(path, errors):
    plays = load(path) or []
    for play in plays:
        if not isinstance(play, dict) or "hosts" not in play:
            continue  # import_playbook
        hosts = {h.strip() for h in str(play["hosts"]).split(",")}
        where = f"{path.relative_to(ROOT)}: play '{play.get('name', play['hosts'])}'"
        if hosts <= CONTROL:
            if not play.get("become"):
                for key in TASK_LISTS:
                    check_tasks(play.get(key), where, False, errors, local=False)
            continue
        if "become" not in play:
            errors.append(f"{where} targets {play['hosts']} without become")
            continue
        if play["become"] is False:
            continue
        for key in TASK_LISTS:
            check_tasks(play.get(key), where, False, errors, remote=False)


def main():
    errors = []
    for path in sorted(ANSIBLE.glob("*.yml")):
        if path.name not in NOT_PLAYBOOKS:
            check_playbook(path, errors)
    # Task files and roles of this repository (Galaxy roles are installed elsewhere)
    task_files = list((ANSIBLE / "tasks").glob("*.yml"))
    task_files += [p for p in (ANSIBLE / "roles").rglob("*.y*ml")
                   if p.parent.name in ("tasks", "handlers")]
    for path in sorted(task_files):
        check_tasks(load(path), str(path.relative_to(ROOT)), False, errors)
    for error in errors:
        print(error)
    if errors:
        return 1
    print("become: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
