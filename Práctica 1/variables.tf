variable "region" {
  description = "Region to be deployed"
  type        = string
  default     = "eu-central-1"
}

variable "public_key_location" {
  description = "The file path to the SSH public key used for accessing the instances."
  type        = string
  default     = "/home/alvaro/.ssh/id_rsa.pub"
}

variable "ip_whitelist" {
  type = list(string)
}