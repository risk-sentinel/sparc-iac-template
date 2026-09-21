# ---------------------------------------------------------------------------
# NIST 800-53 Rev 5 Conformance Pack (optional — adds ~$5-10/month)
#
# Custom pack scoped to SPARC ECS Fargate services. Rules for unused
# services (API Gateway, EC2, Redshift, SageMaker, etc.) removed to
# eliminate INSUFFICIENT_DATA noise. See #132.
#
# Original source: https://github.com/awslabs/aws-config-rules/tree/main/aws-config-conformance-packs
# ---------------------------------------------------------------------------

resource "aws_config_conformance_pack" "nist" {
  count = var.enable_aws_config && var.enable_conformance_pack ? 1 : 0
  name  = "${local.name_prefix}-nist-800-53-rev5"

  template_body = file("${path.module}/sparc-ecs-nist-800-53-rev5-conformance-pack.yaml")

  depends_on = [aws_config_configuration_recorder_status.main]
}
