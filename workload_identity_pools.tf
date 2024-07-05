# Workload identity federation.
#
#
#
# More info:
# 

locals {
  services_to_activate = [
    "iam.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
  ]
}

resource "google_project_service" "project" {

  for_each = toset(local.services_to_activate)

  project = local.host_project

  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github_ihommani" {

  project = local.host_project

  workload_identity_pool_id = "github-ihommani"
  display_name              = "github-ihommani"
  description               = "Identity pool for my github organization"
  disabled                  = true
}

locals {
  github_repositories = [
    "workflow-real-example",
  ]
}

resource "google_iam_workload_identity_pool_provider" "provider" {

  for_each = toset(local.github_repositories)

  project = local.host_project

  workload_identity_pool_id = google_iam_workload_identity_pool.github_ihommani.workload_identity_pool_id

  workload_identity_pool_provider_id = "${each.value}-provider"
  display_name                       = "${each.value}-provider"
  description                        = "Provider dedicated for repository ihommani/${each.value}"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.workflow"         = "assertion.workflow"

  }
  attribute_condition = "attribute.repository_owner == 'ihommani' && attribute.repository == '${each.value}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "service_accounts" {

  for_each = google_iam_workload_identity_pool_provider.provider

  project = local.host_project

  account_id   = "${each.key}-gh"
  display_name = "Service Account connected to the ${each.key}-provider from github-ihommani identity pool."
}

resource "google_service_account_iam_member" "member" {
  for_each = google_service_account.service_accounts

  service_account_id = each.value.name
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_ihommani.name}/attribute.repository/ihommani/${each.key}"
  role               = "roles/iam.workloadIdentityUser"
}
