output "ec2_public_ip" {
  description = "Public IP from my EC2"
  value       = aws_instance.Conv_EC2.public_ip
}
