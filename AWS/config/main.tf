terraform {
  # Partial backend config — values supplied at init via:
  #   terraform init -backend-config=backend.hcl
  # See backend.example.hcl for the template.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # AWS Config delivery minimum is 24 hours. For weekly/biweekly, we still
  # deliver every 24h but cost stays low because PoC/demo environments have
  # minimal change frequency. Rule evaluations are change-triggered (fire only
  # when resources change) so fewer deploys = fewer evaluations = lower cost.
  #
  # Estimated monthly cost by scenario:
  #   daily   (active dev, frequent deploys): ~$15-25 with conformance pack
  #   weekly  (moderate activity):            ~$8-9 with conformance pack
  #   biweekly (PoC/demo, rare changes):      ~$5 with conformance pack
  delivery_frequency = "TwentyFour_Hours"
}

# ---------------------------------------------------------------------------
# IAM Role for AWS Config
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  count              = var.enable_aws_config ? 1 : 0
  name               = "${local.name_prefix}-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json

  tags = {
    Name = "${local.name_prefix}-config-role"
  }
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  count      = var.enable_aws_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_s3" {
  count = var.enable_aws_config ? 1 : 0

  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/config-history/*"]
    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}"]
  }
}

resource "aws_iam_role_policy" "config_s3" {
  count  = var.enable_aws_config ? 1 : 0
  name   = "${local.name_prefix}-config-s3-delivery"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_s3[0].json
}

# ---------------------------------------------------------------------------
# Config Recorder
# ---------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_aws_config ? 1 : 0
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  # Record everything EXCEPT resource types for services we don't deploy.
  # Reduces per-CI billing (~$0.003/CI) and aligns with the custom
  # conformance pack scope. See #132.
  recording_group {
    all_supported                 = false
    include_global_resource_types = false

    recording_strategy {
      use_only = "EXCLUSION_BY_RESOURCE_TYPES"
    }

    exclusion_by_resource_types {
      resource_types = [
        # API Gateway — not deployed (ALB handles ingress)
        "AWS::ApiGateway::RestApi",
        "AWS::ApiGateway::Stage",
        "AWS::ApiGatewayV2::Api",
        "AWS::ApiGatewayV2::Stage",

        # EC2 Auto Scaling — not used (Fargate uses application autoscaling)
        "AWS::AutoScaling::AutoScalingGroup",
        "AWS::AutoScaling::LaunchConfiguration",
        "AWS::AutoScaling::ScalingPolicy",
        "AWS::AutoScaling::ScheduledAction",
        "AWS::AutoScaling::WarmPool",

        # Elastic Beanstalk — not used
        "AWS::ElasticBeanstalk::Application",
        "AWS::ElasticBeanstalk::ApplicationVersion",
        "AWS::ElasticBeanstalk::Environment",

        # CodeBuild — not used (CI/CD via GitHub Actions)
        "AWS::CodeBuild::Project",

        # DMS — not used
        "AWS::DMS::Certificate",
        "AWS::DMS::EventSubscription",
        "AWS::DMS::ReplicationInstance",
        "AWS::DMS::ReplicationSubnetGroup",
        "AWS::DMS::ReplicationTask",

        # EC2 instances — not used (ECS Fargate). NOTE: VPC, Subnet,
        # SecurityGroup, NAT, EIP, FlowLog, NetworkInterface are all
        # AWS::EC2::* but distinct resource types — they remain recorded.
        "AWS::EC2::Instance",
        "AWS::EC2::LaunchTemplate",

        # EFS — not used (S3 + ephemeral Fargate storage)
        "AWS::EFS::AccessPoint",
        "AWS::EFS::FileSystem",

        # Elasticsearch / OpenSearch — not deployed
        "AWS::Elasticsearch::Domain",
        "AWS::OpenSearch::Domain",

        # Classic ELB — using ALBv2 (ElasticLoadBalancingV2 still recorded)
        "AWS::ElasticLoadBalancing::LoadBalancer",

        # EMR — not used
        "AWS::EMR::Cluster",
        "AWS::EMR::SecurityConfiguration",

        # Kinesis — not used
        "AWS::Kinesis::Stream",
        "AWS::Kinesis::StreamConsumer",
        "AWS::KinesisAnalyticsV2::Application",
        "AWS::KinesisFirehose::DeliveryStream",
        "AWS::KinesisVideo::SignalingChannel",
        "AWS::KinesisVideo::Stream",

        # Redshift — not used
        # NOTE: AWS::RedshiftServerless::* not supported by AWS Config recorder
        "AWS::Redshift::Cluster",
        "AWS::Redshift::ClusterParameterGroup",
        "AWS::Redshift::ClusterSecurityGroup",
        "AWS::Redshift::ClusterSnapshot",
        "AWS::Redshift::ClusterSubnetGroup",
        "AWS::Redshift::EventSubscription",

        # SageMaker — not used
        # NOTE: Endpoint, ImageVersion, ModelPackageGroup, Pipeline, Project
        # not supported by AWS Config recorder
        "AWS::SageMaker::AppImageConfig",
        "AWS::SageMaker::CodeRepository",
        "AWS::SageMaker::Domain",
        "AWS::SageMaker::EndpointConfig",
        "AWS::SageMaker::FeatureGroup",
        "AWS::SageMaker::Image",
        "AWS::SageMaker::Model",
        "AWS::SageMaker::NotebookInstance",
        "AWS::SageMaker::NotebookInstanceLifecycleConfig",
        "AWS::SageMaker::Workteam",

        # SSM Documents — no custom documents created
        "AWS::SSM::Document",

        # VPN / Customer Gateway — not used
        "AWS::EC2::CustomerGateway",
        "AWS::EC2::VPNConnection",
        "AWS::EC2::VPNGateway",

        # WAFv2 — not deployed (baselined for future)
        # NOTE: AWS::WAFv2::LoggingConfiguration not supported by AWS Config recorder
        "AWS::WAFv2::IPSet",
        "AWS::WAFv2::ManagedRuleSet",
        "AWS::WAFv2::RegexPatternSet",
        "AWS::WAFv2::RuleGroup",
        "AWS::WAFv2::WebACL",
      ]
    }
  }
}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_aws_config ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ---------------------------------------------------------------------------
# Delivery Channel — snapshots to existing artifacts bucket
# ---------------------------------------------------------------------------

resource "aws_config_delivery_channel" "main" {
  count          = var.enable_aws_config ? 1 : 0
  name           = "${local.name_prefix}-delivery"
  s3_bucket_name = var.artifacts_bucket_name
  s3_key_prefix  = "config-history"

  snapshot_delivery_properties {
    delivery_frequency = local.delivery_frequency
  }

  depends_on = [aws_config_configuration_recorder.main]
}
