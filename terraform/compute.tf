data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

resource "aws_launch_template" "minecraft" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.minecraft.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  user_data = base64encode(templatefile("${path.module}/../user-data/bootstrap.sh", {
    bucket_name       = aws_s3_bucket.minecraft.bucket
    minecraft_version = "1.21.1"
    fabric_loader     = "0.16.10"
    fabric_installer  = "1.0.3"
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = var.project_name
      Project = var.project_name
    }
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = 10
      volume_type           = "gp3"
    }
  }
}