provider "aws" {
  region  = "${var.region}"
  profile = "${var.profile}"
}

terraform {
  backend "s3" {
    bucket  = "red-tfstate"
    key     = "network/terraform.tfstate"
    profile = "red"
    region  = "us-west-2"
  }
}

data "terraform_remote_state" "remote_tfstate" {
  backend = "s3"
  config {
    bucket  = "red-tfstate"
    key     = "network/terraform.tfstate"
    profile = "red"
    region  = "us-west-2"
  }
}

module "vpc" {
  source                   = "git::https://github.com/LarkIT/vpc.git?ref=v0.0.1"
  profile                  = "${var.profile}"
  host_prefix              = "${var.host_prefix}"
  environment              = "${var.environment}"
  region                   = "${var.region}"
  availability_zone        = "${var.availability_zone}"
  internal_internet_egress = "${var.internal_internet_egress}" 
}

module "security_groups" {
  source              = "git::https://github.com/LarkIT/security_groups.git?ref=v0.0.7"
  host_prefix         = "${var.host_prefix}"
  vpc_id              = "${module.vpc.vpc_id}"
  cidr                = "${module.vpc.cidr}"
  infra_services_cidr = "${module.vpc.dmz_subnet_cidr}"
  enable_postgres     = true
}

module "dns" {
  source               = "git::https://github.com/LarkIT/dns.git?ref=master"
  vpc_id               = "${module.vpc.vpc_id}"
  internal_domain_name = "${var.internal_domain_name}"
  external_domain_name = "${var.external_domain_name}"
  cidr                 = "${module.vpc.cidr}"
  domain_name_servers  = "${cidrhost("${module.vpc.cidr}", 2)}"
}

module "gitlab_s3_backups" {
  source      = "git::https://github.com/LarkIT/s3.git?ref=v0.0.1"
  bucket_name = "${var.host_prefix}-gitlab-s3-backups"
}

module "software" {
  source      = "git::https://github.com/LarkIT/s3.git?ref=v0.0.1"
  bucket_name = "${var.host_prefix}-software"
  acl         = "public-read"
}

resource "aws_s3_bucket" "stage_document_uploads" {
  bucket     = "${var.host_prefix}-stage-document-uploads"
  acl        = "private"
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket" "production_document_uploads" {
  bucket     = "${var.host_prefix}-production-document-uploads"
  acl        = "private"
  versioning {
    enabled = true
  }
}

resource "aws_iam_policy" "stage_document_uploads_policy" {
  name = "document_upload"
  path = "/"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "${aws_s3_bucket.stage_document_uploads.arn}"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "${aws_s3_bucket.stage_document_uploads.arn}/*"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "production_document_uploads_policy" {
  name = "production_document_upload"
  path = "/"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "${aws_s3_bucket.production_document_uploads.arn}"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "${aws_s3_bucket.production_document_uploads.arn}/*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "stage_document_uploads" {
    name               = "stage_document_uploads"
    path               = "/"
    assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "production_document_uploads" {
    name               = "production_document_uploads"
    path               = "/"
    assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_instance_profile" "stage_railsapp" {
  name = "stage_railsapp"
  role = "${aws_iam_role.stage_document_uploads.name}"
}

resource "aws_iam_role_policy_attachment" "document_upload" {
  role       = "${aws_iam_role.stage_document_uploads.name}"
  policy_arn = "${aws_iam_policy.stage_document_uploads_policy.arn}"
}

resource "aws_iam_instance_profile" "prod_railsapp" {
  name = "prod_railsapp"
  role = "${aws_iam_role.production_document_uploads.name}"
}

resource "aws_iam_role_policy_attachment" "prod_document_upload" {
  role       = "${aws_iam_role.production_document_uploads.name}"
  policy_arn = "${aws_iam_policy.production_document_uploads_policy.arn}"
}

module "policy" {
  source     = "git::https://github.com/LarkIT/policy.git?ref=v0.0.1"
  bucket_arn = "${module.gitlab_s3_backups.bucket_arn}"
}

module "iam_role" {
  source                = "git::https://github.com/LarkIT/iam_role.git?ref=v0.0.1"
  cloudwatch_policy_arn = "${module.policy.cloudwatch_policy_arn}"
  ec2_admin_policy_arn  = "${module.policy.ec2_admin_policy_arn}"
  gitlab_policy_arn     = "${module.policy.gitlab_policy_arn}"
}

###############################
#
# Core Infrastructure Servers
#
###############################
module "foreman" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "foreman"
  hostname             = "foreman-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-shared}"
  instance_type        = "t2.large"
  bootstrap_template   = "foreman-install"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.foreman_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
}

module "foreman-02" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=DEVSUPPORT616"
  role                 = "foreman"
  hostname             = "foreman-02"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-shared}"
  instance_type        = "t2.large"
  bootstrap_template   = "foreman-install"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.foreman_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
}

module "gitlab" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "gitlab"
  hostname             = "gitlab-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  #subnet_id            = "${module.vpc.a-dmz}"
  subnet_id            = "${module.vpc.a-shared}"
  instance_type        = "t2.medium"
  iam_instance_profile = "gitlab"
  bootstrap_template   = "gitlab-install"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.gitlab_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
}

module "pulp" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "pulp"
  hostname             = "pulp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-shared}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
  ebs_volume_size      = 130
}

module "vpn" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "vpn"
  hostname             = "vpn-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  external_dns_enable  = true
  external_hostname    = "vpn.aws.reddotstorage.com"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  enable_aws_eip       = true
  instance_type        = "t2.micro"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.vpn_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
}

###############################
#
# Stage Application Server
#
###############################
module "stage_railsapp_02" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "railsapp"
  pp_env               = "staging"
  hostname             = "stageapp-02"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.small"
  iam_instance_profile = "stage_railsapp"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.stageapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
  ebs_type             = "standard"
}

module "stage_fusion_01" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "fusion"
  pp_env               = "stage"
  hostname             = "fusion-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.xlarge"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.stage-fusion_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
}

module "stage_fusion_02" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "fusion"
  pp_env               = "stage"
  hostname             = "stagefusion-02"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.xlarge"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.stage-fusion_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
}

###############################
#
# Production Application Server
#
###############################
module "prod_railsapp_01" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "railsapp"
  hostname             = "prodapp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.medium"
  iam_instance_profile = "prod_railsapp"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.prodapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
}

module "prod_railsapp_02" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "railsapp"
  hostname             = "prodapp-02"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.medium"
  iam_instance_profile = "prod_railsapp"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.prodapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
}

module "prod_fusion_01" {
  source               = "git::https://github.com/LarkIT/aws_instance.git?ref=v0.0.3"
  role                 = "fusion"
  pp_env               = "prod"
  hostname             = "prodfusion-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.xlarge"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.prod-fusion_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  enable_ebs_volume    = true
}

###############################
#
# Stage Database
#
###############################
module "stage_db" {
  source                 = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git?ref=v1.0.3"
  identifier             = "stage"
  engine                 = "postgres"
  engine_version         = "9.6.2"
  instance_class         = "db.t2.small"
  allocated_storage      = 5
  name                   = "stagedb"
  username               = "dbadmin"
  password               = "${var.stage_db_password}"
  port                   = "5432"
  vpc_security_group_ids = [ "${module.security_groups.general_id}", "${module.security_groups.stagedb_id}" ]
  maintenance_window     = "Mon:00:00-Mon:03:00"
  backup_window          = "03:00-06:00"
  subnet_ids             = [ "${module.vpc.a-db}", "${module.vpc.b-db}" ]
  family = "postgres9.6"
  
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

###############################
#
# Prod Database
#
###############################
module "prod_db" {
  source                 = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git?ref=v1.0.3"
  identifier             = "prod"
  engine                 = "postgres"
  engine_version         = "9.6.2"
  instance_class         = "db.t2.medium"
  allocated_storage      = 5
  name                   = "proddb"
  username               = "dbadmin"
  password               = "${var.prod_db_password}"
  port                   = "5432"
  vpc_security_group_ids = [ "${module.security_groups.general_id}", "${module.security_groups.proddb_id}" ]
  maintenance_window     = "Mon:00:00-Mon:03:00"
  backup_window          = "03:00-06:00"
  subnet_ids             = [ "${module.vpc.a-db}", "${module.vpc.b-db}" ]
  family = "postgres9.6"

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}
###############################
#
# Load Balancer Config
#
###############################
module "stage_lb" {
  source               = "git::https://github.com/LarkIT/aws-alb.git?ref=v0.0.1"
  environment          = "staging"
  host_prefix          = "${module.vpc.host_prefix}"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.stage-app-lb_id}" ]
  vpc_id               = "${module.vpc.vpc_id}"
  subnets              = [ "${module.vpc.a-dmz}", "${module.vpc.b-dmz}" ]
  app_ssl_enable       = "${var.app_ssl_enable}"
#  app_ssl_domain       = "staging.${var.external_domain_name}"
  app_ssl_domain       = "staging.reddotstorage.com"
  external_domain_name = "staging.${var.external_domain_name}"
  route53_external_id  = "${module.dns.route53_external_id}"
}

###############################
#
# Load Balancer Config
#
###############################
module "prod_lb" {
  source               = "git::https://github.com/LarkIT/aws-alb.git?ref=v0.0.1"
  environment          = "production"
  host_prefix          = "${module.vpc.host_prefix}"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.prod-app-lb_id}" ]
  vpc_id               = "${module.vpc.vpc_id}"
  subnets              = [ "${module.vpc.a-dmz}", "${module.vpc.b-dmz}" ]
  app_ssl_enable       = "${var.app_ssl_enable}"
  app_ssl_domain       = "production.${var.external_domain_name}"
  external_domain_name = "production.${var.external_domain_name}"
  route53_external_id  = "${module.dns.route53_external_id}"
}

###############################
#
# Stage Attach Nodes to LB
#
###############################
resource "aws_alb_target_group_attachment" "stageapp_02-http" {
  target_group_arn = "${module.stage_lb.app-http_arn}"
  target_id        = "${module.stage_railsapp_02.hostname_id}"
}

resource "aws_alb_target_group_attachment" "stageapp-02-stageapp-https" {
  count            = "${var.app_ssl_enable}"
  target_group_arn = "${module.stage_lb.app-https_arn}"
  target_id        = "${module.stage_railsapp_02.hostname_id}"
}
###############################
#
# Prod Attach Nodes to LB
#
###############################
resource "aws_alb_target_group_attachment" "prodapp_01-http" {
  target_group_arn = "${module.prod_lb.app-http_arn}"
  target_id        = "${module.prod_railsapp_01.hostname_id}"
}

# resource "aws_alb_target_group_attachment" "prodapp_02-http" {
#   target_group_arn = "${module.prod_lb.app-http_arn}"
#   target_id        = "${module.prod_railsapp_02.hostname_id}"
# }

resource "aws_alb_target_group_attachment" "prodapp_01-https" {
  count            = "${var.app_ssl_enable}"
  target_group_arn = "${module.prod_lb.app-https_arn}"
  target_id        = "${module.prod_railsapp_01.hostname_id}"
}

#resource "aws_alb_target_group_attachment" "prodapp_02-https" {
#  count            = "${var.app_ssl_enable}"
#  target_group_arn = "${module.prod_lb.app-https_arn}"
#  target_id        = "${module.prod_railsapp_02.hostname_id}"
#}
