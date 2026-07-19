package provisioner

import gotemplate "text/template"

var (
	mainTemplate   = gotemplate.Must(gotemplate.New("main").Parse(mainTemplateText))
	mgmtTemplate   = gotemplate.Must(gotemplate.New("mgmt").Parse(mgmtTemplateText))
	agentTemplate  = gotemplate.Must(gotemplate.New("agent").Parse(agentTemplateText))
	eventsTemplate = gotemplate.Must(gotemplate.New("events").Parse(eventsTemplateText))
)

const mainTemplateText = `
error_log stderr {{ .ErrorLevel }};`

const eventsTemplateText = `
worker_connections {{ .WorkerConnections }};`

const mgmtTemplateText = `mgmt {
    {{- if .UsageEndpoint }}
    usage_report endpoint={{ .UsageEndpoint }};
    {{- end }}
    {{- if .SkipVerify }}
    ssl_verify off;
    {{- end }}
    {{- if .UsageCASecret }}
    ssl_trusted_certificate /etc/bws/certs-bootstrap/ca.crt;
    {{- end }}
    {{- if .UsageClientSSLSecret }}
    ssl_certificate        /etc/bws/certs-bootstrap/tls.crt;
    ssl_certificate_key    /etc/bws/certs-bootstrap/tls.key;
    {{- end }}
    enforce_initial_report off;
    deployment_context /etc/bws/main-includes/deployment_ctx.json;
}`

const agentTemplateText = `command:
    server:
        host: {{ .ServiceName }}.{{ .Namespace }}.svc
        port: 443
    auth:
        tokenpath: /var/run/secrets/bws-gateway/serviceaccount/token
    tls:
        cert: /var/run/secrets/bws-gateway/tls.crt
        key: /var/run/secrets/bws-gateway/tls.key
        ca: /var/run/secrets/bws-gateway/ca.crt
        server_name: {{ .ServiceName }}.{{ .Namespace }}.svc
allowed_directories:
- /opt/bws
- /usr/share/nginx
- /etc/bws
- /var/cache/bws
- /var/run/bws
- /var/log/bws-agent
- /var/run/secrets/bws
- /var/run/secrets/bws-gateway
features:
- configuration
- certificates
{{- if .EnableMetrics }}
- metrics
{{- end }}
{{- if eq true .WafEnabled }}
- logs-nap
{{- end }}
{{- if eq true .Plus }}
- api-action
{{- end }}
{{- if .LogLevel }}
log:
    level: {{ .LogLevel }}
{{- end }}
labels:
    {{- range $key, $value := .AgentLabels }}
    {{ $key }}: {{ $value }}
    {{- end }}

{{- if .NginxOneReporting }}
auxiliary_command:
    server:
        host: {{ .EndpointHost }}
        port: {{ .EndpointPort }}
        type: grpc
    auth:
        tokenpath: /etc/bws-agent/secrets/dataplane.key
    tls:
        skip_verify: {{ .EndpointTLSSkipVerify }}
{{- end }}
{{- if .EnableMetrics }}
collector:
    log:
       path: "stdout"
    exporters:
        prometheus:
            server:
                host: "0.0.0.0"
                port: {{ .MetricsPort }}
    pipelines:
        metrics:
{{- if .NginxOneReporting }}
            "ngf":
{{- else }}
            "default":
{{- end}}
                receivers: ["host_metrics", "nginx_metrics"]
                exporters: ["prometheus"]
{{- end }}
`
