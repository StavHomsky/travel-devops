{{/*
Common labels - put on every object so you can find everything that
belongs to this release:  kubectl get all -l app.kubernetes.io/instance=travel
*/}}
{{- define "travel.labels" -}}
app.kubernetes.io/name: travel-app
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Selector labels - the smaller, never-changing set a Service or Deployment
uses to find its pods. (Selectors can't be changed after creation, so the
version label must NOT be in here.)
*/}}
{{- define "travel.selectorLabels" -}}
app.kubernetes.io/name: travel-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret: the one we create, or an existing one if given.
*/}}
{{- define "travel.secretName" -}}
{{- .Values.secrets.existingSecret | default (printf "%s-secrets" .Release.Name) -}}
{{- end }}
