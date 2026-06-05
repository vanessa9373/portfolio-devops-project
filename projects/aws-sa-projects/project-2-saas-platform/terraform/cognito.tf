# ── Cognito User Pool ─────────────────────────────────────────────────────────
# One pool for all tenants (pool model). Enterprise tenants get SAML federation.

resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = var.cognito_mfa_configuration

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Custom attributes for multi-tenancy
  schema {
    attribute_data_type      = "String"
    name                     = "tenant_id"
    required                 = false
    mutable                  = false
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 128
    }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "plan"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 32
    }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "role"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 32
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-user-pool"
  })
}

# ── Cognito User Pool Client ──────────────────────────────────────────────────

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"

  read_attributes = [
    "email",
    "custom:tenant_id",
    "custom:plan",
    "custom:role",
  ]

  write_attributes = [
    "email",
    "custom:plan",
  ]
}

# M2M client for server-side Lambda calls (uses client_credentials flow)
resource "aws_cognito_user_pool_client" "server" {
  name         = "${local.name_prefix}-server-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["formflow/read", "formflow/write"]
}

# ── Cognito User Pool Domain ──────────────────────────────────────────────────

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.name_prefix}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ── Cognito Resource Server (custom OAuth scopes) ─────────────────────────────

resource "aws_cognito_resource_server" "api" {
  identifier   = "formflow"
  name         = "FormFlow API"
  user_pool_id = aws_cognito_user_pool.main.id

  scope {
    scope_name        = "read"
    scope_description = "Read access to FormFlow API"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access to FormFlow API"
  }

  scope {
    scope_name        = "admin"
    scope_description = "Admin access — tenant management only"
  }
}

# ── Cognito Identity Pool (for S3 pre-signed URL generation) ──────────────────

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.name_prefix}-identity-pool"
  allow_unauthenticated_identities = false
  allow_classic_flow               = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = true
  }

  tags = var.tags
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    authenticated   = aws_iam_role.cognito_authenticated.arn
    unauthenticated = aws_iam_role.cognito_unauthenticated.arn
  }
}

resource "aws_iam_role" "cognito_authenticated" {
  name = "${local.name_prefix}-cognito-auth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cognito_authenticated_s3" {
  name = "${local.name_prefix}-cognito-s3-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::${local.name_prefix}-uploads/tenants/$${cognito-identity.amazonaws.com:sub}/*"
    }]
  })
}

resource "aws_iam_role" "cognito_unauthenticated" {
  name = "${local.name_prefix}-cognito-unauth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action = "sts:AssumeRoleWithWebIdentity"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cognito_unauthenticated" {
  name = "${local.name_prefix}-cognito-unauth-policy"
  role = aws_iam_role.cognito_unauthenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })
}
