variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "Whitelisted IPs allowed to SSH"
}

resource "aws_security_group" "minecraft" {
  name        = "${var.project_name}-sg"
  description = "Minecraft server access"

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from whitelisted IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}