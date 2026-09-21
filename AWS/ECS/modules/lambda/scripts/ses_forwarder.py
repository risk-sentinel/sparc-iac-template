#!/usr/bin/env python3
"""SES inbound → S3 → forward Lambda for example.com (#528 Phase 2).

Wired as the Lambda action on the SES receipt rule (which also stores the raw
message to S3). Reads the raw MIME from S3, rewrites the From header to a
verified domain address — so SPF/DKIM/DMARC stay aligned on the forward — with
Reply-To set to the original sender, then re-sends via SES to the configured
destinations. Runtime python3.12.

Env:
  INBOUND_BUCKET  S3 bucket the SES S3-action wrote the raw message to
  INBOUND_PREFIX  key prefix used by the S3 action (may be empty)
  FROM_ADDRESS    verified sender the forward is sent as (e.g. no-reply@<domain>)
  DESTINATIONS    comma-separated list of forward targets
"""
import email
import os
from email.utils import formataddr, parseaddr

import boto3

s3 = boto3.client("s3")
ses = boto3.client("ses")

BUCKET = os.environ["INBOUND_BUCKET"]
PREFIX = os.environ.get("INBOUND_PREFIX", "")
# Guards the S3 read against a bucket-ownership swap (confused-deputy).
EXPECTED_BUCKET_OWNER = os.environ["EXPECTED_BUCKET_OWNER"]
FROM_ADDRESS = os.environ["FROM_ADDRESS"]
DESTINATIONS = [d.strip() for d in os.environ["DESTINATIONS"].split(",") if d.strip()]

# Headers that are invalid or misleading once we rewrite the sender.
_STRIP_HEADERS = ("From", "Return-Path", "Sender", "Reply-To", "DKIM-Signature")


def handler(event, context):
    forwarded = 0
    for record in event.get("Records", []):
        mail = record.get("ses", {}).get("mail", {})
        message_id = mail.get("messageId")
        if not message_id:
            continue

        raw = s3.get_object(
            Bucket=BUCKET,
            Key=f"{PREFIX}{message_id}",
            ExpectedBucketOwner=EXPECTED_BUCKET_OWNER,
        )["Body"].read()
        msg = email.message_from_bytes(raw)

        orig_from = msg.get("From", "")
        orig_name, orig_addr = parseaddr(orig_from)
        recipients = mail.get("destination", [])

        for header in _STRIP_HEADERS:
            del msg[header]
        # Preserve the original sender in the display name; route replies to them.
        display = f"{orig_name or orig_addr or 'unknown'} (via {', '.join(recipients)})"
        msg["From"] = formataddr((display, FROM_ADDRESS))
        msg["Reply-To"] = orig_from or FROM_ADDRESS

        ses.send_raw_email(
            Source=FROM_ADDRESS,
            Destinations=DESTINATIONS,
            RawMessage={"Data": msg.as_bytes()},
        )
        forwarded += 1
        print(f"forwarded messageId={message_id} to={recipients} -> {DESTINATIONS}")

    return {"forwarded": forwarded}
