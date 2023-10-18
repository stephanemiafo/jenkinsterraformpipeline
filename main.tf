terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-2"             #  var.aws_region
}

data "aws_availability_zones" "my_az" {
  state = "available"
}

resource "random_integer" "tag" {
  min = 1
  max = 5000
}

resource "aws_vpc" "my_vpc" {
    cidr_block       = var.vpc_cidr     
    enable_dns_support = var.dns_support     
    enable_dns_hostnames = var.dns_hostnames 
    tags = {
        Name = "my_vpc_${random_integer.tag.id}"
    }
}

resource "aws_security_group" "pipe_sg" {
  name        = "pipe_sg"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description      = "traffic from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pipe_sg"
  }
}

variable "vpc_cidr" {
  type = string
  description = "the CIDR of the vpc"     # (REQUIRED)
  default = "192.168.0.0/16"
}

variable "dns_support" {
  type = bool
  description = "DNS support in the VPC"    # (OPTIONAL)
  default = true
}

variable "dns_hostnames" {
  type = bool
  description = "DNS hostnames in the VPC"     # (OPTIONAL)
  default = true
}

resource "aws_subnet" "subnet" {
    count = var.my_count   # number of subnets to be created
    vpc_id     = aws_vpc.my_vpc.id  # ID of the VPC where the subnet will be created.
    cidr_block = cidrsubnet(var.vpc_cidr , 8, count.index)
    # The availability zone where the subnet will be created. 
    # The subnets are evenly distributed across the available zones 1a, 1b. 1c.
    availability_zone = (count.index < 3 ? 
    element(data.aws_availability_zones.my_az.names, count.index) : 
    count.index < 6 ? element(data.aws_availability_zones.my_az.names, count.index - 3) : 
    element(data.aws_availability_zones.my_az.names, count.index - 6))
    # Indicates whether instances launched in this subnet should be assigned a public IP address or not.
    map_public_ip_on_launch = count.index < 3 ? true : false 
    tags = {
        Name = (count.index < 3
            ? "public_subnet_${count.index + 1}_${random_integer.tag.id}"
            : count.index < 6
                ? "private_subnet_${count.index - 2}_${random_integer.tag.id}"
                : "DataBase_subnet_${count.index - 5}_${random_integer.tag.id}")
    }
}

variable "my_count" {
  type = number
  description = "number of subnets to create"       # (OPTIONAL)
  default = 9
}

# BATTLE TESTED INSTANCE
resource "aws_instance" "al2" {
  ami = "ami-09538990a0c4fe9be"
  instance_type = "t2.micro"
  metadata_options {                    # Prevent the Instance metadata service to be interacted with freely.
    http_tokens = "required"
    http_endpoint = "enabled"
  } 
  key_name = "playground"
  vpc_security_group_ids = [aws_security_group.pipe_sg.id]
  subnet_id      = element(aws_subnet.subnet[*].id, 0)
  user_data = <<-EOT
              #!/bin/bash
              yum update -y
              yum install httpd -y
              systemctl start httpd
              systemctl enable httpd
              echo "WELCOME TO TERRAFORM" > /var/www/html/index.html
              EOT
  tags = {
    "Name" = "Hello-World-DYNAMYC"
  }
}

/*
THIS RESOURCE ALONE WILL CREATE AND ATTACHED THE IGW TO THE VPC
SO, THERE IS NO NEED TO CREATE A GW ATTACHMENT
*/
resource "aws_internet_gateway" "my_igw" {
    vpc_id = aws_vpc.my_vpc.id
    tags = {
      Name = "my_igw_${random_integer.tag.id}"
    }
}

resource "aws_route_table" "my_public_route" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "public-rtb_${random_integer.tag.id}"
  }
  route {
    cidr_block = var.internet_cidr                     
    gateway_id = aws_internet_gateway.my_igw.id                            
  }
}

variable "internet_cidr" {
  type = string
  description = "the generic cidr"
  default = "0.0.0.0/0"
}

# Associate the public subnet1 with the public route table
resource "aws_route_table_association" "pub_sub1_rta" {
  # Retriving the first public subnet id.
  subnet_id      = element(aws_subnet.subnet[*].id, 0)             # retrieving the first public subnet ID.
  route_table_id = aws_route_table.my_public_route.id                    # and associating it with public rt
}

# Associate the public subnet2 with the public route table
resource "aws_route_table_association" "pub_sub2_rta" {
  # Retriving the second public subnet id.
  subnet_id      = element(aws_subnet.subnet[*].id, 1)             # retrieving the first public subnet ID.
  route_table_id = aws_route_table.my_public_route.id                    # and associating it with public rt
}

# Associate the public subnet3 with the public route table
resource "aws_route_table_association" "pub_sub3_rta" {
  # Retriving the third public subnet id.
  subnet_id      = element(aws_subnet.subnet[*].id, 2)             # retrieving the first public subnet ID. 
  route_table_id = aws_route_table.my_public_route.id                    # and associating it with public rt
}

resource "aws_route_table" "my_route" {
  vpc_id = aws_vpc.my_vpc.id
  count = var.private_count
  tags = {
    Name = (count.index < 3 ? "private_rtb_${count.index + 1}" 
      : "DataBase_rtb_${count.index - 2}_${random_integer.tag.id}")
  }
}

variable "private_count" {
  type = number
  description = "the number of private rtb to be created"
  default = 6
}

resource "aws_route_table_association" "private_association" {
  count          = var.priv_assoc_count
  subnet_id      = aws_subnet.subnet[count.index + 3].id
  route_table_id = aws_route_table.my_route[count.index].id
}

resource "aws_route_table_association" "db_association" {
  count          = var.priv_assoc_count
  subnet_id      = aws_subnet.subnet[count.index + 6].id
  route_table_id = aws_route_table.my_route[count.index + 3].id
}

variable "priv_assoc_count" {
  type = number
  description = "the number of private rtb association to be created"
  default = 3
}

resource "aws_security_group" "my_mod_sg" {
  name        = "my_mod_sg"
  description = "Allow inbound traffic"
   vpc_id = aws_vpc.my_vpc.id
  ingress {
    description      = "traffic from internet"
    from_port        = var.http_ingress_port
    to_port          = var.http_ingress_port
    protocol         = var.protocol
    cidr_blocks      = [var.internet_cidr]
  }
  ingress {
    description      = "traffic from VPC"
    from_port        = var.ssh_ingress_port
    to_port          = var.ssh_ingress_port
    protocol         = var.protocol
    cidr_blocks      = [var.internet_cidr]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [var.internet_cidr]
  }
  tags = {
    Name = "my_mod_sg_${random_integer.tag.id}"
  }
}

variable "ssh_ingress_port" {
  type = number
  description = "the port to which ssh listen to"
  default = 22
}

variable "http_ingress_port" {
  type = number
  description = "the port to which http listen to"
  default = 80
}

variable "protocol" {
  type = string
  description = "the protocol used by the SG"
  default = "tcp"
}

output "SG_id" {
    value = aws_security_group.my_mod_sg.id 
    description = "the sg id "
}

output "vpc_id" {
    value = aws_vpc.my_vpc.id
    description = "the vpc id"
}

output "public_subnets_id" {
    value       = slice(aws_subnet.subnet[*].id, 0, 3)
    description = "the list of public subnet ids"
}

output "private_subnets_id" {
    value       = slice(aws_subnet.subnet[*].id, 3, 6)
    description = "the list of private subnet ids"
}

output "database_subnets_id" {
    value       = slice(aws_subnet.subnet[*].id, 6, 9)
    description = "the list of database subnet ids"
}

output "availability_zone" {
    value = slice(data.aws_availability_zones.my_az.names, 0, 3)
    description = "the list of availability_zone"
}

output "public_subnets_cidr" {
    # value = aws_subnet.pub_subnet[*].cidr_block 
    value =  slice(aws_subnet.subnet[*].cidr_block, 0, 3)
    description = "the list of public subnet cidrs"
}

output "private_subnets_cidr" {
    # value = aws_subnet.pub_subnet[*].cidr_block 
    value =  slice(aws_subnet.subnet[*].cidr_block, 3, 6)
    description = "the list of private subnet cidrs"
}

output "database_subnets_cidr" {
    # value = aws_subnet.pub_subnet[*].cidr_block 
    value =  slice(aws_subnet.subnet[*].cidr_block, 6, 9)
    description = "the list of database subnet cidrs"
}


