resource "tls_private_key" "support" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "support" {
  private_key_pem = tls_private_key.support.private_key_pem
  subject {
    common_name  = "blabla.com"
    organization = "Blabla ACME blabla, Inc"
  }
  validity_period_hours = 900
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "cert" {
  private_key      = tls_private_key.support.private_key_pem
  certificate_body = tls_self_signed_cert.support.cert_pem
  tags = {
    Environment = "test"
  }
}

locals {
  cert_json = jsonencode({
    Certificate     = tls_self_signed_cert.support.cert_pem
    PrivateKey      = tls_private_key.support.private_key_pem
  })
}

