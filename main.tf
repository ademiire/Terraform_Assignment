provider "aws" {
 region = "eu-west-2"
}

resource "aws_vpc" "my_vpcade" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
  tags = {
    name = "my-main-vpc"
  }
}

resource "aws_internet_gateway" "cba_igw1" {
  vpc_id = aws_vpc.my_vpcade.id
  tags = {
    Name = "ApacheIGW"
  }
}

resource "aws_subnet" "cba_public1" {
  vpc_id                  = aws_vpc.my_vpcade.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "eu-west-2a"

  tags = {
    Name = "ApachePublicSubnet1"
  }
}

resource "aws_subnet" "cba_public2" {
  vpc_id                  = aws_vpc.my_vpcade.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "eu-west-2b"

  tags = {
    Name = "ApachePublicSubnet2"
  }
}

resource "aws_subnet" "cba_private1" {
  vpc_id                  = aws_vpc.my_vpcade.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "eu-west-2a"

  tags = {
    Name = "ApachePrivateSubnet1"
  }
}

resource "aws_subnet" "cba_private2" {
  vpc_id                  = aws_vpc.my_vpcade.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "eu-west-2b"

  tags = {
    Name = "ApachePrivateSubnet2"
  }
}


resource "aws_route_table" "cba_public_rt1" {
  vpc_id = aws_vpc.my_vpcade.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cba_igw1.id
  }

  tags = {
    Name = "ApachePublicRT"
  }

}


resource "aws_route_table" "cba_private_rt" {
  vpc_id = aws_vpc.my_vpcade.id

  tags = {
    Name = "ApachePrivateRT"
  }

}



resource "aws_route_table_association" "public_route_table_assoc" {
  route_table_id = aws_route_table.cba_public_rt1.id
  subnet_id     = aws_subnet.cba_public1.id
}

resource "aws_route_table_association" "private_route_table_assoc" {
  route_table_id = aws_route_table.cba_private_rt.id
  subnet_id     = aws_subnet.cba_private1.id
}


resource "aws_eip" "nat_gateway" {
  #instance_id = aws_nat_gateway.main.id
  domain      = "vpc"
  tags = {
    Name = "nat-gateway-eip"
  }
}


resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.cba_private1.id

  tags = {
    Name = "main-nat-gateway"
  }
}


resource "aws_security_group" "cba_tf_sg1" {
  name        = "cba_tf_sg1"
  vpc_id      = aws_vpc.my_vpcade.id
  description = "allow all traffic"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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
    name = "CBAterraformSG"
  }
}


resource "aws_lb" "internet_facing" {
  name               = "internet-facing-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.cba_public1.id, aws_subnet.cba_public2.id]
  security_groups    = [aws_security_group.cba_tf_sg1.id]

  tags = {
    Name = "Internet-Facing ALB"
  }
}

resource "aws_lb" "lbinternal" {
  name               = "lbinternal-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.cba_private1.id, aws_subnet.cba_private2.id]
  ##scheme             = "internal"

  tags = {
    Name = "Internal ALB"
  }
}


resource "aws_lb_target_group" "internet_facing_target_group" {
  name        = "internet-facing-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpcade.id


}

resource "aws_lb_target_group" "internal_target_group" {
  name        = "internal-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpcade.id

 }

 resource "aws_launch_template" "launch_config" {
  name = "launch_config"

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 20
    }
  }

  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }

 # cpu_options {
 #   core_count       = 4
 #  threads_per_core = 2
 # }

  credit_specification {
    cpu_credits = "standard"
  }

  disable_api_stop        = true
  disable_api_termination = true
  ebs_optimized = true
  image_id = "ami-03c6b308140d10488"
  instance_type = "t2.micro"
  key_name = "ademide_keypair"
  vpc_security_group_ids = [aws_security_group.cba_tf_sg1.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "test"
    }
  }

  
}

resource "aws_autoscaling_group" "autoscaling" {
  desired_capacity          = 2
  max_size                  = 5
  min_size                  = 1
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.cba_public1.id,aws_subnet.cba_public2.id]

  target_group_arns = [aws_lb_target_group.internal_target_group.arn]

  # Correct block for Launch Template
  launch_template {
    id      = aws_launch_template.launch_config.id
    version = "$Latest"

 }

  tag {
    key                 = "Name"
    value               = "example-asg"
    propagate_at_launch = true
  }
}


#resource "aws_instance" "cba_tf_instance" {
#  ami             = data.aws_ssm_parameter.instance_ami.value
#  instance_type   = var.instance_type
#  subnet_id       = aws_subnet.cba_public1.id
#  security_groups = [aws_security_group.cba_tf_sg.id]
#  key_name        = var.key_name
#  user_data       = fileexists("install_apache.sh") ? file("install_apache.sh") : null


#  tags = {
 #   "Name" = "ApacheInstance"
 # }

#}

resource "aws_instance" "bastion" {
  ami           = "ami-03c6b308140d10488" # Replace with the desired AMI ID
  instance_type = "t2.micro" # Replace with the desired instance type
  key_name      = "ademide_keypair" # Replace with your key pair name
  subnet_id     = aws_subnet.cba_public1.id

  tags = {
    Name = "Bastion Host"
  }

  security_groups = [aws_security_group.cba_tf_sg1.id]
}




