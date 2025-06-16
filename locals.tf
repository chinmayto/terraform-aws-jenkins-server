locals {
  common_tags = {
    environment = var.environment
  }

  naming_prefix = "${var.naming_prefix}-${var.environment}"
}

