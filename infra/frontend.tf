resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Placeholder page (replace later with real UI build artifacts)
resource "aws_s3_object" "static_index" {
  bucket       = aws_s3_bucket.static_site.id
  key          = "index.html"
  content_type = "text/html"
  content      = <<HTML
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>AWS RAG Chatbot</title>
  </head>
  <body>
    <h1>AWS RAG Chatbot</h1>
    <p>Frontend placeholder. Next commit wires UI to API Gateway.</p>
  </body>
</html>
HTML
}

resource "aws_cloudfront_origin_access_control" "static_oac" {
  name                              = "rag-chatbot-static-oac"
  description                       = "OAC for private S3 static_site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static_site" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id                = "s3-static-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-static-site"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "static_bucket_policy" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.static_site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.static_site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site" {
  bucket = aws_s3_bucket.static_site.id
  policy = data.aws_iam_policy_document.static_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.static_site]
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.static_site.domain_name}"
}