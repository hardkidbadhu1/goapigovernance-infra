provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_vpc" "goapigovernance_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "goapigovernance-vpc"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.goapigovernance_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "goapigovernance-public-1"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.goapigovernance_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "goapigovernance-private-1"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.goapigovernance_vpc.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"

  tags = {
    Name = "goapigovernance-public-2"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.goapigovernance_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "goapigovernance-private-2"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "public_subnet_3" {
  vpc_id                  = aws_vpc.goapigovernance_vpc.id
  cidr_block              = "10.0.5.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1d"

  tags = {
    Name    = "goapigovernance-public-3"
    Project = "goapigovernance"
  }
}

resource "aws_subnet" "private_subnet_3" {
  vpc_id            = aws_vpc.goapigovernance_vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "ap-northeast-1d"

  tags = {
    Name    = "goapigovernance-private-3"
    Project = "goapigovernance"
  }
}

resource "aws_internet_gateway" "goapigovernance_igw" {
  vpc_id = aws_vpc.goapigovernance_vpc.id

  tags = {
    Name = "goapigovernance-igw"
    Project = "goapigovernance"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.goapigovernance_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.goapigovernance_igw.id
  }

  tags = {
    Name = "goapigovernance-public-rt"
    Project = "goapigovernance"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_nat_gateway" "goapigovernance_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "goapigovernance-nat"
    Project = "goapigovernance"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "goapigovernance-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name    = "goapigovernance-eks-role"
    Project = "goapigovernance"
  }
}

# Attach Required Policies to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_cluster" "goapigovernance_eks" {
  name     = "goapigovernance-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  vpc_config {
    subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id, aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  }

  tags = {
    Name = "goapigovernance-eks"
    Project = "goapigovernance"
  }
}

resource "aws_iam_role" "eks_node_role" {
  name = "goapigovernance-eks-node-role"

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

  tags = {
    Name    = "goapigovernance-eks-node-role"
    Project = "goapigovernance"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_readonly_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_eks_node_group" "goapigovernance_nodes" {
  cluster_name    = aws_eks_cluster.goapigovernance_eks.name
  node_group_name = "goapigovernance-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id, aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role.eks_node_role,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_readonly_policy
  ]

  tags = {
    Name    = "goapigovernance-node-group"
    Project = "goapigovernance"
  }
}

resource "helm_release" "kong" {
  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  namespace  = "kong"

  set {
    name  = "proxy.type"
    value = "LoadBalancer"
  }

  set {
    name  = "admin.enabled"
    value = "true"
  }

  set {
    name  = "admin.type"
    value = "LoadBalancer"
  }
}


resource "aws_wafregional_web_acl" "goapigovernance_waf" {
  name        = "goapigovernance-waf"
  metric_name = "goapigovernanceWAF"

  default_action {
    type = "ALLOW"
  }

  tags = {
    Name = "goapigovernance-waf"
    Project = "goapigovernance"
  }
}

resource "aws_cognito_user_pool" "goapigovernance_user_pool" {
  name = "goapigovernance-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Name    = "goapigovernance-user-pool"
    Project = "goapigovernance"
  }
}

resource "aws_cognito_user_pool_client" "goapigovernance_user_client" {
  name         = "goapigovernance-client"
  user_pool_id = aws_cognito_user_pool.goapigovernance_user_pool.id
  generate_secret = true

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  supported_identity_providers = ["COGNITO"]

  callback_urls = ["https://admin.goapigovernance.com/callback"]
}


resource "aws_cloudwatch_log_group" "goapigovernance_logs" {
  name = "goapigovernance-logs"

  tags = {
    Name = "goapigovernance-logs"
    Project = "goapigovernance"
  }
}

resource "aws_kinesis_stream" "goapigovernance_kinesis" {
  name             = "goapigovernance-stream"
  shard_count      = 1

  tags = {
    Name = "goapigovernance-kinesis"
    Project = "goapigovernance"
  }
}

resource "aws_opensearch_domain" "goapigovernance_opensearch" {
  domain_name    = "goapigovernance-search"
  engine_version = "OpenSearch_2.3"

  ebs_options {
    ebs_enabled = true
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "goapigovernance-opensearch"
    Project = "goapigovernance"
  }
}

resource "aws_iam_role" "terraform_ec2_role" {
  name = "terraform-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name    = "terraform-ec2-role"
    Project = "goapigovernance"
  }
}

resource "aws_iam_policy" "quicksight_s3_access" {
  name        = "quicksight-s3-access"
  description = "Allows QuickSight to access S3 logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::goapigovernance-logs",
          "arn:aws:s3:::goapigovernance-logs/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_quicksight_s3" {
  policy_arn = aws_iam_policy.quicksight_s3_access.arn
  role       = aws_iam_role.terraform_ec2_role.name
}

resource "aws_quicksight_data_source" "goapigovernance_quicksight" {
  data_source_id = "goapigovernance-quicksight"
  name           = "goapigovernance-data-source"
  type           = "S3"

  parameters {
    s3 {
      manifest_file_location {
        bucket  = aws_s3_bucket.goapigovernance_logs.bucket
        key     = "manifest.json"
      }
    }
  }

  tags = {
    Name = "goapigovernance-quicksight"
    Project = "goapigovernance"
  }
}

resource "aws_s3_bucket" "goapigovernance_logs" {
  bucket = "goapigovernance-logs"

  tags = {
    Name = "goapigovernance-s3"
    Project = "goapigovernance"
  }
}

resource "aws_redshift_cluster" "goapigovernance_redshift" {
  cluster_identifier = "goapigovernance-redshift"
  node_type          = "dc2.large"
  number_of_nodes    = 2
  master_username    = "admin"
  master_password    = "SuperSecurePassword123"

  tags = {
    Name = "goapigovernance-redshift"
    Project = "goapigovernance"
  }
}
