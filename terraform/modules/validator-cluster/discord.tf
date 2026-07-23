# Discord webhook integration for SNS alerts
# Only created if discord_webhook_secret_name is provided

locals {
  discord_enabled = var.discord_webhook_secret_name != null
  # Regions to run the forwarder in (SNS can only invoke a same-region Lambda).
  # The webhook secret must exist in every region (Secrets Manager replica).
  discord_regions = local.discord_enabled ? local.regions : {}
}

# Only the primary region's secret is looked up (it always exists); replicas in
# other regions may not exist at plan time, so their policy ARNs are constructed
# with a wildcard suffix instead.
data "aws_secretsmanager_secret" "discord_webhook" {
  for_each = local.discord_enabled ? { (var.region) = true } : {}

  region = each.key
  name   = var.discord_webhook_secret_name
}

locals {
  discord_secret_arns = local.discord_enabled ? concat(
    [data.aws_secretsmanager_secret.discord_webhook[var.region].arn],
    [for r in sort(keys(local.discord_regions)) : "arn:aws:secretsmanager:${r}:${data.aws_caller_identity.current.account_id}:secret:${var.discord_webhook_secret_name}-*" if r != var.region]
  ) : []
}

# Lambda function code
data "archive_file" "discord_lambda" {
  count       = local.discord_enabled ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/.terraform/discord_lambda_${var.environment}.zip"

  source {
    content  = <<-EOF
      import json
      import urllib.request
      import boto3
      import os

      def get_webhook_url():
          client = boto3.client('secretsmanager', region_name=os.environ['AWS_REGION'])
          response = client.get_secret_value(SecretId=os.environ['SECRET_NAME'])
          secret = json.loads(response['SecretString'])
          return secret['webhook_url']

      def lambda_handler(event, context):
          webhook_url = get_webhook_url()

          for record in event.get('Records', []):
              sns_message = record.get('Sns', {})
              subject = sns_message.get('Subject', 'AWS Alert')
              message = sns_message.get('Message', '')

              # Parse CloudWatch alarm message if applicable
              try:
                  alarm_data = json.loads(message)
                  if 'AlarmName' in alarm_data:
                      alarm_name = alarm_data.get('AlarmName', 'Unknown')
                      new_state = alarm_data.get('NewStateValue', 'Unknown')
                      reason = alarm_data.get('NewStateReason', '')
                      old_state = alarm_data.get('OldStateValue', 'Unknown')

                      # Color based on state
                      if new_state == 'ALARM':
                          color = 0xFF0000  # Red
                          emoji = '🚨'
                      elif new_state == 'OK':
                          color = 0x00FF00  # Green
                          emoji = '✅'
                      else:
                          color = 0xFFFF00  # Yellow
                          emoji = '⚠️'

                      discord_message = {
                          "embeds": [{
                              "title": f"{emoji} {alarm_name}",
                              "description": reason[:2000] if reason else "No details provided",
                              "color": color,
                              "fields": [
                                  {"name": "State Change", "value": f"{old_state} → {new_state}", "inline": True},
                                  {"name": "Region", "value": alarm_data.get('Region', 'Unknown'), "inline": True}
                              ]
                          }]
                      }
                  else:
                      # Generic message
                      discord_message = {
                          "embeds": [{
                              "title": subject[:256],
                              "description": message[:2000],
                              "color": 0x5865F2
                          }]
                      }
              except json.JSONDecodeError:
                  # Plain text message
                  discord_message = {
                      "embeds": [{
                          "title": subject[:256],
                          "description": message[:2000],
                          "color": 0x5865F2
                      }]
                  }

              # Send to Discord (User-Agent required to avoid 403)
              req = urllib.request.Request(
                  webhook_url,
                  data=json.dumps(discord_message).encode('utf-8'),
                  headers={
                      'Content-Type': 'application/json',
                      'User-Agent': 'Mozilla/5.0 (compatible; AWS-Lambda-Alerter/1.0)'
                  },
                  method='POST'
              )

              try:
                  urllib.request.urlopen(req)
                  print(f"Successfully sent message to Discord")
              except Exception as e:
                  print(f"Failed to send to Discord: {e}")
                  raise

          return {'statusCode': 200}
    EOF
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "discord_lambda" {
  count = local.discord_enabled ? 1 : 0
  name  = "${var.environment}-discord-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "discord_lambda" {
  count = local.discord_enabled ? 1 : 0
  name  = "discord-lambda-policy"
  role  = aws_iam_role.discord_lambda[0].id

  # Two jsonencode branches so the single-region rendering stays byte-identical
  # (Resource as a plain string) while multi-region gets a list of replica ARNs.
  policy = length(local.discord_secret_arns) == 1 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = local.discord_secret_arns[0]
      }
    ]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = local.discord_secret_arns
      }
    ]
  })
}

# Lambda function (one per region — SNS can only invoke a same-region Lambda)
resource "aws_lambda_function" "discord_forwarder" {
  for_each         = local.discord_regions
  region           = each.key
  filename         = data.archive_file.discord_lambda[0].output_path
  source_code_hash = data.archive_file.discord_lambda[0].output_base64sha256
  function_name    = "${var.environment}-sns-to-discord"
  role             = aws_iam_role.discord_lambda[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SECRET_NAME = var.discord_webhook_secret_name
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Allow SNS to invoke Lambda
resource "aws_lambda_permission" "sns_alerts" {
  for_each      = local.discord_regions
  region        = each.key
  statement_id  = "AllowSNSAlerts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_forwarder[each.key].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts[each.key].arn
}

resource "aws_lambda_permission" "sns_reboot" {
  for_each      = local.discord_regions
  region        = each.key
  statement_id  = "AllowSNSReboot"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_forwarder[each.key].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.reboot_required[each.key].arn
}

# Subscribe Lambda to SNS topics
resource "aws_sns_topic_subscription" "alerts_to_discord" {
  for_each  = local.discord_regions
  region    = each.key
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_forwarder[each.key].arn
}

resource "aws_sns_topic_subscription" "reboot_to_discord" {
  for_each  = local.discord_regions
  region    = each.key
  topic_arn = aws_sns_topic.reboot_required[each.key].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_forwarder[each.key].arn
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_lambda_function.discord_forwarder[0]
  to   = aws_lambda_function.discord_forwarder["ap-south-1"]
}

moved {
  from = aws_lambda_permission.sns_alerts[0]
  to   = aws_lambda_permission.sns_alerts["ap-south-1"]
}

moved {
  from = aws_lambda_permission.sns_reboot[0]
  to   = aws_lambda_permission.sns_reboot["ap-south-1"]
}

moved {
  from = aws_sns_topic_subscription.alerts_to_discord[0]
  to   = aws_sns_topic_subscription.alerts_to_discord["ap-south-1"]
}

moved {
  from = aws_sns_topic_subscription.reboot_to_discord[0]
  to   = aws_sns_topic_subscription.reboot_to_discord["ap-south-1"]
}
