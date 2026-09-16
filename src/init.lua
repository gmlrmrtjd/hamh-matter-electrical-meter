local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

-- Helper function to get valid target endpoints for the device
local function get_target_endpoints(device, cluster_id)
  local eps = {}
  if cluster_id and type(device.get_endpoints) == "function" then
    eps = device:get_endpoints(cluster_id) or {}
  end

  if #eps == 0 and device.matter_endpoints then
    for _, ep in ipairs(device.matter_endpoints) do
      table.insert(eps, ep)
    end
  end

  if #eps == 0 and device.endpoints then
    for ep_id, _ in pairs(device.endpoints) do
      if type(ep_id) == "number" and ep_id > 0 then
        table.insert(eps, ep_id)
      end
    end
  end

  return eps
end

-- Safely emit event to the main component exactly once with state_change guaranteed
local function emit_measurement_event(device, endpoint_id, event)
  if not event then return end

  -- Ensure provisioning state is PROVISIONED so cloud records all events
  if device.network_type ~= "CHILD" then
    pcall(function()
      device:try_update_metadata({ provisioning_state = "PROVISIONED" })
    end)
  end

  -- Determine component (fallback to main)
  local comp_id = "main"
  if endpoint_id and type(device.get_component_id_for_endpoint) == "function" then
    comp_id = device:get_component_id_for_endpoint(endpoint_id) or "main"
  end

  local component = (device.profile and device.profile.components and device.profile.components[comp_id])
    or (device.profile and device.profile.components and device.profile.components.main)

  if component then
    device:emit_component_event(component, event)
  else
    device:emit_event(event)
  end
end

-- Handler for ActivePower attribute report
local function active_power_handler(driver, device, ib, response)
  if ib.data and ib.data.value ~= nil then
    -- Matter ElectricalPowerMeasurement.ActivePower is in milliwatts.
    local raw_watts = ib.data.value / 1000.0

    -- 1. Apply multiplier calibration (default 1.0)
    local multiplier = 1.0
    if device.preferences and device.preferences.powerMultiplier ~= nil then
      multiplier = tonumber(device.preferences.powerMultiplier) or 1.0
    end
    local calibrated_watts = raw_watts * multiplier

    -- 2. Apply decimal places formatting (0 = integer, 1 = 1 decimal)
    local decimals = "1"
    if device.preferences and device.preferences.decimalPlaces ~= nil then
      decimals = tostring(device.preferences.decimalPlaces)
    end

    local final_watts
    if decimals == "0" then
      final_watts = math.floor(calibrated_watts + 0.5)
    else
      final_watts = math.floor(calibrated_watts * 10 + 0.5) / 10
    end

    -- 3. Check threshold filter
    local threshold = 1.0
    if device.preferences and device.preferences.powerThreshold ~= nil then
      threshold = tonumber(device.preferences.powerThreshold) or 0.0
    end

    local last_reported_watts = device:get_field("__last_reported_power")
    local should_emit = true

    if threshold > 0 and last_reported_watts ~= nil then
      local delta = math.abs(final_watts - last_reported_watts)
      if delta < threshold then
        should_emit = false
        log.debug(string.format("[HAMH] Power delta (%.2f W) < threshold (%.2f W). Skipping report.", delta, threshold))
      end
    end

    if should_emit then
      device:set_field("__last_reported_power", final_watts)
      log.info(string.format("[HAMH] ActivePower emitting: %s W (raw: %.2f W, mult: %.2f)", tostring(final_watts), raw_watts, multiplier))
      local event = capabilities.powerMeter.power({ value = final_watts, unit = "W" }, { state_change = true })
      emit_measurement_event(device, ib.endpoint_id, event)
    end
  end
end

-- Handler for Cumulative Energy attribute report
local function cumulative_energy_handler(driver, device, ib, response)
  local wh = nil
  if ib.data and ib.data.elements and ib.data.elements.energy ~= nil then
    -- Matter energy struct reports milliwatt-hours; SmartThings energyMeter uses Wh.
    wh = math.floor((ib.data.elements.energy.value / 1000.0) * 10 + 0.5) / 10
  elseif ib.data and ib.data.value ~= nil then
    wh = math.floor((ib.data.value / 1000.0) * 10 + 0.5) / 10
  end

  if wh ~= nil then
    log.info(string.format("[HAMH] CumulativeEnergy received: %.1f Wh (endpoint %s)", wh, tostring(ib.endpoint_id)))
    local event = capabilities.energyMeter.energy({ value = wh, unit = "Wh" }, { state_change = true })
    emit_measurement_event(device, ib.endpoint_id, event)
  end
end

-- Handler for Periodic Energy attribute report
local function periodic_energy_handler(driver, device, ib, response)
  if ib.data and ib.data.elements and ib.data.elements.energy ~= nil then
    local wh = math.floor((ib.data.elements.energy.value / 1000.0) * 10 + 0.5) / 10
    log.info(string.format("[HAMH] PeriodicEnergy received: %.1f Wh (endpoint %s)", wh, tostring(ib.endpoint_id)))
    local event = capabilities.energyMeter.energy({ value = wh, unit = "Wh" }, { state_change = true })
    emit_measurement_event(device, ib.endpoint_id, event)
  end
end

-- Read all measurements directly
local function read_measurements(device)
  local power_eps = get_target_endpoints(device, clusters.ElectricalPowerMeasurement and clusters.ElectricalPowerMeasurement.ID)
  for _, ep in ipairs(power_eps) do
    if clusters.ElectricalPowerMeasurement and clusters.ElectricalPowerMeasurement.attributes.ActivePower then
      device:send(clusters.ElectricalPowerMeasurement.attributes.ActivePower:read(device, ep))
    end
  end

  local energy_eps = get_target_endpoints(device, clusters.ElectricalEnergyMeasurement and clusters.ElectricalEnergyMeasurement.ID)
  for _, ep in ipairs(energy_eps) do
    if clusters.ElectricalEnergyMeasurement then
      if clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported then
        device:send(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(device, ep))
      end
    end
  end
end

-- Setup recurring poll timer based on user preference
local function setup_poll_timer(driver, device)
  local old_timer = device:get_field("__poll_timer")
  if old_timer then
    device.thread:cancel_timer(old_timer)
    device:set_field("__poll_timer", nil)
  end

  local interval = 15
  if device.preferences and device.preferences.pollInterval ~= nil then
    interval = tonumber(device.preferences.pollInterval) or 15
  end

  if interval <= 0 then
    log.info(string.format("[HAMH] Polling disabled (interval=0) for %s", device.label))
    return
  end

  log.info(string.format("[HAMH] Starting recurring poll timer (every %ds) for %s", interval, device.label))
  local timer = device.thread:call_on_schedule(interval, function()
    read_measurements(device)
  end)
  device:set_field("__poll_timer", timer)
end

-- Refresh capability handler
local function refresh_handler(driver, device, command)
  log.info(string.format("[HAMH] Refresh command triggered for device %s", device.label))
  if type(device.subscribe) == "function" then
    device:subscribe()
  end
  read_measurements(device)
end

-- Lifecycle Handlers
local function device_init(driver, device)
  log.info(string.format("[HAMH] Device init: %s (%s)", device.id, device.label))
  pcall(function()
    device:try_update_metadata({ provisioning_state = "PROVISIONED" })
  end)

  -- Subscribe to attributes
  if type(device.subscribe) == "function" then
    device:subscribe()
  end

  -- Initial read
  read_measurements(device)

  -- Setup poll timer based on preference
  setup_poll_timer(driver, device)
end

local function device_added(driver, device)
  log.info(string.format("[HAMH] Device added: %s (%s)", device.id, device.label))
  pcall(function()
    device:try_update_metadata({ provisioning_state = "PROVISIONED" })
  end)
  if type(device.subscribe) == "function" then
    device:subscribe()
  end
  read_measurements(device)
end

local function do_configure(driver, device)
  log.info(string.format("[HAMH] doConfigure: %s", device.label))
  pcall(function()
    device:try_update_metadata({ provisioning_state = "PROVISIONED" })
  end)
  if type(device.subscribe) == "function" then
    device:subscribe()
  end
  read_measurements(device)
end

local function driver_switched(driver, device)
  log.info(string.format("[HAMH] driverSwitched: %s", device.label))
  pcall(function()
    device:try_update_metadata({ provisioning_state = "PROVISIONED" })
  end)
  if type(device.subscribe) == "function" then
    device:subscribe()
  end
  read_measurements(device)
end

local function info_changed(driver, device, event, args)
  log.info(string.format("[HAMH] infoChanged: %s", device.label))
  if type(device.subscribe) == "function" then
    device:subscribe()
  end

  -- Reconfigure poll timer if preference changed
  if args.old_st_store and args.old_st_store.preferences then
    local old_interval = args.old_st_store.preferences.pollInterval
    local new_interval = device.preferences and device.preferences.pollInterval
    if old_interval ~= new_interval then
      log.info(string.format("[HAMH] pollInterval preference changed: %s -> %s", tostring(old_interval), tostring(new_interval)))
      setup_poll_timer(driver, device)
    end
  else
    setup_poll_timer(driver, device)
  end

  read_measurements(device)
end

local driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    driverSwitched = driver_switched,
    infoChanged = info_changed,
  },

  matter_handlers = {
    attr = {
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = active_power_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = cumulative_energy_handler,
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = periodic_energy_handler,
      },
    },
  },

  subscribed_attributes = {
    [capabilities.powerMeter.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    },
    [capabilities.energyMeter.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    },
  },

  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    },
  },

  supported_capabilities = {
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.refresh,
  },
}

local driver = MatterDriver("hamh-matter-electrical-meter", driver_template)
driver:run()
