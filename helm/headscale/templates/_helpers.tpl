{{- define "headscale.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "headscale.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "headscale.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "headscale.labels" -}}
app.kubernetes.io/name: {{ include "headscale.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: control-plane
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 }}
{{- end -}}

{{- define "headscale.selectorLabels" -}}
app.kubernetes.io/name: {{ include "headscale.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "headscale.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "headscale.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "headscale.postgresql.labels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 }}
{{- end -}}

{{- define "headscale.postgresql.selectorLabels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end -}}

{{- define "headscale.dbSecretName" -}}
{{- if .Values.vault.enabled -}}
{{ .Values.vault.destinationSecretName | default (printf "%s-vault-db" (include "headscale.fullname" .)) }}
{{- else if .Values.postgresql.external.enabled -}}
{{ required "postgresql.external.existingSecret is required when external.enabled=true" .Values.postgresql.external.existingSecret }}
{{- else if .Values.postgresql.auth.existingSecret -}}
{{ .Values.postgresql.auth.existingSecret }}
{{- else -}}
{{ printf "%s-postgresql-auth" (include "headscale.fullname" .) }}
{{- end -}}
{{- end -}}

{{- define "headscale.dbSecretKey" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.existingSecretKey | default "password" }}{{- else -}}{{ .Values.postgresql.auth.existingSecretKey | default "password" }}{{- end -}}
{{- end -}}

{{- define "headscale.dbHost" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.host }}{{- else -}}{{ include "headscale.postgresql.fullname" . }}{{- end -}}
{{- end -}}

{{- define "headscale.dbPort" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.port }}{{- else -}}5432{{- end -}}
{{- end -}}

{{- define "headscale.dbName" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.database }}{{- else -}}{{ .Values.postgresql.auth.database }}{{- end -}}
{{- end -}}

{{- define "headscale.dbUser" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.username }}{{- else -}}{{ .Values.postgresql.auth.username }}{{- end -}}
{{- end -}}

{{- define "headscale.dbSSL" -}}
{{- if .Values.postgresql.external.enabled -}}{{ .Values.postgresql.external.ssl }}{{- else -}}{{ .Values.postgresql.clientConfig.ssl }}{{- end -}}
{{- end -}}

{{- define "headscale.uiBasicAuthSecretName" -}}
{{- if .Values.ui.basicAuth.existingSecret -}}
{{ .Values.ui.basicAuth.existingSecret }}
{{- else -}}
{{ printf "%s-ui-auth" (include "headscale.fullname" .) }}
{{- end -}}
{{- end -}}

{{- define "headscale.netpol.ingressControllerFrom" -}}
{{- if .Values.networkPolicy.ingressController.namespace -}}
- namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: {{ .Values.networkPolicy.ingressController.namespace }}
  podSelector:
    matchLabels:
      {{- toYaml .Values.networkPolicy.ingressController.podLabels | nindent 6 }}
{{- else -}}
# Same namespace as this release — pod-only selector
- podSelector:
    matchLabels:
      {{- toYaml .Values.networkPolicy.ingressController.podLabels | nindent 6 }}
{{- end -}}
{{- end -}}
