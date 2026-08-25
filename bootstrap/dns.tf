resource "aws_route53_zone" "public" {
  name = var.hosted_zone_name
}
