terraform {
  required_version = ">= 1.0"

  # State on RustFS, shared by make configure-minio and the Deploy workflow.
  # configure_minio.yml passes the bucket (-backend-config) and the endpoint
  # and credentials (AWS_ENDPOINT_URL_S3, AWS_ACCESS_KEY_ID, ...).
  backend "s3" {
    key                         = "minio/terraform.tfstate"
    region                      = "eu-west-1"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "3.43.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
  }
}

provider "minio" {
  minio_server   = var.minio_endpoint
  minio_region   = var.minio_region
  minio_user     = var.minio_admin_user
  minio_password = var.minio_admin_password
  minio_ssl      = var.minio_use_ssl
  minio_insecure = var.minio_insecure
  minio_debug    = true
}

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = var.vault_skip_tls_verify
}
