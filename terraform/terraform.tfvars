aws_region         = "us-gov-west-1"
aws_profile        = "default"
project_name       = "contact-lens-genai"
environment        = "dev"
bedrock_model_id   = "amazon.nova-pro-v1:0"
lambda_timeout     = 120
lambda_memory_size = 512

# Amazon Connect Integration — update these with your values
connect_instance_id = "YOUR_CONNECT_INSTANCE_ID"
connect_s3_bucket   = "YOUR_CONNECT_S3_BUCKET"
connect_s3_prefix   = "connect/YOUR_INSTANCE_ALIAS/"
