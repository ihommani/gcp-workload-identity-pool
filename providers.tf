provider "google" {
  default_labels = local.default_labels
}

provider "google-beta" {
  default_labels = local.default_labels
}
