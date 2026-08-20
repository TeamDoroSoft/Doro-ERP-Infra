data "aws_iam_role" "github_actions_ecr_push" {
  name = "${local.name_prefix}-github-ecr-push"
}
