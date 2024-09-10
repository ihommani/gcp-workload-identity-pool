# Workload identity federation along with dedicated terraform sac for impersonoation by the gh action sac.
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

  workload_identity_pool_id = "github-${local.github_organization}"
  display_name              = "github-${local.github_organization}"
  description               = "Identity pool for my github organization"
  disabled                  = false
}

#TODO1: create the github repo along the way.
#TODO2: distinguish roles for terraform sac and gha sac
locals {
  terraform_sa_roles_by_repository_name = {
    "workflow-real-example" : [
      "roles/viewer",
    ],
  }
}

resource "google_iam_workload_identity_pool_provider" "provider" {

  for_each = toset(keys(local.terraform_sa_roles_by_repository_name))

  project = local.host_project

  workload_identity_pool_id = google_iam_workload_identity_pool.github_ihommani.workload_identity_pool_id

  workload_identity_pool_provider_id = "${each.value}-provider"
  display_name                       = "${each.value}-provider"
  description                        = "Provider dedicated for repository ${local.github_organization}/${each.value}"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.workflow"         = "assertion.workflow"

  }
  attribute_condition = "attribute.repository_owner == '${local.github_organization}' && attribute.repository == '${local.github_organization}/${each.value}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "gh_actions_service_accounts" {

  for_each = google_iam_workload_identity_pool_provider.provider

  project = local.host_project

  account_id   = "${each.key}-gh"
  display_name = "Service Account connected to the ${each.key}-provider from github-ihommani identity pool."
}

resource "google_service_account_iam_member" "member" {
  for_each = google_service_account.gh_actions_service_accounts

  service_account_id = each.value.name
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_ihommani.name}/attribute.repository/${local.github_organization}/${each.key}"
  role               = "roles/iam.workloadIdentityUser"
}

resource "google_service_account" "terraform_service_accounts" {

  for_each = toset(keys(local.terraform_sa_roles_by_repository_name))

  project = local.host_project

  account_id   = "${each.value}-tf"
  display_name = "Account dedicated to TF impersonation on ${local.github_organization}/${each.value} repository"
}

resource "google_service_account_iam_member" "gh_actions_impersonation_iam" {

  for_each = google_service_account.terraform_service_accounts

  service_account_id = each.value.id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.gh_actions_service_accounts[each.key].email}"
}

locals {
  role_sa_associations = chunklist(flatten([for repo, roles in local.terraform_sa_roles_by_repository_name : setproduct([repo], roles)]), 2)

  roles_by_tf_sa_association = {
    for role_sa_association in local.role_sa_associations :
    "${role_sa_association[0]}-${role_sa_association[1]}" => {
      sa_key : "${role_sa_association[0]}",
      role : "${role_sa_association[1]}",
    }
  }
}

resource "google_project_iam_member" "tf_sa_iam" {

  for_each = local.roles_by_tf_sa_association

  project = local.host_project

  role   = each.value["role"]
  member = "serviceAccount:${google_service_account.terraform_service_accounts[each.value["sa_key"]].email}"
}

output "pool_provider_ids" {
  description = ""
  value = values(google_iam_workload_identity_pool_provider.provider)[*].name
}