data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/summarizer"
  output_path = "${path.module}/.build/summarizer.zip"
}

resource "aws_lambda_function" "summarizer" {
  function_name    = "${local.name_prefix}-summarizer"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BEDROCK_MODEL_ID        = var.bedrock_model_id
      SUMMARY_BUCKET          = aws_s3_bucket.summaries.id
      SUMMARY_PREFIX          = var.summary_prefix
      DYNAMODB_TABLE          = aws_dynamodb_table.contact_summaries.name
      POWERTOOLS_SERVICE_NAME = "contact-lens-summarizer"
      LOG_LEVEL               = "INFO"
    }
  }

  tags = var.tags
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.summarizer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.transcripts.arn
  source_account = local.account_id
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.summarizer.function_name}"
  retention_in_days = 90
  tags              = var.tags
}
