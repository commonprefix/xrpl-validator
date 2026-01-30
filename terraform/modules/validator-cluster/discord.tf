# Discord webhook integration for SNS alerts
# Only created if discord_webhook_secret_name is provided

locals {
  discord_enabled = var.discord_webhook_secret_name != null
}

data "aws_secretsmanager_secret" "discord_webhook" {
  count = local.discord_enabled ? 1 : 0
  name  = var.discord_webhook_secret_name
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

  policy = jsonencode({
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
        Resource = data.aws_secretsmanager_secret.discord_webhook[0].arn
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "discord_forwarder" {
  count            = local.discord_enabled ? 1 : 0
  filename         = data.archive_file.discord_lambda[0].output_path
  source_code_hash = data.archive_file.discord_lambda[0].output_base64sha256
  function_name    = "${var.environment}-sns-to-discord"
  role             = aws_iam_role.discord_lambda[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      SECRET_NAME = data.aws_secretsmanager_secret.discord_webhook[0].name
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Allow SNS to invoke Lambda
resource "aws_lambda_permission" "sns_alerts" {
  count         = local.discord_enabled ? 1 : 0
  statement_id  = "AllowSNSAlerts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_lambda_permission" "sns_reboot" {
  count         = local.discord_enabled ? 1 : 0
  statement_id  = "AllowSNSReboot"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.reboot_required.arn
}

# Subscribe Lambda to SNS topics
resource "aws_sns_topic_subscription" "alerts_to_discord" {
  count     = local.discord_enabled ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_forwarder[0].arn
}

resource "aws_sns_topic_subscription" "reboot_to_discord" {
  count     = local.discord_enabled ? 1 : 0
  topic_arn = aws_sns_topic.reboot_required.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_forwarder[0].arn
}
