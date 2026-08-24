resource "aws_s3_bucket" "frontend" {
  bucket = "doro-erp-dev-alpha-frontend-${var.aws_account_id}"
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-alpha-frontend"
  description                       = "OAC for the private Dev Alpha SPA bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${local.name_prefix}-alpha-api"
  comment = "Forward API cookies, queries, and viewer headers except Host to preserve ALB origin TLS validation."

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allExcept"

    headers {
      items = ["host"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_security_group" "alpha_alb_frontend" {
  name        = "${local.name_prefix}-alpha-alb"
  description = "Allow CloudFront VPC origin traffic to the Dev Alpha internal ALB."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name = "${local.name_prefix}-alpha-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alpha_alb_from_cloudfront" {
  security_group_id = aws_security_group.alpha_alb_frontend.id
  description       = "HTTPS from the CloudFront origin-facing managed prefix list"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
}

resource "aws_vpc_security_group_egress_rule" "alpha_alb_all" {
  security_group_id = aws_security_group.alpha_alb_frontend.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_cloudfront_vpc_origin" "alpha_alb" {
  count = var.enable_gateway_backend ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${local.name_prefix}-alpha-alb"
    arn                    = data.aws_lb.gateway[0].arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    # CloudFront permits only TLS 1.2 when connecting to the ALB origin.
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${local.name_prefix}-alpha-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless frontend routes to the SPA entry point."
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
      } else if (!uri.split('/').pop().includes('.')) {
        request.uri = '/index.html';
      }

      return request;
    }
  EOT
}

resource "aws_acm_certificate" "frontend" {
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "alpha_alb" {
  domain_name       = var.alb_origin_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  edge_certificate_validation_options = merge(
    {
      for option in aws_acm_certificate.frontend.domain_validation_options : option.domain_name => {
        name   = option.resource_record_name
        record = option.resource_record_value
        type   = option.resource_record_type
      }
    },
    {
      for option in aws_acm_certificate.alpha_alb.domain_validation_options : option.domain_name => {
        name   = option.resource_record_name
        record = option.resource_record_value
        type   = option.resource_record_type
      }
    }
  )
}

resource "aws_route53_record" "certificate_validation" {
  for_each = local.edge_certificate_validation_options

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "frontend" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation[var.domain_name].fqdn]
}

resource "aws_acm_certificate_validation" "alpha_alb" {
  certificate_arn         = aws_acm_certificate.alpha_alb.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation[var.alb_origin_domain_name].fqdn]
}

resource "aws_route53_record" "alpha_alb_origin" {
  count = var.enable_gateway_backend ? 1 : 0

  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.alb_origin_domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.gateway[0].dns_name
    zone_id                = data.aws_lb.gateway[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_wafv2_web_acl" "frontend" {
  provider = aws.us_east_1

  name  = "${local.name_prefix}-alpha"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "doro-erp-dev-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "doro-erp-dev-alpha"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Doro ERP Dev Alpha"
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_200"
  web_acl_id          = aws_wafv2_web_acl.frontend.arn

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  dynamic "origin" {
    for_each = var.enable_gateway_backend ? [true] : []

    content {
      domain_name = var.alb_origin_domain_name
      origin_id   = "backend-alb"

      vpc_origin_config {
        vpc_origin_id            = aws_cloudfront_vpc_origin.alpha_alb[0].id
        origin_keepalive_timeout = 5
        origin_read_timeout      = 30
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 86400

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.enable_gateway_backend ? [true] : []

    content {
      path_pattern           = "/api/*"
      target_origin_id       = "backend-alb"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.frontend.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.alpha_alb,
    aws_route53_record.alpha_alb_origin,
    aws_s3_bucket_public_access_block.frontend
  ]
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.frontend.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}

resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}
