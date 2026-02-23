module "static_site" {
  source = "git::https://github.com/<your-org>/awshosting.git?ref=v1.0.0"

  # ── Required ──────────────────────────────────────────────────────────────
  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name

  # ── Optional (shown with defaults) ────────────────────────────────────────
  # enable_custom_domain = true
  # default_root_object  = "index.html"
  # price_class          = "PriceClass_100"
  # spa_mode             = true

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
