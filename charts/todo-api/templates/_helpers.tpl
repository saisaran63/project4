{{- define "todo-api.name" -}}
{{ include "todo-api.chart" . }}
{{- end -}}

{{- define "todo-api.chart" -}}
{{ .Chart.Name }}
{{- end -}}

{{- define "todo-api.fullname" -}}
{{ .Release.Name }}
{{- end -}}
