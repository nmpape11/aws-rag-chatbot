output "static_site_bucket" {
  value = aws_s3_bucket.static_site.bucket
}

output "knowledge_docs_bucket" {
  value = aws_s3_bucket.knowledge_docs.bucket
}