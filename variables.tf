variable "project_name" {
  description = "Project name used as a prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "domain_name" {
  description = "Custom domain for the website (e.g. example.com). A Route53 hosted zone must already exist for this domain."
  type        = string
}

variable "enable_custom_domain" {
  description = "Toggle CloudFront alternate domain alias + Route53 A/AAAA records. When false, the site is only accessible via the *.cloudfront.net URL."
  type        = bool
  default     = true
}

variable "default_root_object" {
  description = "Default root object served by CloudFront"
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_All | PriceClass_200 | PriceClass_100)"
  type        = string
  default     = "PriceClass_100"
}

variable "spa_mode" {
  description = "When true, 403/404 errors are rewritten to /index.html (single-page app support)"
  type        = bool
  default     = true
}

variable "enable_url_rewrite_function" {
  description = "When true, attaches a CloudFront Function that rewrites directory URIs to index.html (e.g. /about → /about/index.html). Disable for pure SPA apps that only need spa_mode."
  type        = bool
  default     = true
}

variable "enable_cf_logging" {
  description = "When true, creates a dedicated S3 bucket and enables CloudFront access logging."
  type        = bool
  default     = false
}
