terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
B  region = "us-east-1" # Or your preferred region
}

# Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "quickcart-vpc"
  }
}
# 1. Create a Public Subnet
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # This makes it "Public"
  availability_zone       = "us-east-1a"

  tags = {
    Name = "quickcart-public-1"
  }
}

# 2. Create the Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "quickcart-igw"
  }
}

# 3. Create a Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" # Represents the whole internet
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "quickcart-public-rt"
  }
}

# 4. Associate the Subnet with the Route Table
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. Create a Security Group
resource "aws_security_group" "quickcart_sg" {
  name        = "quickcart-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  # Inbound: Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In a real job, you'd use your specific IP
  }

  # Inbound: Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow everything
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. Create the EC2 Instance
resource "aws_instance" "app_server" {
  ami                    = "ami-0440d3b780d96b29d" # Amazon Linux 2023 in us-east-1
  instance_type          = "t2.micro"
  key_name		 = "Lab-Test"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.quickcart_sg.id]

  # This script runs on the very first boot
  user_data = <<-EOF
              #!/bin/bash
              sudo dnf update -y
              sudo dnf install -y docker git
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ec2-user
              
              # Automated Swap Fix (Enterprise Best Practice for small nodes)
              sudo dd if=/dev/zero of=/swapfile bs=128M count=16
              sudo chmod 600 /swapfile
              sudo mkswap /swapfile
              sudo swapon /swapfile
              echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
              EOF

  tags = {
    Name = "quickcart-app-server"
  }
}

output "quickcart_public_ip" {
  value       = aws_instance.app_server.public_ip
  description = "The public IP of the new QuickCart app server"
}

# 9. Security Group for the Database (The Vault Gate)
resource "aws_security_group" "db_sg" {
  name        = "quickcart-db-sg"
  vpc_id      = aws_vpc.main.id

  # ONLY allow traffic from the Web Server Security Group
  ingress {
    from_port       = 5432 # Standard Port for PostgreSQL
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.quickcart_sg.id]
  }

  tags = { Name = "quickcart-db-sg" }
}

resource "aws_db_subnet_group" "quickcart_db_group" {
  name       = "quickcart-db-group"
  subnet_ids = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]

  tags = { Name = "QuickCart DB Subnet Group" }
}

# 10. The RDS Database Instance
resource "aws_db_instance" "quickcart_db" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "16.1"
  instance_class       = "db.t4g.micro" # Cost-efficient for lab
  db_name              = "quickcart"
  username             = "adminuser"
  password             = "QuickCartSecure123!" # In real life, use a Secret Manager!
  parameter_group_name = "default.postgres16"
  skip_final_snapshot  = true
  
  db_subnet_group_name   = aws_db_subnet_group.quickcart_db_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

}
