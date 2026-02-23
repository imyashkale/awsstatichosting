output "website_url" {
  value = module.static_site.website_url
}

output "s3_bucket_name" {
  value = module.static_site.s3_bucket_name
}

output "cloudfront_distribution_id" {
  value = module.static_site.cloudfront_distribution_id
}
