output "transcript_bucket_name" {
  description = "S3 bucket for Contact Lens transcripts"
  value       = aws_s3_bucket.transcripts.id
}

output "summary_bucket_name" {
  description = "S3 bucket for AI-generated summaries"
  value       = aws_s3_bucket.summaries.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table for structured contact summaries"
  value       = aws_dynamodb_table.contact_summaries.name
}

output "lambda_function_name" {
  description = "Lambda summarizer function name"
  value       = aws_lambda_function.summarizer.function_name
}

output "lambda_function_arn" {
  description = "Lambda summarizer function ARN"
  value       = aws_lambda_function.summarizer.arn
}

output "bedrock_model_id" {
  description = "Bedrock model ID configured for summarization"
  value       = var.bedrock_model_id
}
