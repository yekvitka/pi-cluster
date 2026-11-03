# App template

A [gruntwork-io/boilerplate](https://github.com/gruntwork-io/boilerplate) template for a new Flux app in the layout every app in `kubernetes/platform/` uses.

```shell
go install github.com/gruntwork-io/boilerplate@latest   # once

cd boilerplate
make vars-example                       # creates fluxcd-app-template-vars.yaml
$EDITOR fluxcd-app-template-vars.yaml   # app_name, app_namespace, chart_repo_url, chart_name, chart_version, chart_release_name
make generate-fluxcd-app OUTPUT_DIR=../kubernetes/platform/<app_name>
```

Without `OUTPUT_DIR` the app goes to `output/<app_name>` (`output/` when `yq` is not installed).

## What it generates

```text
<app_name>/
├── app.yaml                 Flux Kustomizations <app>-app and <app>-config (config depends on app)
├── app/
│   ├── base/                namespace, HelmRepository + HelmRelease, values ConfigMap
│   ├── components/          reusable value and patch bundles (componentX as the example)
│   └── overlays/{dev,prod}/ per-environment values, appended to valuesFrom
└── config/                  resources applied after the chart (base, overlays/{dev,prod})
```

To deploy, move `app.yaml` to `kubernetes/clusters/prod/infra/<app_name>-app.yaml` and add it to that directory's `kustomization.yaml`.
