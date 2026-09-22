-- Athena external table for example-trail CloudTrail logs.
-- Schema mirrors AWS's documented CloudTrail Athena DDL:
-- https://docs.aws.amazon.com/athena/latest/ug/cloudtrail-logs.html
--
-- Partition projection over year/month/day so we don't have to MSCK REPAIR
-- after every new day's logs land.
--
-- Created 2026-05-26 as part of sparc-iac#298 (Phase 3 — permission audit
-- for sparc-iac-github-actions). The table can be re-used by future audits;
-- it points at the canonical trail location.

CREATE EXTERNAL TABLE IF NOT EXISTS sparc_audit.cloudtrail_logs (
    eventVersion STRING,
    userIdentity STRUCT<
        type: STRING,
        principalId: STRING,
        arn: STRING,
        accountId: STRING,
        invokedBy: STRING,
        accessKeyId: STRING,
        userName: STRING,
        sessionContext: STRUCT<
            attributes: STRUCT<
                mfaAuthenticated: STRING,
                creationDate: STRING>,
            sessionIssuer: STRUCT<
                type: STRING,
                principalId: STRING,
                arn: STRING,
                accountId: STRING,
                userName: STRING>,
            ec2RoleDelivery: STRING,
            webIdFederationData: MAP<STRING,STRING>>>,
    eventTime STRING,
    eventSource STRING,
    eventName STRING,
    awsRegion STRING,
    sourceIpAddress STRING,
    userAgent STRING,
    errorCode STRING,
    errorMessage STRING,
    requestParameters STRING,
    responseElements STRING,
    additionalEventData STRING,
    requestId STRING,
    eventId STRING,
    resources ARRAY<STRUCT<
        arn: STRING,
        accountId: STRING,
        type: STRING>>,
    eventType STRING,
    apiVersion STRING,
    readOnly STRING,
    recipientAccountId STRING,
    serviceEventDetails STRING,
    sharedEventID STRING,
    vpcEndpointId STRING,
    tlsDetails STRUCT<
        tlsVersion: STRING,
        cipherSuite: STRING,
        clientProvidedHostHeader: STRING>
)
COMMENT 'example-trail CloudTrail logs for OIDC permission audit (sparc-iac#298)'
PARTITIONED BY (region STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
    'ignore.malformed.json' = 'true',
    'case.insensitive' = 'false',
    'mapping.eventversion' = 'eventVersion',
    'mapping.useridentity' = 'userIdentity',
    'mapping.principalid' = 'principalId',
    'mapping.accountid' = 'accountId',
    'mapping.invokedby' = 'invokedBy',
    'mapping.accesskeyid' = 'accessKeyId',
    'mapping.username' = 'userName',
    'mapping.sessioncontext' = 'sessionContext',
    'mapping.mfaauthenticated' = 'mfaAuthenticated',
    'mapping.creationdate' = 'creationDate',
    'mapping.sessionissuer' = 'sessionIssuer',
    'mapping.ec2roledelivery' = 'ec2RoleDelivery',
    'mapping.webidfederationdata' = 'webIdFederationData',
    'mapping.eventtime' = 'eventTime',
    'mapping.eventsource' = 'eventSource',
    'mapping.eventname' = 'eventName',
    'mapping.awsregion' = 'awsRegion',
    'mapping.sourceipaddress' = 'sourceIPAddress',
    'mapping.useragent' = 'userAgent',
    'mapping.errorcode' = 'errorCode',
    'mapping.errormessage' = 'errorMessage',
    'mapping.requestparameters' = 'requestParameters',
    'mapping.responseelements' = 'responseElements',
    'mapping.additionaleventdata' = 'additionalEventData',
    'mapping.requestid' = 'requestID',
    'mapping.eventid' = 'eventID',
    'mapping.eventtype' = 'eventType',
    'mapping.apiversion' = 'apiVersion',
    'mapping.readonly' = 'readOnly',
    'mapping.recipientaccountid' = 'recipientAccountId',
    'mapping.serviceeventdetails' = 'serviceEventDetails',
    'mapping.sharedeventid' = 'sharedEventID',
    'mapping.vpcendpointid' = 'vpcEndpointId',
    'mapping.tlsdetails' = 'tlsDetails',
    'mapping.tlsversion' = 'tlsVersion',
    'mapping.ciphersuite' = 'cipherSuite',
    'mapping.clientprovidedhostheader' = 'clientProvidedHostHeader'
)
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://your-security-artifacts-bucket/cloudtrail/AWSLogs/123456789012/CloudTrail/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.region.type' = 'enum',
    'projection.region.values' = 'us-east-1,us-east-2,us-west-1,us-west-2,ca-central-1,eu-west-1,eu-west-2,eu-west-3,eu-central-1,eu-north-1,ap-northeast-1,ap-northeast-2,ap-northeast-3,ap-south-1,ap-southeast-1,ap-southeast-2,sa-east-1',
    'projection.year.type' = 'integer',
    'projection.year.range' = '2026,2030',
    'projection.month.type' = 'integer',
    'projection.month.range' = '1,12',
    'projection.month.digits' = '2',
    'projection.day.type' = 'integer',
    'projection.day.range' = '1,31',
    'projection.day.digits' = '2',
    'storage.location.template' = 's3://your-security-artifacts-bucket/cloudtrail/AWSLogs/123456789012/CloudTrail/${region}/${year}/${month}/${day}'
);
