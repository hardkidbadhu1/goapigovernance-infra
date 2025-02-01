local BasePlugin = require "kong.plugins.base_plugin"
local MaintenanceToggle = BasePlugin:extend()

function MaintenanceToggle:new()
  MaintenanceToggle.super.new(self, "maintenance-toggle")
end

function MaintenanceToggle:access(conf)
  MaintenanceToggle.super.access(self)
  if conf.enabled then
    -- If the maintenance mode is enabled, return a 503 error
    return kong.response.exit(503, "Service is under maintenance")
  end
end

return MaintenanceToggle