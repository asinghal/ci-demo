
# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
}


# Create a VPC to launch our instances into
resource "aws_vpc" "main" {
  cidr_block = "${var.vpc_cidr}"

  tags {
    Name = "${var.name}"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"
  tags {
    Name = "${var.name}"
  }
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.main.id}"
}



# Create a subnet to launch our instances into
resource "aws_subnet" "api" {
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "${var.subnet_cidr}"
  map_public_ip_on_launch = true
  tags {
    Name = "${var.name}"
  }
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "${var.name}-elb"
  description = "ELB for ${var.name}"
  vpc_id      = "${aws_vpc.main.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "${var.name}-elb"
  }
}

resource "aws_elb" "api" {
  name = "${var.name}-elb"

  subnets         = ["${aws_subnet.api.id}"]
  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:80"
    interval            = 30
  }
}



resource "aws_ecs_cluster" "app" {
  name = "${var.name}"
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "app" {
  name        = "${var.name}"
  description = "Security for app instances"
  vpc_id      = "${aws_vpc.main.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "${var.name}"
  }
}

resource "aws_launch_configuration" "app" {
    name            = "${var.name}"
    instance_type   = "t2.micro"
    image_id        = "ami-c17ce0d6"
    security_groups = [ "${aws_security_group.app.id}" ]

    # The name of our SSH keypair.
    key_name = "${var.key_name}"

    iam_instance_profile = "${aws_iam_instance_profile.ecs.name}"
    user_data            = "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.app.name} > /etc/ecs/ecs.config"
}

# the autoscaling group determines health based on ELB stats
resource "aws_autoscaling_group" "app" {
    name                      = "${var.name}"
    availability_zones        = [ "${aws_subnet.api.availability_zone}" ]
    vpc_zone_identifier       = [ "${aws_subnet.api.id}" ]
    load_balancers            = [ "${aws_elb.api.id}" ]
    min_size                  = 3
    max_size                  = 3
    desired_capacity          = 3
    health_check_type         = "EC2"
    health_check_grace_period = 300
    force_delete              = false
    launch_configuration      = "${aws_launch_configuration.app.name}"

    tag {
      key = "Name"
      value = "${var.name}"
      propagate_at_launch = true
    }

}


/* ecs iam role and policies */
resource "aws_iam_role" "ecs_role" {
  name               = "ecs_role_${var.name}"
  assume_role_policy = "${file("${path.module}/policies/ecs-role.json")}"
}

/* ec2 container instance role & policy */
resource "aws_iam_role_policy" "ecs_instance_role_policy" {
  name     = "ecs_instance_role_policy_${var.name}"
  policy   = "${file("${path.module}/policies/ecs-instance-role-policy.json")}"
  role     = "${aws_iam_role.ecs_role.id}"
}

/**
 * IAM profile to be used in auto-scaling launch configuration.
 */
resource "aws_iam_instance_profile" "ecs" {
  name = "ecs-instance-profile_${var.name}"
  path = "/"
  roles = ["${aws_iam_role.ecs_role.name}"]
}


resource "template_file" "ecs_service_role_policy" {
  template = "${file("${path.module}/policies/ecs-service-role-policy.json")}"
}

/* ecs service scheduler role */
resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name     = "ecs_service_role_policy"
  policy   = "${template_file.ecs_service_role_policy.rendered}"
  role     = "${aws_iam_role.ecs_role.id}"
}


resource "template_file" "ecs_task" {
  template = "${file("${path.module}/task-definitions/app.json")}"

  vars {
    container_name    = "${var.name}"
    docker_image      = "janroesner/nodetest:0.0.6"
    container_port    = "3000"
    container_port2   = "3000"
    aws_region        = "${var.aws_region}"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                = "${var.name}"
  container_definitions = "${template_file.ecs_task.rendered}"
}

/* container and task definitions for running the actual app */
resource "aws_ecs_service" "app" {
  name            = "${var.name}"
  cluster         = "${aws_ecs_cluster.app.id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = 2
  iam_role        = "${aws_iam_role.ecs_role.arn}"
  depends_on      = ["aws_iam_role_policy.ecs_service_role_policy"]

  load_balancer {
    elb_name       = "${aws_elb.api.id}"
    container_name = "${var.name}"
    container_port = "3000"
  }
}
