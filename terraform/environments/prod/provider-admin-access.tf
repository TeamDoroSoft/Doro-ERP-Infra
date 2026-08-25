resource "aws_ssm_document" "provider_admin_port_forwarding" {
  count = var.provider_admin_remote_host == null ? 0 : 1

  name            = "${local.name_prefix}-provider-admin-port-forwarding"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Port forwarding only to the fixed Provider Admin internal ALB HTTPS endpoint."
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        description    = "Fixed local TLS tunnel port for the Provider Admin OIDC redirect contract."
        default        = "8443"
        allowedPattern = "^8443$"
      }
    }
    properties = {
      host            = var.provider_admin_remote_host
      portNumber      = "443"
      localPortNumber = "{{ localPortNumber }}"
    }
  })

  tags = {
    Name = "${local.name_prefix}-provider-admin-port-forwarding"
  }
}
