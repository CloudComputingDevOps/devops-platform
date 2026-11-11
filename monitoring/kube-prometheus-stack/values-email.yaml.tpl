# Generado por scripts/install-monitoring.sh — no editar a mano en el repo.
alertmanager:
  config:
    global:
      smtp_smarthost: "${SMTP_SMARTHOST}"
      smtp_from: "${SMTP_FROM}"
      smtp_auth_username: "${SMTP_AUTH_USERNAME}"
      smtp_auth_password: "${SMTP_AUTH_PASSWORD}"
      smtp_require_tls: true
    receivers:
      - name: "null"
      - name: devops-notifications
        webhook_configs:
          - url: http://alertmanager-webhook.monitoring.svc.cluster.local:8080/alert
            send_resolved: true
            max_alerts: 10
        email_configs:
          - to: "${ALERT_EMAIL_TO}"
            send_resolved: true
            headers:
              Subject: "[DevOps] {{ .Status | toUpper }}: {{ .CommonLabels.alertname }}"
            html: |
              <h3>Alerta DevOps Platform</h3>
              <p><b>Estado:</b> {{ .Status }}</p>
              {{ range .Alerts }}
              <hr/>
              <p><b>{{ .Labels.alertname }}</b> ({{ .Labels.severity }})</p>
              <p>{{ .Annotations.summary }}</p>
              <p>{{ .Annotations.description }}</p>
              {{ end }}
