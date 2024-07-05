terraform {
  backend "gcs" {
    bucket = "gde-ihommani-tf-state"
    prefix = "terraform/"
  }
}