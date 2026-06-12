resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-spot-asg-sg"
  description = "Jenkins access"

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-spot-asg-sg"
  }
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"] #["al2023-ami-*-x86_64"]
  }
}

resource "aws_key_pair" "laptopswo_key" {
  key_name   = "laptopswo"
  public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
}

resource "aws_ebs_volume" "jenkins_data" {
  availability_zone = local.az
  type              = "gp3"
  size              = 4
  encrypted         = false
  throughput        = 125
  iops              = 3000

  tags = {
    Name = "jenkins-data-volume"
  }
}

##Commenting to use dyndns for public IP management instead of EIP
# resource "aws_eip" "jenkins_eip" {
#   domain = "vpc"
#   tags = {
#     Name = "jenkins-production-eip"
#   }
# }

# resource "aws_network_interface" "jenkins_eni" {
#   subnet_id       = data.aws_subnet.selected.id
#   security_groups = [aws_security_group.jenkins_sg.id]

#   tags = {
#     Name = "jenkins-primary-eni"
#   }
# }

# resource "aws_eip_association" "eip_assoc" {
#   network_interface_id = aws_network_interface.jenkins_eni.id
#   allocation_id        = aws_eip.jenkins_eip.id
# }

resource "aws_launch_template" "jenkins" {
  name_prefix   = "jenkins-spot-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t4g.medium"
  key_name      = aws_key_pair.laptopswo_key.key_name

  # protect from surge cost
  credit_specification {
    cpu_credits = "standard"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.jenkins_sg.id]
    delete_on_termination       = true
    # network_interface_id = aws_network_interface.jenkins_eni.id
    # device_index         = 0
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    volume_id = aws_ebs_volume.jenkins_data.id
    region    = data.aws_region.current.name
    cert_json = local.cert_json
    device    = "/dev/xvdf"
  }))

  #########
  ## root volume xvda is automatically created.
  ## it will be created by the size of the image and default to deletion on termination true
  ## the jenkins data volume must be attach and mount through user script because we use spot instance that change frequently, 
  ## so we can't use block device mapping to attach the data volume, 
  ## otherwise we will lose data when instance is terminated and recreated with new volume.
  #########
  # block_device_mappings {
  # #   device_name = "/dev/xvda"
  # #   ebs {
  # #     volume_size = 30
  # #     volume_type = "gp3"
  # #     delete_on_termination = true
  # #     encrypted             = false
  # #     iops        = 3000
  # #     throughput = 125
  # #   }
  # }

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "terminate"
    }
  }

  placement {
    availability_zone = local.az #data.aws_subnet.jenkins.availability_zone
  }

  iam_instance_profile {
    name = "jenkins_instance_profile"
  }

  lifecycle {
    ignore_changes = [
      image_id,  # Ignore changes to AMI ID to prevent recreation when new AMIs are available
    ]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Jenkins-Server"
    }
  }
}

resource "aws_autoscaling_group" "jenkins" {
  name                = "jenkins-spot-asg"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 1
  ##Commenting to use dyndns for public IP management instead of EIP
  # availability_zones  = [local.az]
  vpc_zone_identifier = [data.aws_subnet.selected.id]

  launch_template {
    id      = aws_launch_template.jenkins.id
    version = aws_launch_template.jenkins.latest_version
  }

  health_check_type         = "EC2"
  health_check_grace_period = 120
  wait_for_capacity_timeout = "10m"
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      max_healthy_percentage = 100
      checkpoint_delay       = 300
    }
  }

  tag {
    key                 = "Name"
    value               = "jenkins-spot-node"
    propagate_at_launch = true
  }
}



