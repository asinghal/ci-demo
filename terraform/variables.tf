variable "aws_region" {
  description = "AWS region to launch servers."
  default = "us-east-1"
}

variable "key_name" {
  description = "Desired name of AWS key pair"
}

variable "vpc_cidr" {
  default = "10.1.0.0/16"
}

variable "subnet_cidr" {
  default = "10.1.0.0/24"
}


variable "name" {
  default = "ci-demo"
}
