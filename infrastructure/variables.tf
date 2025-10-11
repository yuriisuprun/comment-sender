#############################################
# Variables
#############################################
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default = "eu-central-1"
}

variable "from_email" {
  description = "SES From Email"
  type        = string
  default = "iursuprun@gmail.com"

  validation {
    condition     = length(var.from_email) > 0
    error_message = "from_email must be provided and non-empty"
  }
}

variable "admin_email" {
  description = "SES Admin Email"
  type        = string
  default = "iursuprun@gmail.com"

  validation {
    condition     = length(var.admin_email) > 0
    error_message = "admin_email must be provided and non-empty"
  }
}

variable "lambda_package_path" {
  description = "Path to Lambda JAR file"
  type        = string
  default     = ""
}