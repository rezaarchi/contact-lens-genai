resource "aws_dynamodb_table" "contact_summaries" {
  name         = "${local.name_prefix}-contact-summaries"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "contactId"
  range_key    = "timestamp"

  attribute {
    name = "contactId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-timestamp-index"
    hash_key        = "category"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}
