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
  source                   = "git::https://nfosdick@bitbucket.org/larkit/vpc.git"
  profile                  = "${var.profile}"
  host_prefix              = "${var.host_prefix}"
  environment              = "${var.environment}"
  region                   = "${var.region}"
  availability_zone        = "${var.availability_zone}"
  internal_internet_egress = "${var.internal_internet_egress}" 
}

module "security_groups" {
  source              = "git::https://nfosdick@bitbucket.org/larkit/security_groups.git"
  host_prefix         = "${var.host_prefix}"
  vpc_id              = "${module.vpc.vpc_id}"
  cidr                = "${module.vpc.cidr}"
  infra_services_cidr = "${module.vpc.dmz_subnet_cidr}"
}

module "dns" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/dns.git"
  vpc_id               = "${module.vpc.vpc_id}"
  internal_domain_name = "${var.internal_domain_name}"
  external_domain_name = "${var.external_domain_name}"
  cidr                 = "${module.vpc.cidr}"
  domain_name_servers  = "${cidrhost("${module.vpc.cidr}", 2)}"
}

module "gitlab_s3_backups" {
  source      = "git::https://nfosdick@bitbucket.org/larkit/s3.git"
  bucket_name = "${var.host_prefix}-gitlab-s3-backups"
}

module "policy" {
  source     = "git::https://nfosdick@bitbucket.org/larkit/policy.git"
  bucket_arn = "${module.gitlab_s3_backups.bucket_arn}"
}

module "iam_role" {
  source                = "git::https://nfosdick@bitbucket.org/larkit/iam_role.git"
  cloudwatch_policy_arn = "${module.policy.cloudwatch_policy_arn}"
  ec2_admin_policy_arn  = "${module.policy.ec2_admin_policy_arn}"
  gitlab_policy_arn     = "${module.policy.gitlab_policy_arn}"
}

#module "bootstrap" {
#  source               = "git::https://nfosdick@bitbucket.org/larkit/bootstrap.git"
#  internal_domain_name = "${module.dns.internal_domain_name}"
#  host_prefix          = "${module.vpc.host_prefix}"
#}

###############################
#
# Core Infrastructure Servers
#
###############################
#module "jump" {
#  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
#  hostname             = "jump-01"
#  host_prefix          = "${module.vpc.host_prefix}"
#  internal_domain_name = "${module.dns.internal_domain_name}"
#  region               = "${var.region}"
#  availability_zone    = "${module.vpc.availability_zone}"
#  subnet_id            = "${module.vpc.a-dmz}"
#  enable_aws_eip       = true
#  instance_type        = "t2.micro"
#  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
#  route53_internal_id  = "${module.dns.route53_internal_id}"
#  route53_external_id  = "${module.dns.route53_external_id}"
#  bootstrap            = "${module.bootstrap.base_cloutinit}"
#}

module "foreman" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  hostname             = "foreman-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  enable_aws_eip       = true
  #subnet_id            = "${module.vpc.a-shared}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.foreman_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
#  bootstrap            = "${module.bootstrap.foreman_cloutinit}"
}

module "gitlab" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  hostname             = "gitlab-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
#  bootstrap            = "${module.bootstrap.gitlab_cloutinit}"
}

#resource "aws_ebs_volume" "pulp" {
#    availability_zone = "${var.region}${var.availability_zone}"
#    size              = 100
#    tags {
#        Name = "Pulp Volume"
#    }
#}

module "pulp" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  role                 = "pulp"
  hostname             = "pulp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-shared}"
  #subnet_id            = "${module.vpc.a-dmz}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
  enable_ebs_volume    = true
  ebs_volume_size      = 100
#  bootstrap            = "${module.bootstrap.pulp_cloutinit}"
}

module "vpn" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
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
module "stage_railsapp" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  role                 = "railsapp"
  hostname             = "stageapp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  enable_aws_eip       = true
  instance_type        = "t2.small"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.stageapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
}

module "stage_railsapp_02" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  role                 = "railsapp"
  hostname             = "stageapp-02"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.small"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.stageapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
}

###############################
#
# Production Application Server
#
###############################
module "prod_railsapp" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  role                 = "railsapp"
  hostname             = "prodapp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-app}"
  instance_type        = "t2.small"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.prodapp_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
#  route53_external_id  = "${module.dns.route53_external_id}"
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
  password               = "YourPwdShouldBeLongAndSecure!"
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
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws-alb.git"
  environment          = "staging"
  host_prefix          = "${module.vpc.host_prefix}"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.app-lb_id}" ]
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
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws-alb.git"
  environment          = "production"
  host_prefix          = "${module.vpc.host_prefix}"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.app-lb_id}" ]
  vpc_id               = "${module.vpc.vpc_id}"
  subnets              = [ "${module.vpc.a-dmz}", "${module.vpc.b-dmz}" ]
  app_ssl_domain       = "production.${var.external_domain_name}"
  external_domain_name = "${var.external_domain_name}"
  route53_external_id  = "${module.dns.route53_external_id}"
}

###############################
#
# Stage Attach Nodes to LB
#
###############################
resource "aws_alb_target_group_attachment" "stageapp-http" {
  target_group_arn = "${module.stage_lb.app-http_arn}"
  target_id        = "${module.stage_railsapp.hostname_id}"
}

resource "aws_alb_target_group_attachment" "stageapp-01-stageapp-https" {
  count            = "${var.app_ssl_enable}"
  target_group_arn = "${module.stage_lb.app-https_arn}"
  target_id        = "${module.stage_railsapp.hostname_id}"
}




