variable "aws_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile for GovCloud"
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "contact-lens-genai"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for summarization. Model-agnostic — change to any GovCloud-available model."
  type        = string
  default     = "amazon.nova-pro-v1:0"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory_size" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 512
}

variable "transcript_prefix" {
  description = "S3 prefix where Contact Lens deposits transcripts"
  type        = string
  default     = "transcripts/"
}

variable "summary_prefix" {
  description = "S3 prefix for output summaries"
  type        = string
  default     = "summaries/"
}

# ─── Amazon Connect Integration ───

variable "connect_instance_id" {
  description = "Amazon Connect instance ID. Find via: aws connect list-instances"
  type        = string
}

variable "connect_s3_bucket" {
  description = "Existing S3 bucket where Amazon Connect stores call recordings and Contact Lens analysis"
  type        = string
}

variable "connect_s3_prefix" {
  description = "S3 key prefix for this Connect instance (e.g., 'connect/my-instance/'). Must end with '/'"
  type        = string
  default     = "connect/"

  validation {
    condition     = can(regex("/$", var.connect_s3_prefix))
    error_message = "connect_s3_prefix must end with a trailing slash."
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project    = "contact-lens-genai-govcloud"
    ManagedBy  = "terraform"
    Compliance = "FedRAMP-High"
  }
}
