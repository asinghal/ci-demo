output "address" {
  value = "${aws_elb.api.dns_name}"
}

output "repository_url" {
  value = "${aws_ecr_repository.registry.repository_url}"
}
