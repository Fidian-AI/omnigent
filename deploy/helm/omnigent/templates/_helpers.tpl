{{/*
Expand the name of the chart.
*/}}
{{- define "omnigent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, truncated per the DNS label limit.
*/}}
{{- define "omnigent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "omnigent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "omnigent.labels" -}}
helm.sh/chart: {{ include "omnigent.chart" . }}
{{ include "omnigent.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "omnigent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "omnigent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Server Secret name: pre-created override or the chart-managed one.
*/}}
{{- define "omnigent.secretName" -}}
{{- .Values.existingSecret | default (printf "%s-secrets" (include "omnigent.fullname" .)) }}
{{- end }}

{{/*
Whether the built-in accounts provider is active (it is the server's default
when auth is enabled and no other provider is pinned).
*/}}
{{- define "omnigent.accountsAuth" -}}
{{- if and .Values.auth.enabled (or (not .Values.auth.provider) (eq .Values.auth.provider "accounts")) }}true{{- end }}
{{- end }}

{{/*
DATABASE_URL: built from the in-cluster Postgres values, or taken verbatim
from database.url for an external database.
*/}}
{{- define "omnigent.databaseUrl" -}}
{{- if .Values.postgres.enabled }}
{{- $password := required "postgres.password is required when postgres.enabled (or set existingSecret)" .Values.postgres.password }}
{{- printf "postgresql+psycopg://%s:%s@%s:5432/%s" .Values.postgres.username $password (include "omnigent.postgres.fullname" .) .Values.postgres.database }}
{{- else }}
{{- required "database.url is required when postgres.enabled=false (or set existingSecret)" .Values.database.url }}
{{- end }}
{{- end }}

{{/*
Suffixed names re-truncate the base so suffix + name stays within the
63-char DNS label limit even with a long fullnameOverride.
*/}}
{{- define "omnigent.postgres.fullname" -}}
{{- printf "%s-postgres" (include "omnigent.fullname" . | trunc 54 | trimSuffix "-") }}
{{- end }}

{{/*
ServiceAccount the server runs as (only used with the sandbox provider).
*/}}
{{- define "omnigent.serverServiceAccountName" -}}
{{- printf "%s-server" (include "omnigent.fullname" . | trunc 56 | trimSuffix "-") }}
{{- end }}

{{- define "omnigent.runnerServiceAccountName" -}}
{{- printf "%s-runner" (include "omnigent.fullname" . | trunc 56 | trimSuffix "-") }}
{{- end }}

{{/*
Harness-credentials Secret projected into runner Pods.
*/}}
{{- define "omnigent.credsSecretName" -}}
{{- .Values.sandboxes.credentials.existingSecret | default (printf "%s-creds" (include "omnigent.fullname" . | trunc 57 | trimSuffix "-")) }}
{{- end }}

{{/*
URL runner Pods dial back to: explicit override or the in-cluster Service DNS
(port included so a non-default service.port keeps working).
*/}}
{{- define "omnigent.sandboxServerUrl" -}}
{{- .Values.sandboxes.serverUrl | default (printf "http://%s.%s.svc.cluster.local:%v" (include "omnigent.fullname" .) .Release.Namespace .Values.service.port) }}
{{- end }}
