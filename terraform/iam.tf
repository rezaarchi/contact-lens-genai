data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.name_prefix}-summarizer:*"
    ]
  }

  # Read from transcript bucket
  statement {
    sid = "S3ReadTranscripts"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.transcripts.arn,
      "${aws_s3_bucket.transcripts.arn}/*"
    ]
  }

  # Write to summaries bucket
  statement {
    sid = "S3WriteSummaries"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.summaries.arn}/*"
    ]
  }

  # DynamoDB write
  statement {
    sid = "DynamoDBWrite"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.contact_summaries.arn
    ]
  }

  # Read from Connect S3 bucket (Contact Lens analysis output)
  statement {
    sid = "S3ReadConnectAnalysis"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.connect_s3_bucket}",
      "arn:${local.partition}:s3:::${var.connect_s3_bucket}/*"
    ]
  }

  # Bedrock InvokeModel
  statement {
    sid = "BedrockInvoke"
    actions = [
      "bedrock:InvokeModel"
    ]
    resources = [
      "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.bedrock_model_id}"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${local.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}
