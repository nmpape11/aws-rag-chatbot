resource "aws_s3_bucket" "static_site" {
  bucket_prefix = "rag-chatbot-static-"
}

resource "aws_s3_bucket" "knowledge_docs" {
  bucket_prefix = "rag-chatbot-kb-"
}