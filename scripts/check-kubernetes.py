#!/usr/bin/env python3
"""Render every Flux Kustomization the way Flux does, then validate the result.

For each Flux Kustomization in kubernetes/clusters/<env>/: build its path with
kustomize; apply its postBuild substitution with `flux envsubst --strict` (the
same library as kustomize-controller), using the variables of its
cluster-settings ConfigMap and spec.postBuild.substitute, and skipping
resources annotated kustomize.toolkit.fluxcd.io/substitute: disabled; validate
every resource with kubeconform. The directories Flux applies directly
(clusters/<env>/config, infra) are built and validated too.

Strict substitution fails on a variable without a value or default, where Flux
would substitute an empty string: a typo in a variable name fails here.

Needs kubectl, flux and kubeconform in PATH, and PyYAML.
Usage: scripts/check-kubernetes.py [repository root]
"""
import os
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
CLUSTERS = ROOT / "kubernetes" / "clusters"
DISABLED = "kustomize.toolkit.fluxcd.io/substitute"
CRD_SCHEMAS = ("https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/"
               "{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")


def run(cmd, stdin=None, env=None):
    return subprocess.run(cmd, input=stdin, env=env, capture_output=True, text=True)


def cluster_settings(env):
    path = CLUSTERS / env / "config" / "cluster-settings.yaml"
    for doc in yaml.safe_load_all(path.read_text()):
        if doc and doc.get("kind") == "ConfigMap" and doc["metadata"]["name"] == "cluster-settings":
            return {k: str(v) for k, v in (doc.get("data") or {}).items()}
    return {}


def flux_kustomizations(env):
    for path in sorted((CLUSTERS / env).rglob("*.y*ml")):
        for doc in yaml.safe_load_all(path.read_text()):
            if (doc and doc.get("kind") == "Kustomization"
                    and doc.get("apiVersion", "").startswith("kustomize.toolkit.fluxcd.io/")):
                yield doc


def substitute(rendered, spec, settings):
    post = spec.get("postBuild") or {}
    if not post:
        return rendered, None
    values = {}
    for source in post.get("substituteFrom") or []:
        if source.get("kind") == "ConfigMap" and source.get("name") == "cluster-settings":
            values.update(settings)
        elif not source.get("optional", False):
            return None, f"substituteFrom {source.get('kind')}/{source.get('name')} is not in the repository"
    values.update({k: str(v) for k, v in (post.get("substitute") or {}).items()})

    keep, subst = [], []
    for doc in yaml.safe_load_all(rendered):
        if not doc:
            continue
        annotations = (doc.get("metadata") or {}).get("annotations") or {}
        (keep if annotations.get(DISABLED) == "disabled" else subst).append(doc)
    # Only the variables Flux has: never the environment of this process
    out = run(["flux", "envsubst", "--strict"], stdin=yaml.safe_dump_all(subst),
              env={"PATH": os.environ["PATH"], **values})
    if out.returncode != 0:
        return None, out.stderr.strip()
    return yaml.safe_dump_all(keep) + "---\n" + out.stdout, None


def validate(manifests):
    out = run(["kubeconform", "-strict", "-ignore-missing-schemas", "-summary", "-output", "text",
               "-schema-location", "default", "-schema-location", CRD_SCHEMAS, "-"], stdin=manifests)
    return out.returncode == 0, (out.stdout + out.stderr).strip()


def main():
    failures, checked = [], 0
    for env in sorted(p.name for p in CLUSTERS.iterdir() if p.is_dir()):
        settings = cluster_settings(env)
        targets = [(f"{env}/{d.name}", d, {}) for d in sorted((CLUSTERS / env).iterdir())
                   if (d / "kustomization.yaml").exists()]
        targets += [(f"{env}/{k['metadata']['name']}", ROOT / k["spec"]["path"], k["spec"])
                    for k in flux_kustomizations(env)]
        for name, path, spec in targets:
            checked += 1
            built = run(["kubectl", "kustomize", str(path)])
            if built.returncode != 0:
                failures.append((name, "kustomize: " + built.stderr.strip()))
                continue
            manifests, error = substitute(built.stdout, spec, settings)
            if error:
                failures.append((name, "substitution: " + error))
                continue
            ok, report = validate(manifests)
            if not ok:
                failures.append((name, report))
    for name, error in failures:
        print(f"FAIL {name}\n  " + error.replace("\n", "\n  "))
    print(f"{checked} checked, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
