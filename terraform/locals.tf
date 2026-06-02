# Single source of truth: config/platforms.json (also read by the shell scripts).
locals {
  platforms_config = jsondecode(file("${path.module}/../config/platforms.json"))
  catalog          = local.platforms_config.catalog
  selected         = local.platforms_config.selected

  # Node pools derived from the 2 selected platforms. The `if contains(...)`
  # filter keeps an unknown key from throwing a raw "Invalid index" here, so the
  # platform_guard precondition below surfaces the friendly error instead.
  pools = {
    for key in local.selected : key => {
      machine_type = local.catalog[key].machine_type
      proc_label   = key
      disk_type    = local.catalog[key].disk_type
    } if contains(keys(local.catalog), key)
  }

  selected_valid = (
    length(local.selected) == 2 &&
    length(distinct(local.selected)) == 2 &&
    alltrue([for k in local.selected : contains(keys(local.catalog), k)])
  )
}

# Hard-fail `terraform plan`/`apply` if the selection is invalid (the user's
# requirement: any value other than exactly 2 distinct catalog keys must fail).
resource "terraform_data" "platform_guard" {
  lifecycle {
    precondition {
      condition     = local.selected_valid
      error_message = "config/platforms.json: 'selected' must list EXACTLY 2 distinct keys from 'catalog'. Got selected=${jsonencode(local.selected)}; valid catalog keys=${jsonencode(keys(local.catalog))}."
    }
  }
}
