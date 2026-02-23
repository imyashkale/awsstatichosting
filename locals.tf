locals {
  bucket_name  = "${replace(var.domain_name, ".", "-")}-${var.environment}-website"
  s3_origin_id = "${var.project_name}-${var.environment}-s3-origin"
}
