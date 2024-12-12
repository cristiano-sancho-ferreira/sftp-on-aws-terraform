variable "user_admin_console" {}

variable "region" {}

variable "common_tags" {
  type = map(string)
  default = {
    "Name"    = "SFTP Server"
    "Projeto" = "SFTP Server Demo"
  }
}

######## Foundation ############
variable "application_name" {
  description = "Name of the application"
}

variable "organization_name" {
  description = "Name of the organization"
}

variable "environment" {
  description = "Environment name"
}

variable "sftp_users" {
  description = "Lista de usuários do servidor SFTP"
  type        = list(any)
}
