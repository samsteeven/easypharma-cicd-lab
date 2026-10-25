{{- define "easypharma.labels" -}}
app.kubernetes.io/name: easypharma
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "easypharma.selector" -}}
app.kubernetes.io/name: easypharma
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
