# ── Rider User Pool ───────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "riders" {
  name                     = "${local.name_prefix}-riders"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  schema {
    attribute_data_type      = "String"
    name                     = "rider_id"
    required                 = false
    mutable                  = false
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 128 }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "default_payment_method"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 0; max_length = 128 }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-riders-pool" })
}

resource "aws_cognito_user_pool_client" "riders" {
  name         = "${local.name_prefix}-riders-client"
  user_pool_id = aws_cognito_user_pool.riders.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
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
}

# ── Driver User Pool ──────────────────────────────────────────────────────────
# Separate pool: drivers have additional attributes and a stricter verification flow

resource "aws_cognito_user_pool" "drivers" {
  name                     = "${local.name_prefix}-drivers"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    attribute_data_type      = "String"
    name                     = "driver_id"
    required                 = false
    mutable                  = false
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 128 }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "vehicle_type"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 32 }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "license_plate"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 16 }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "background_check_status"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 32 }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-drivers-pool" })
}

resource "aws_cognito_user_pool_client" "drivers" {
  name         = "${local.name_prefix}-drivers-client"
  user_pool_id = aws_cognito_user_pool.drivers.id

  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 8
  id_token_validity      = 8
  refresh_token_validity = 7

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}
