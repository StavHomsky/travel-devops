# One environment of the travel app: a namespace + the Helm chart.
variable "environment" { type = string }
variable "chart_path" { type = string }
variable "image_tag" { type = string }
variable "ingress_host" { type = string }
variable "postgres_password" {
  type      = string
  sensitive = true
}
variable "secret_key" {
  type      = string
  sensitive = true
}

resource "kubernetes_namespace_v1" "this" {
  metadata { name = "travel-${var.environment}" }
}

resource "helm_release" "travel" {
  name      = "travel"
  namespace = kubernetes_namespace_v1.this.metadata[0].name
  chart     = var.chart_path

  set = [
    { name = "backend.image.repository", value = "stavdevops/travel-backend" },
    { name = "backend.image.tag", value = var.image_tag },
    { name = "frontend.image.repository", value = "stavdevops/travel-frontend" },
    { name = "frontend.image.tag", value = var.image_tag },
    { name = "ingress.host", value = var.ingress_host },
  ]
  # sensitive = hidden in plan output and logs
  set_sensitive = [
    { name = "secrets.postgresPassword", value = var.postgres_password },
    { name = "secrets.secretKey", value = var.secret_key },
  ]
}

output "namespace" { value = kubernetes_namespace_v1.this.metadata[0].name }
