mission_control_auth_enabled = ENV.fetch("MISSION_CONTROL_JOBS_AUTH_ENABLED", "1") == "1"
mission_control_auth_user = ENV.fetch("MISSION_CONTROL_JOBS_BASIC_AUTH_USERNAME", "admin")
mission_control_auth_password = ENV.fetch(
  "MISSION_CONTROL_JOBS_BASIC_AUTH_PASSWORD",
  ENV.fetch("ADMIN_BOOTSTRAP_PASSWORD", "")
)

Rails.application.configure do
  config.mission_control.jobs.base_controller_class = "ApplicationController"
  config.mission_control.jobs.http_basic_auth_enabled = mission_control_auth_enabled
end

MissionControl::Jobs.base_controller_class = "ApplicationController"
MissionControl::Jobs.http_basic_auth_enabled = mission_control_auth_enabled

if mission_control_auth_enabled
  MissionControl::Jobs.http_basic_auth_user = mission_control_auth_user
  MissionControl::Jobs.http_basic_auth_password = mission_control_auth_password
else
  MissionControl::Jobs.http_basic_auth_user = nil
  MissionControl::Jobs.http_basic_auth_password = nil
end
