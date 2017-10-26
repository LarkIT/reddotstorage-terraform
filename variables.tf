
variable "profile" {
  description = "AWS profile for AWS CLI Credentials"
  default     = "red"
}

variable "region" {
    description = "EC2 Region for the VPC"
    default = "us-west-2"
}

variable "environment" {
  description = "EC2 Region for the VPC"
  default     = "production"
}

variable "host_prefix" {
  default = "red"
}

variable "internal_domain_name" {
  default = "red.lan"
}

variable "external_domain_name" {
  default = "aws.reddotstorage.com"
}

variable "app_ssl_enable" {
  default = true
}
