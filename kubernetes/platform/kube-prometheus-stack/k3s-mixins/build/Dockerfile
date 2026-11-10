FROM golang:1.27.1-alpine AS build
LABEL stage=builder

WORKDIR /k3s-mixins

COPY src/ .

RUN ls -la *

# Install required packages
RUN apk add git

# Install jsonnet and the jsonnet-bundler
# renovate: datasource=github-releases depName=google/go-jsonnet
ARG JSONNET_VERSION=v0.22.0
RUN go install github.com/google/go-jsonnet/cmd/jsonnet@${JSONNET_VERSION}
# renovate: datasource=github-releases depName=jsonnet-bundler/jsonnet-bundler
ARG JB_VERSION=v0.6.0
RUN go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@${JB_VERSION}

# Install gojsontoyaml
# renovate: datasource=github-releases depName=brancz/gojsontoyaml
ARG GOJSONTOYAML_VERSION=v0.1.0
RUN go install github.com/brancz/gojsontoyaml@${GOJSONTOYAML_VERSION}

# Init Jsonnet project
RUN jb init

# Install mixins from their branches: running this build is how the mixins get
# updated; its output is committed and reviewed
RUN jb install github.com/kubernetes-monitoring/kubernetes-mixin@master
RUN jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
RUN jb install github.com/povilasv/coredns-mixin@master

# RUN jsonnet main.jsonnet -J vendor > generated.json

# Create output directory for the manifest files
RUN mkdir templates

# Execute command to generate
RUN chmod +x generate.sh
RUN ./generate.sh

FROM scratch AS mixins
COPY --from=build /k3s-mixins/templates /