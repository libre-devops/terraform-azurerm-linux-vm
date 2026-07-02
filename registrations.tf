# The often-forgotten subscription plumbing, opt-in and conditional. Both are SUBSCRIPTION-WIDE and
# owned by whoever manages them first: only enable these when this module call is the deliberate
# owner, and never register the same namespace or feature from two places.

variable "resource_provider_registrations" {
  description = <<DESC
Resource provider namespaces to register on the subscription (for example Microsoft.Monitor), for
subscriptions where the provider has never been used. Empty (the default) manages nothing. NOTE: a
namespace already registered elsewhere will conflict on import/destroy; this is for the deliberate
owner only, and the provider's own resource_provider_registrations setting must not also manage it.
DESC

  type    = set(string)
  default = []
}

variable "resource_provider_feature_registrations" {
  description = <<DESC
Preview/opt-in features to register, as "Namespace/FeatureName" strings (for example
"Microsoft.Compute/EncryptionAtHost", the classic forgotten prerequisite for
encryption_at_host_enabled). Empty (the default) manages nothing. Registration is subscription-wide
and can take several minutes to propagate.
DESC

  type    = set(string)
  default = []

  validation {
    condition     = alltrue([for f in var.resource_provider_feature_registrations : length(split("/", f)) == 2])
    error_message = "Each feature registration must be \"Namespace/FeatureName\", for example \"Microsoft.Compute/EncryptionAtHost\"."
  }
}

resource "azurerm_resource_provider_registration" "this" {
  for_each = var.resource_provider_registrations

  name = each.value
}

resource "azurerm_resource_provider_feature_registration" "this" {
  for_each = var.resource_provider_feature_registrations

  provider_name = split("/", each.value)[0]
  name          = split("/", each.value)[1]
}

# encryption_at_host without its feature registration is the classic silent 400: remind when the
# module sees the flag but is not registering the feature (it may of course be registered elsewhere).
check "encryption_at_host_feature_reminder" {
  assert {
    condition = !(
      anytrue([for v in values(var.linux_virtual_machines) : coalesce(v.encryption_at_host_enabled, false)]) &&
      !contains(var.resource_provider_feature_registrations, "Microsoft.Compute/EncryptionAtHost")
    )
    error_message = "encryption_at_host_enabled is set but this call does not register Microsoft.Compute/EncryptionAtHost; the apply fails unless the feature is already registered on the subscription (add it to resource_provider_feature_registrations, or register it once elsewhere)."
  }
}
