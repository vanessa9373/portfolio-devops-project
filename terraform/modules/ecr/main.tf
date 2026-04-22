# ─────────────────────────────────────────────────────────────────────────────
# ECR MODULE — One repository per microservice
# ─────────────────────────────────────────────────────────────────────────────

locals {
  services = [
    "frontend",
    "cartservice",
    "checkoutservice",
    "paymentservice",
    "productcatalogservice",
    "currencyservice",
    "emailservice",
    "shippingservice",
    "recommendationservice",
    "adservice",
    "loadgenerator"
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = each.value
    Service = each.value
  }
}

# Lifecycle policy: keep last 10 tagged images, delete untagged after 1 day
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "repository_urls" {
  value = {
    for name, repo in aws_ecr_repository.services :
    name => repo.repository_url
  }
}
