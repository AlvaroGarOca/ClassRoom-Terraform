output "s3_bucket_name" {
  value = aws_s3_bucket.website_bucket.bucket
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.website_distribution.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.website_distribution.id
}

output "route53_alias_record" {
  value = aws_route53_record.cloudfront_alias.fqdn
}
