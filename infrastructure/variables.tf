variable "aws_region" { default = "eu-central-1" }

variable "admin_email" { default = "iursuprun@gmail.com" }

variable "from_email" { default = "no-reply@example.com" }

variable "lambda_package_path" {
  description = "Path to the built Lambda JAR file"
  type        = string
  default     = ""
}