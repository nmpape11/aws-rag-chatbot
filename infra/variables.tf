variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "kb_arn" {
  type        = string
  description = "Full ARN of the Bedrock Knowledge Base"
}

variable "kb_id" {
  type        = string
  description = "Bedrock Knowledge Base ID (e.g. A1B2C3D4E5)"
}

variable "model_arn" {
  type        = string
  description = "Bedrock model ARN for RetrieveAndGenerate (e.g. Claude Haiku)"
}
