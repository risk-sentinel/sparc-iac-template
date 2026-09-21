"""
Identity-enriched SNS notification for app-secrets access and modifications.

Invoked by a CloudWatch Logs subscription filter on the CloudTrail log group.
Parses CloudTrail events for Secrets Manager operations on app-secrets and
sends a rich SNS message with principal ARN, source IP, event name, secret ID,
and timestamp.

This bypasses EventBridge (which is confirmed non-functional for CloudTrail
delivery in this account — see issue #156) while providing the same
identity-enriched alerts the EventBridge rules were designed for.

Environment variables:
    SNS_TOPIC_ARN  — ARN of the SNS topic to publish to
    CI_ROLE_NAME   — IAM role name to exclude (e.g. sparc-iac-github-actions)
"""

import base64
import gzip
import json
import os

import boto3

sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
CI_ROLE_NAME = os.environ.get("CI_ROLE_NAME", "sparc-iac-github-actions")

# Operations we care about — split into access vs modification for
# distinct subject lines so recipients can filter by severity.
ACCESS_EVENTS = {"GetSecretValue"}
MODIFY_EVENTS = {
    "PutSecretValue",
    "UpdateSecret",
    "UpdateSecretVersionStage",
    "DeleteSecret",
    "RestoreSecret",
    "RotateSecret",
    "TagResource",
    "UntagResource",
    "PutResourcePolicy",
    "DeleteResourcePolicy",
}
ALL_EVENTS = ACCESS_EVENTS | MODIFY_EVENTS


def handler(event, context):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """CloudWatch Logs subscription filter entry point."""
    payload = base64.b64decode(event["awslogs"]["data"])
    log_data = json.loads(gzip.decompress(payload))

    for log_event in log_data.get("logEvents", []):
        try:
            record = json.loads(log_event["message"])
        except (json.JSONDecodeError, KeyError):
            continue

        event_name = record.get("eventName", "")
        if event_name not in ALL_EVENTS:
            continue

        # Filter: only app-secrets
        secret_id = (
            record.get("requestParameters", {}).get("secretId", "")
        )
        if "app-secrets" not in secret_id:
            continue

        # Exclude CI role
        identity = record.get("userIdentity", {})
        if identity.get("type") == "AssumedRole":
            session_issuer = (
                identity
                .get("sessionContext", {})
                .get("sessionIssuer", {})
            )
            if session_issuer.get("userName") == CI_ROLE_NAME:
                continue

        # Also exclude Terraform user-agent as a safety net
        user_agent = record.get("userAgent", "")
        if user_agent.startswith("APN/1.0 HashiCorp"):
            continue

        # Build the notification
        principal = identity.get("arn", "unknown")
        source_ip = record.get("sourceIPAddress", "unknown")
        event_time = record.get("eventTime", "unknown")
        account_id = record.get("recipientAccountId", "unknown")
        region = record.get("awsRegion", "unknown")

        if event_name in ACCESS_EVENTS:
            action_type = "ACCESSED"
            subject = f"SECURITY: App secret accessed — {principal}"
        else:
            action_type = "MODIFIED"
            subject = f"SECURITY: App secret modified ({event_name}) — {principal}"

        # SNS subject is capped at 100 characters
        subject = subject[:100]

        message = (
            f"SECURITY ALERT: App secret {action_type}\n"
            f"\n"
            f"Operation: {event_name}\n"
            f"Who:       {principal}\n"
            f"Source IP:  {source_ip}\n"
            f"Secret:    {secret_id}\n"
            f"Time:      {event_time}\n"
            f"Account:   {account_id}\n"
            f"Region:    {region}\n"
            f"\n"
            f"Verify this was authorized usage."
        )

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message,
        )

        print(
            f"Published {action_type} alert: "
            f"event={event_name} principal={principal} secret={secret_id}"
        )
