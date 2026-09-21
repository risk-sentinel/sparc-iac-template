# =============================================================================
# AWS Config — recorder, delivery and rules (#597)
#
# Relocated from the standalone AWS/config root so the boundary lives in ONE
# state. The separate state cost a full extra CI job per merge (~79s, of which
# ~63s was container/backend overhead) to reconcile resources that change a few
# times a year, and its stated justification — surviving hibernate — was false:
# var.hibernate gates only desired_count, the EIP, the NAT gateway and one route.
#
# No IAM is declared here. The service role lives in the IAM module per #238 and
# arrives as var.config_role_arn.
#
# The recorder, recorder status, delivery channel and conformance pack are
# ACCOUNT-LEVEL SINGLETONS. They must be imported into this state rather than
# recreated — see scripts/migrate_aws_config_state.sh.
# =============================================================================

resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_aws_config ? 1 : 0
  name     = "${local.name_prefix}-recorder"
  role_arn = var.config_role_arn

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
  s3_bucket_name = var.audit_logs_bucket_name
  s3_key_prefix  = "config-history"

  snapshot_delivery_properties {
    delivery_frequency = local.delivery_frequency
  }

  depends_on = [aws_config_configuration_recorder.main]
}
