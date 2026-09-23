locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # AWS Config delivery minimum is 24 hours, so this is fixed rather than driven
  # by var.config_snapshot_frequency — the variable documents intent (daily /
  # weekly / biweekly) while the channel always delivers at the AWS floor. This
  # mirrors the standalone root exactly; passing the intent value straight
  # through would send "biweekly" to an API that only accepts its own enum.
  #
  # Cost tracks change frequency, not this setting: rule evaluations are
  # change-triggered, so fewer deploys means fewer evaluations.
  delivery_frequency = "TwentyFour_Hours"
}
