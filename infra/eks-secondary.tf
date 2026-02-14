# Configure AWS provider for us-west-2


	# ===== SECONDARY CLUSTER IN US-WEST-2 =====

# VPC for secondary cluster
resource "aws_vpc" "secondary" {
  provider             = aws.west
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "gitops-vpc-west"
  }
}

# Get availability zones in us-west-2
data "aws_availability_zones" "available_west" {
  provider = aws.west
  state    = "available"
}

# Private subnets (3)
resource "aws_subnet" "private_west" {
  provider          = aws.west
  count             = 3
  vpc_id            = aws_vpc.secondary.id
  cidr_block        = "10.1.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available_west.names[count.index]

  tags = {
    Name = "gitops-private-west-${count.index + 1}"
  }
}

# Public subnets (3)
resource "aws_subnet" "public_west" {
  provider                = aws.west
  count                   = 3
  vpc_id                  = aws_vpc.secondary.id
  cidr_block              = "10.1.${count.index + 101}.0/24"
  availability_zone       = data.aws_availability_zones.available_west.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "gitops-public-west-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "secondary" {
  provider = aws.west
  vpc_id   = aws_vpc.secondary.id

  tags = {
    Name = "gitops-igw-west"
  }
}

# Elastic IPs for NAT
resource "aws_eip" "nat_west" {
  provider = aws.west
  count    = 3
  domain   = "vpc"

  depends_on = [aws_internet_gateway.secondary]

  tags = {
    Name = "gitops-eip-west-${count.index + 1}"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "secondary" {
  provider      = aws.west
  count         = 3
  allocation_id = aws_eip.nat_west[count.index].id
  subnet_id     = aws_subnet.public_west[count.index].id

  depends_on = [aws_internet_gateway.secondary]

  tags = {
    Name = "gitops-nat-west-${count.index + 1}"
  }
}

# Public route table
resource "aws_route_table" "public_west" {
  provider = aws.west
  vpc_id   = aws_vpc.secondary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary.id
  }

  tags = {
    Name = "gitops-public-rt-west"
  }
}

# Associate public subnets
resource "aws_route_table_association" "public_west" {
  provider       = aws.west
  count          = 3
  subnet_id      = aws_subnet.public_west[count.index].id
  route_table_id = aws_route_table.public_west.id
}

# Private route tables (one per AZ for NAT)
resource "aws_route_table" "private_west" {
  provider = aws.west
  count    = 3
  vpc_id   = aws_vpc.secondary.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.secondary[count.index].id
  }

  tags = {
    Name = "gitops-private-rt-west-${count.index + 1}"
  }
}

# Associate private subnets
resource "aws_route_table_association" "private_west" {
  provider       = aws.west
  count          = 3
  subnet_id      = aws_subnet.private_west[count.index].id
  route_table_id = aws_route_table.private_west[count.index].id
}

# ===== EKS CLUSTER =====

# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_west" {
  name = "gitops-eks-cluster-role-west"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_west" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_west.name
}

# Security group for cluster
resource "aws_security_group" "eks_cluster_west" {
  provider = aws.west
  name     = "gitops-eks-cluster-sg-west"
  vpc_id   = aws_vpc.secondary.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitops-eks-cluster-sg-west"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "secondary" {
  provider = aws.west
  name     = "gitops-secondary"
  version  = "1.29"
  role_arn = aws_iam_role.eks_cluster_west.arn

  vpc_config {
    subnet_ids              = aws_subnet.private_west[*].id
    security_group_ids      = [aws_security_group.eks_cluster_west.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name = "gitops-secondary"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_west]
}

# ===== WORKER NODES =====

# IAM role for nodes
resource "aws_iam_role" "eks_node_west" {
  name = "gitops-eks-node-role-west"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_west" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_west.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_west" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_west.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_west" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_west.name
}

# Security group for nodes
resource "aws_security_group" "eks_nodes_west" {
  provider = aws.west
  name     = "gitops-eks-nodes-sg-west"
  vpc_id   = aws_vpc.secondary.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_west.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitops-eks-nodes-sg-west"
  }
}

# Node Group (2 nodes instead of 3)
resource "aws_eks_node_group" "secondary" {
  provider        = aws.west
  cluster_name    = aws_eks_cluster.secondary.name
  node_group_name = "gitops-general-west"
  node_role_arn   = aws_iam_role.eks_node_west.arn
  subnet_ids      = aws_subnet.private_west[*].id
  version         = "1.29"

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  tags = {
    Name = "gitops-node-group-west"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_west,
    aws_iam_role_policy_attachment.eks_cni_west,
    aws_iam_role_policy_attachment.eks_registry_west
  ]
}

# Outputs
output "secondary_cluster_endpoint" {
  value       = aws_eks_cluster.secondary.endpoint
  description = "Secondary cluster endpoint"
}

output "secondary_cluster_name" {
  value       = aws_eks_cluster.secondary.name
  description = "Secondary cluster name"
}
