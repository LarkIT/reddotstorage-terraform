
variable "profile" {
  description = "AWS profile for AWS CLI Credentials"
  default     = "red"
}

variable "region" {
    description = "EC2 Region for the VPC"
    default = "us-west-2"
}

variable "availability_zone" {
    description = "EC2 availability zone for the VPC"
    default     = "a"
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

variable "prod_db_password" {
  description = "Production database password."
}

variable "internal_internet_egress" {
  description = "Allow outbound internet communication for non PCI/HIPPA environments"
}
