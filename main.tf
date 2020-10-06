provider "aws" {
  version = "~> 2.0"
  region     = var.region
}

# create the VPC
resource "aws_vpc" "Web_Server_VPC" {
  cidr_block           = var.vpcCIDRblock
  instance_tenancy     = var.instanceTenancy 
  enable_dns_support   = var.dnsSupport 
  enable_dns_hostnames = var.dnsHostNames
tags = {
    Name = "Web_Server_VPC"
}
} # end resource

# create the Subnet
resource "aws_subnet" "Web_Server_Subnet" {
  vpc_id                  = aws_vpc.Web_Server_VPC.id
  cidr_block              = var.subnetCIDRblock
  map_public_ip_on_launch = var.mapPublicIP 
  availability_zone       = var.availabilityZone
tags = {
   Name = "Web_Server_Subnet"
}
} # end resource

# Create the Security Group
resource "aws_security_group" "Web_Server_Security_Group" {
  vpc_id       = aws_vpc.Web_Server_VPC.id
  name         = "Web_Server_Security_Group"
  description  = "Web_Server_Security_Group"
  
  # allow ingress of port 22
  ingress {
    cidr_blocks = var.ingressCIDRblock  
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  } 
  
  # allow egress of all ports
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
   Name = "Web_Server_Security_Group"
   Description = "Web_Server_Security_Group"
}
} # end resource

# create VPC Network access control list
resource "aws_default_network_acl" "Web_Server_Security_ACL" {
  #vpc_id = aws_vpc.Web_Server_VPC.id
  default_network_acl_id = aws_vpc.Web_Server_VPC.default_network_acl_id
  subnet_ids = [ aws_subnet.Web_Server_Subnet.id ]
# allow ingress port 22
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.destinationCIDRblock 
    from_port  = 22
    to_port    = 22
  }
  
  # allow ingress port 80 
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.destinationCIDRblock 
    from_port  = 80
    to_port    = 80
  }
      
  # allow egress port 22 
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.destinationCIDRblock
    from_port  = 22 
    to_port    = 22
  }
  
  # allow egress port 80 
  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.destinationCIDRblock
    from_port  = 80  
    to_port    = 80 
  }
   
tags = {
    Name = "Web_Server_ACL"
}
} # end resource

# Create the Internet Gateway
resource "aws_internet_gateway" "Web_Server_GW" {
 vpc_id = aws_vpc.Web_Server_VPC.id
 tags = {
        Name = "Web_Server Internet Gateway"
}
} # end resource

# Create the Route Table
resource "aws_route_table" "Web_Server_route_table" {
 vpc_id = aws_vpc.Web_Server_VPC.id
 tags = {
        Name = "Web_Server Route Table"
}
} # end resource

# Create the Internet Access
resource "aws_route" "Web_Server_internet_access" {
  route_table_id         = aws_route_table.Web_Server_route_table.id
  destination_cidr_block = var.destinationCIDRblock
  gateway_id             = aws_internet_gateway.Web_Server_GW.id
} # end resource

# Associate the Route Table with the VPC
resource "aws_main_route_table_association" "Web_Server_RT_association" {
  vpc_id         = aws_vpc.Web_Server_VPC.id
  route_table_id = aws_route_table.Web_Server_route_table.id
} # end resource

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "Web_Server_association" {
  subnet_id      = aws_subnet.Web_Server_Subnet.id
  route_table_id = aws_route_table.Web_Server_route_table.id
} # end resource

# Create a new S3 bucket for ELB
resource "aws_s3_bucket" "Web_Server_ELB_access_logs" {
  bucket = "web-server-elb-access-logs"
  acl    = "private"

  tags = {
    Name        = "Web_Server_ELB_access_logs"
  }
} # end resource

# Create a new Classic load balancer
resource "aws_elb" "Web_Server_Elb" {
  name               = "ELB"
  #availability_zones = [var.availabilityZone]
  security_groups = [aws_security_group.Web_Server_Security_Group.id]
  subnets = [aws_subnet.Web_Server_Subnet.id]
  access_logs {
    bucket        = "web-server-elb-access-logs"
    interval      = 60
  }

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = [aws_instance.Linux_Web_Server.id]
  cross_zone_load_balancing   = false
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "Web_Server_ELB"
  }
} # end resource

#Creating Linux web server
resource "aws_instance" "Linux_Web_Server" {
  ami                = "ami-015a6758451df3cb9"
  instance_type      = "t2.micro"
  security_groups    = [ aws_security_group.Web_Server_Security_Group.id ]
  subnet_id          = aws_subnet.Web_Server_Subnet.id
  key_name           = "abcd"
 
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("C:/Users/admin/Downloads/abcd.pem")
    host        = aws_instance.Linux_Web_Server.public_ip
  }
  user_data     = <<-EOF
                  #!/bin/bash
                  sudo su
                  yum -y install httpd
                  echo "<p> Hello AWS World – running on Linux – on port 80 </p>" >> /var/www/html/index.html
                  sudo systemctl enable httpd
                  sudo systemctl start httpd
                  EOF
  tags = {
    Name = "Linux_Web_Server"
  }
}

#Creating ebs volume
resource "aws_ebs_volume" "Web_Server_EBS" {
 availability_zone  = var.availabilityZone
 size = 1
 tags = {
        Name = "Web_Server_EBS"
 }

}
#Attaching EBS volume 
resource "aws_volume_attachment" "Web_Server_EBS_attachment" {
 device_name = "/dev/sdc"
 volume_id = aws_ebs_volume.Web_Server_EBS.id
 instance_id = aws_instance.Linux_Web_Server.id
}
