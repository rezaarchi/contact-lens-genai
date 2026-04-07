# ─────────────────────────────────────────────────────────────────────────────
# Amazon Connect Integration
# Hooks the summarizer Lambda into the Connect instance's Contact Lens
# analysis output. Contact Lens writes post-call analysis JSON to the
# Connect S3 bucket under the Analysis/ prefix — we trigger on that.
# ─────────────────────────────────────────────────────────────────────────────

# Allow Lambda to be invoked by the Connect S3 bucket
resource "aws_lambda_permission" "connect_s3_invoke" {
  statement_id   = "AllowConnectS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.summarizer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = "arn:${local.partition}:s3:::${var.connect_s3_bucket}"
  source_account = local.account_id
}

# S3 notification on the existing Connect bucket for Contact Lens analysis output
resource "aws_s3_bucket_notification" "connect_analysis_trigger" {
  bucket = var.connect_s3_bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.summarizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "Analysis/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.connect_s3_invoke]
}
