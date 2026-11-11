variable "image_tag" { type = string }
variable "postgres_password" {
  type      = string
  sensitive = true
}
variable "secret_key" {
  type      = string
  sensitive = true
}

# The workspace name (dev / prod) picks the environment.
module "travel_app" {
  source            = "./modules/travel-app"
  environment       = terraform.workspace
  chart_path        = "${path.module}/../helm/travel-app"
  image_tag         = var.image_tag
  ingress_host      = "${terraform.workspace}.travel.local"
  postgres_password = var.postgres_password
  secret_key        = var.secret_key
}

output "namespace" { value = module.travel_app.namespace }
