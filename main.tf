provider "aws" {
  region  = "${var.region}"
  profile = "${var.profile}"
}

module "vpc" {
  source            = "git::https://nfosdick@bitbucket.org/larkit/vpc.git"
  profile           = "${var.profile}"
  host_prefix       = "${var.host_prefix}"
  environment       = "${var.environment}"
  region            = "${var.region}"
  availability_zone = "a"
}

module "security_groups" {
  source      = "git::https://nfosdick@bitbucket.org/larkit/security_groups.git"
  host_prefix = "${var.host_prefix}"
  vpc_id      = "${module.vpc.vpc_id}"
  cidr        = "${module.vpc.cidr}"
}

module "dns" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/dns.git"
  vpc_id               = "${module.vpc.vpc_id}"
  internal_domain_name = "${var.internal_domain_name}"
  cidr                 = "${module.vpc.cidr}"
  domain_name_servers  = "${cidrhost("${module.vpc.cidr}", 2)}"
}

module "policy" {
  source = "git::https://nfosdick@bitbucket.org/larkit/policy.git"
}

module "iam_role" {
  source                = "git::https://nfosdick@bitbucket.org/larkit/iam_role.git"
  cloudwatch_policy_arn = "${module.policy.cloudwatch_policy_arn}"
  ec2_admin_policy_arn  = "${module.policy.ec2_admin_policy_arn}"
}

module "bootstrap" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/bootstrap.git"
  internal_domain_name = "${module.dns.internal_domain_name}"
  host_prefix          = "${module.vpc.host_prefix}"
}

module "foreman" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  hostname             = "foreman-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}", "${module.security_groups.foreman_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
  bootstrap            = "${module.bootstrap.foreman_cloutinit}"
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
  bootstrap            = "${module.bootstrap.gitlab_cloutinit}"
}

module "pulp" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  hostname             = "pulp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  instance_type        = "t2.medium"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
  bootstrap            = "${module.bootstrap.pulp_cloutinit}"
}


module "stage_railsapp" {
  source               = "git::https://nfosdick@bitbucket.org/larkit/aws_instance.git"
  hostname             = "stageapp-01"
  host_prefix          = "${module.vpc.host_prefix}"
  internal_domain_name = "${module.dns.internal_domain_name}"
  region               = "${var.region}"
  availability_zone    = "${module.vpc.availability_zone}"
  subnet_id            = "${module.vpc.a-dmz}"
  instance_type        = "t2.small"
  security_groups      = [ "${module.security_groups.general_id}", "${module.security_groups.ssh_jump_id}" ]
  route53_internal_id  = "${module.dns.route53_internal_id}"
  route53_external_id  = "${module.dns.route53_external_id}"
  bootstrap            = "${module.bootstrap.railsapp_cloutinit}"
}

#module "stage_db" {
module "db" {
  source                 = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git"
  identifier             = "stage"
  engine                 = "postgres"
  engine_version         = "9.6.2"
  instance_class         = "db.t2.small"
  allocated_storage      = 5
  name                   = "stagedb"
  username               = "dbadmin"
  password               = "YourPwdShouldBeLongAndSecure!"
  port                   = "5432"
  vpc_security_group_ids = [ "${module.security_groups.general_id}" ]
  maintenance_window     = "Mon:00:00-Mon:03:00"
  backup_window          = "03:00-06:00"
  subnet_ids             = [ "${module.vpc.a-db}", "${module.vpc.b-db}" ]
  family = "postgres9.6"
  
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

module "stage_lb" {
  source          = "git::https://nfosdick@bitbucket.org/larkit/aws-alb.git"
  environment     = "staging"
  host_prefix     = "${module.vpc.host_prefix}"
  hostnames        = "${module.stage_railsapp.hostname_id}"
  security_groups = [ "${module.security_groups.general_id}" ]
  vpc_id          = "${module.vpc.vpc_id}"
  subnets         = [ "${module.vpc.a-dmz}", "${module.vpc.b-dmz}" ]
}






