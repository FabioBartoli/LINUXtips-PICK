variable "ami" {}
variable "instance_type" {}
variable "volume_size" {}
variable "instance_count" {}
variable "vpc_id" {}
variable "k8s_subnet_cidr" {}
variable "k8s_subnet_cidr_2" {}
variable "k8s_subnet_az" {}
variable "k8s_subnet_az_2" {}
variable "AWS_ACCESS_KEY_ID" {}
variable "AWS_SECRET_ACCESS_KEY" {}
variable "private_key" {}
variable "public_key" {}
variable "security_group_rules" {
  type = list(object({
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_blocks = list(string)
  }))
}

variable "key_name" {
  description = "The name of the key pair to use for the instances"
  default     = "k8s-key"
}
