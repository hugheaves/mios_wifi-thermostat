-- MiOS Plugin for Radio Thermostat Corporation of America, Inc. Wi-Fi Thermostats
--
-- Copyright (C) 2012  Hugh Eaves
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.


-- IMPORT GLOBALS
local luup = luup
local string = string
local require = require
local math = math
local json = g_dkjson
local log = g_log
local util = g_util

-- IMPORT REQUIRED MODULES
local http = require("socket.http")

-- CONSTANTS

-- Plug-in version
local PLUGIN_VERSION = "2.2"

-- assign a few from util module to reduce verbosity

local T_NUMBER = util.T_NUMBER
local T_BOOLEAN = util.T_BOOLEAN
local T_STRING = util.T_STRING

local DEFAULT_POLL_INTERVAL = 60

local DEFAULT_NUM_RETRIES = 10

local LOG_PREFIX = "RTCOA"

local DEFAULT_VERA_CONFIG_URL = "http://localhost:3480/data_request?id=lu_sdata"

local LOG_FILTER = {
["L_RTCOA_Wifi_core.lua$"] = {
		"isValidAPIParameterValue",
		"cleanupVariable"
	},
["L_RTCOA_Wifi_util.lua$"] = {
		"g_logFunc"
	}
}

-----------------------------------------------
----- Define some LUUP constants --------------
-----------------------------------------------
local JOB_RETURN_FAILURE = 2
local JOB_RETURN_SUCCESS = 4

------------------------------------------------------------------
----- Define SIDs used by the various thermostat services -------
------------------------------------------------------------------
local TEMP_SENSOR_SID = "urn:upnp-org:serviceId:TemperatureSensor1"
local HEAT_SETPOINT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat"
local COOL_SETPOINT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool"
local FAN_MODE_SID = "urn:upnp-org:serviceId:HVAC_FanOperatingMode1"
local USER_OPERATING_MODE_SID = "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local MCV_HA_DEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local MCV_OPERATING_STATE_SID = "urn:micasaverde-com:serviceId:HVAC_OperatingState1"
local POWER_SID = "urn:upnp-org:serviceId:SwitchPower1" -- not sure what this one is for
local MCV_ENERGY_METERING_SID = "urn:micasaverde-com:serviceId:EnergyMetering1"

-- I added these to support RTCOA specific features
local TEMPERATURE_HOLD_SID = "urn:hugheaves-com:serviceId:HVAC_RTCOA_TemperatureHold1"
local RTCOA_WIFI_SID = "urn:hugheaves-com:serviceId:HVAC_RTCOA_Wifi1"

-- SIDs to sync between the main and generic thermostat devices
local GENERIC_DEVICE_SIDS = {
	[TEMP_SENSOR_SID] = true,
	[HEAT_SETPOINT_SID] = true,
	[COOL_SETPOINT_SID] = true,
	[FAN_MODE_SID] = true,
	[USER_OPERATING_MODE_SID] = true,
	[MCV_OPERATING_STATE_SID] = true
}


-- "Global" variables (global to the module, that is)
local g_lastMetadataPollTime = nil
local g_lastRemoteTempPollTime = nil
local g_nextPollTime = 0
local g_temperatureFormat = nil

-- id for the main thermostat device
local g_deviceId = nil
-- id for the generic thermostat device
local g_genericDeviceId = nil

local g_ipAddress = nil
local g_programs = nil
local g_thermostatTime = nil
local g_configUrl = DEFAULT_VERA_CONFIG_URL

--------------------------------------------------------------------
------- Various definitions to support the RTCOA Wifi API ----------
--------------------------------------------------------------------

-- URL path's used to access various thermostat resources

local TSTAT_API_THERMOSTAT_PATH = "/tstat"
-- Example GET response: {"temp":71.00,"tmode":1,"fmode":0,"override":0,"hold":1,"t_heat":70.00,"tstate":0,"fstate":0,"time":{"day":3,"hour":16,"minute":49},"t_type_post":0}

local TSTAT_API_MODEL_PATH = "/tstat/model"
-- Example GET resonse: {"model":"CT50 V1.09"}

local TSTAT_API_TTEMP_PATH = "/tstat/ttemp"
-- Example GET resonse: {"t_heat":52.00,"t_cool":78.00}

local TSTAT_API_SYSTEM_PATH = "/sys"
-- Example GET response: {"uuid":"ffffffffffff","api_version":113,"fw_version":"1.04.73","wlan_fw_version":"v10.105576"

local TSTAT_API_SYSTEM_NAME_PATH = "/sys/name"
-- Example GET response: {"name":"Dining Room"}

local TSTAT_API_HOLD_PATH = "/tstat/hold"
-- Example GET response: {"hold":0}

local TSTAT_API_PMA_PATH = "/tstat/pma"
-- Example PUT data: {"line":0,"message":"234.23",mode:2}

local TSTAT_API_UMA_PATH = "/tstat/uma"
-- Example PUT data: {"line":0,"message":"The Sky Is Falling"}

local TSTAT_API_LED_PATH = "/tstat/led"
-- Example PUT data: {"energy_led":2}

local TSTAT_API_REMOTE_TEMP_PATH = "/tstat/remote_temp"
-- Example PUT data: {"rem_mode":1,"rem_temp":64.00}

local TSTAT_API_TIME_PATH = "/tstat/time"
-- Example PUT data: {"rem_mode":1,"rem_temp":64.00}

local TSTAT_API_PROGRAM_PATH = "/tstat/program"
-- Example GET data:

-- Table definitions to map between RTCOA API values and UPnP state variable values

-- SID: urn:upnp-org:serviceId:HVAC_UserOperatingMode1
-- VARIABLE: ModeTarget
local TSTAT_API_TMODE = {
[0] = "Off",
[1] = "HeatOn",
[2] = "CoolOn",
[3] = "AutoChangeOver"
}

-- SID: urn:upnp-org:serviceId:HVAC_UserOperatingMode1
-- VARIABLE: ModeStatus
local TSTAT_API_TSTATE = {
[0] = "Idle",
[1] = "Heating",
[2] = "Cooling"
}

-- SID: urn:upnp-org:serviceId:HVAC_FanOperatingMode1
-- VARIABLE: Mode
local TSTAT_API_FMODE = {
[0] = "Auto",
[1] = "PeriodicOn",
[2] = "ContinuousOn"
}

-- urn:upnp-org:serviceId:HVAC_FanOperatingMode1
-- VARIABLE: FanStatus
local TSTAT_API_FSTATE = {
[0] = "Off",
[1] = "On"
}

-- set a luup variable in both thermostat devices
local function setLuupVariable(sid, variableName, value, deviceId)
	luup.variable_set(sid, variableName, value, deviceId)
	if (g_genericDeviceId and deviceId == g_deviceId and GENERIC_DEVICE_SIDS[sid]) then
		luup.variable_set(sid, variableName, value, g_genericDeviceId)
	elseif (deviceId == g_genericDeviceId) then
		luup.variable_set(sid, variableName, value, g_deviceId)
	end
end

------------------------------------------------------
-------- HTTP / JSON communcation functions ----------
------------------------------------------------------

--- Send a request to to a URL with optional requestParameters that will be JSON encoded.
-- Expects a JSON formatted response that will be decoded into a Lua table
-- @return response - a table of the decoded JSON response, or nil if failed
local function doHttpRequest(url, requestParameters)
	local postData = nil
	local response = nil

	if (requestParameters ~= nil) then
		log.debug ("requestParameters = " , requestParameters)
		postData = json.encode (requestParameters)
	end

	log.debug("Making HTTP request: ", "url = ",url, ", postData = ",postData)
	local body, status, headers = http.request(url, postData)

	if (body == nil or status == nil or headers == nil or status ~= 200) then
		log.error ("Received bad HTTP response")
		log.error ("URL: " ,url)
		log.error ("postData: ",postData)
		log.error ("Status: ",status)
		log.error ("Body: " ,body)
		log.error ("Headers: ",headers)
	else
		log.debug ("Received good HTTP response")
		log.debug ("URL: " ,url)
		log.debug ("postData: ",postData)
		log.debug ("Status: ",status)
		log.debug ("Body: " ,body)
		log.debug ("Headers: ",headers)
		response = json.decode(body)
		log.debug ("Parsed response: ",response)
	end

	return response
end

-------------------------------------------
------- Wifi Thermostat API functions ------
-------------------------------------------

--- convert temp from thermostat format (F) to local format (C or F depending on config)
-- rounds to nearest 0.1C on conversion to celcius
local function localizeTemp(temperature)
	if (g_temperatureFormat == "F") then
		return temperature
	else
		return util.round(((temperature + 0.0) - 32) * 5 / 9, 1)
	end
end

--- convert temp from local format (C or F depending on config) to thermostat format (F)
-- rounds to nearest 0.5 degree F on conversion from celcius
local function delocalizeTemp(temperature)
	if (g_temperatureFormat == "F") then
		return temperature + 0
	else
		return util.round(((temperature + 0.0) * 9 / 5) + 32, 2)
	end
end

--- Call the thermostat API using the given path and request parameters.
-- Will retry communications upon failure, unless noRetry is set to true.
-- @parameter path
-- @parameter responseValidationFunction - function to check for valid response to this API call
-- @parameter requestParameters
-- @parameter noRetry
-- @return response - the JSON response decoded into a Lua table, or nil if failed
local function callThermostatAPI(path, responseValidationFunction, requestParameters, noRetry)
	log.info("Calling thermostat API, path = ",path,", requestParameters = ",requestParameters,", noRetry = ", noRetry)
	local retries = 0
	local numRetries = DEFAULT_NUM_RETRIES

	if (noRetry) then
		numRetries = 0
	end

	repeat
		-- if this is a retry, then we wait a little
		luup.sleep(retries * 500)
		if (retries > 0) then
			log.info("retrying request, path = ", path, ", retry #", retries)
		end

		local response = doHttpRequest ("http://" .. g_ipAddress .. path, requestParameters)
		if (not response) then
			log.error ("Received no response (timeout?), path = ", path)
		elseif (responseValidationFunction(response)) then
			log.info ("Received succesful response, path = ", path, ", response = ", response)
			return (response)
		else
			log.error ("Received invalid response, path = ", path, ", response = ", response)
		end

		retries = retries + 1
	until (retries > numRetries)

	return (nil)
end

--- Check if we got a value that looks "normal" for the thermostat API
-- @return true if the parameter value is in the valid range for the thermostat API
local function isValidAPIParameterValue(value)
	if (value == nil or value == "") then
		return false
	end
	if (type(value) == "numeric" and value < 0) then
		return false
	end
	return true
end

--- Check for valid response to a status inquiry
local function isValidStatusResponse(response)
	log.debug ("validating status response")
	local error = false

	if (response ~= nil) then
		if (not isValidAPIParameterValue(response.temp)) then
			log.error ("Invalid temp")
			error = true
		end

		if (isValidAPIParameterValue(response.tmode)) then
			if (response.tmode == 1) then -- Heating, so check if we have a valid heat setpoint
				if (not isValidAPIParameterValue(response.t_heat)) then
					log.error ("Invalid t_heat")
					error = true
				end
			elseif (response.tmode == 2) then -- Cooling, so check if we have a valid cool setpoint
				if (not isValidAPIParameterValue(response.t_cool)) then
					log.error ("Invalid t_cool")
					error = true
				end
			end
		else
			log.error ("Invalid tmode")
			error = true
		end

		if (not isValidAPIParameterValue(response.tstate)) then
			log.error ("Invalid tstate")
			error = true
		end

		if (not isValidAPIParameterValue(response.fmode)) then
			log.error ("Invalid fmode")
			error = true
		end

		if (not isValidAPIParameterValue(response.fstate)) then
			log.error ("Invalid fstate")
			error = true
		end
	else
		error = true
	end

	log.debug ("done validating status response, error = ", error)

	return (not error)
end

--- validate the response to a TTemp request
local function isValidTTempResponse(response)
	return (isValidAPIParameterValue(response.t_cool) and isValidAPIParameterValue(response.t_heat) )
end

--- validate the response to an update request
local function isValidUpdateResponse(response)
	return (isValidAPIParameterValue(response.success) and response.success == 0)
end

--- validate the reponse to a sys information request
local function isValidSysResponse(response)
	local error = false

	if (response ~= nil) then
		if (not isValidAPIParameterValue(response.uuid)) then
			error = true
		end

		if (not isValidAPIParameterValue(response.api_version)) then
			error = true
		end

		if (not isValidAPIParameterValue(response.fw_version)) then
			error = true
		end

		if (not isValidAPIParameterValue(response.wlan_fw_version)) then
			error = true
		end
	else
		error = true
	end

	return (not error)
end

--- validate the response to a thermostat name  request
local function isValidNameResponse(response)
	return (isValidAPIParameterValue(response.name))
end

--- validate the response to a thermostat name  request
local function isValidHoldResponse(response)
	return (isValidAPIParameterValue(response.hold))
end

-- validate the response to a model information request
local function isValidModelResponse(response)
	return (isValidAPIParameterValue(response.model))
end

local function initSettings(mode)
	if (not mode) then
		mode = util.getLuupVariable(USER_OPERATING_MODE_SID, "ModeStatus", g_deviceId, T_STRING)
	end
	local settings = {}

	settings.hold = util.getLuupVariable(TEMPERATURE_HOLD_SID, "Status", g_deviceId, T_NUMBER)
	settings.tmode = util.findKeyByValue(TSTAT_API_TMODE, mode)

	if (not util.getLuupVariable(RTCOA_WIFI_SID, "LooseTempControl", g_deviceId, T_BOOLEAN)) then
		if (mode == "HeatOn") then
			settings.t_heat = delocalizeTemp(util.getLuupVariable(HEAT_SETPOINT_SID, "CurrentSetpoint", g_deviceId, T_NUMBER))
		elseif (mode == "CoolOn") then
			settings.t_cool = delocalizeTemp(util.getLuupVariable(COOL_SETPOINT_SID, "CurrentSetpoint", g_deviceId, T_NUMBER))
		end
	end
	
	return settings
end

--- Retrieve the current status from the thermostat, and store in the appropriate luup variabes.
-- @return true upon success, false upon failure
local function retrieveThermostatStatus()

	local response = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidStatusResponse)

	if (response == nil) then
		return false
	end

	g_thermostatTime = response.time

	setLuupVariable(TEMP_SENSOR_SID, "CurrentTemperature",  localizeTemp(response.temp), g_deviceId)

	-- The MCV thermostat standard uses "ModeStatus" to be current operating mode of the thermostat,
	-- instead of the mode that was set by the user. This seems different than what the
	-- UPnP spec intended, but I'm implementing it that way for compatibility with other MCV
	-- defined thermostats.
	setLuupVariable(USER_OPERATING_MODE_SID, "ModeStatus", TSTAT_API_TMODE[response.tmode], g_deviceId)

	-- Set MCV's "ModeState" variable to represent the current operating state. I think
	-- this should really have been set in "ModeStatus", but what can you do? :)
	setLuupVariable(MCV_OPERATING_STATE_SID, "ModeState", TSTAT_API_TSTATE[response.tstate], g_deviceId)
	setLuupVariable(FAN_MODE_SID, "Mode", TSTAT_API_FMODE[response.fmode], g_deviceId)
	setLuupVariable(FAN_MODE_SID, "FanStatus", TSTAT_API_FSTATE[response.fstate], g_deviceId)

	-- only update hold mode and temperature from the thermostat if we're not in the "Off" state
	if (TSTAT_API_TMODE[response.tmode] ~= "Off") then
		setLuupVariable(TEMPERATURE_HOLD_SID, "Status", response.hold, g_deviceId)

		if (TSTAT_API_TMODE[response.tmode] == "HeatOn") then
			setLuupVariable(HEAT_SETPOINT_SID, "CurrentSetpoint", localizeTemp(response.t_heat), g_deviceId)
		elseif (TSTAT_API_TMODE[response.tmode] == "CoolOn") then
			setLuupVariable(COOL_SETPOINT_SID, "CurrentSetpoint", localizeTemp(response.t_cool), g_deviceId)
		end
	end

	setLuupVariable(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)

	return true
end

--- Update a core thermostat setting, and set UPnP status variables to match
-- @parameter lul_settings
-- @parameter serviceId
-- @parameter action
-- @return true upon success, false upon failure
local function updateThermostatSetting(lul_settings, serviceId, action)
	log.info ("serviceId = " , serviceId, ", action = " , action)

	-- variable to hold new settings in thermostat API format
	local settings = nil
	local success = false

	if (serviceId == USER_OPERATING_MODE_SID and action == "SetModeTarget") then
		setLuupVariable(serviceId, "ModeTarget", lul_settings.NewModeTarget, g_deviceId)
		settings = initSettings(lul_settings.NewModeTarget)
		success = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidUpdateResponse, settings)
		if (success) then
			setLuupVariable(serviceId, "ModeStatus", lul_settings.NewModeTarget, g_deviceId)
		end
	elseif (serviceId == FAN_MODE_SID and action == "SetMode") then
		setLuupVariable(serviceId, "Mode", lul_settings.NewMode, g_deviceId)
		settings = initSettings()
		settings.fmode = util.findKeyByValue(TSTAT_API_FMODE, lul_settings.NewMode)
		success = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidUpdateResponse, settings)
	elseif (serviceId == HEAT_SETPOINT_SID and action == "SetCurrentSetpoint") then
		setLuupVariable(serviceId, "CurrentSetpoint", lul_settings.NewCurrentSetpoint, g_deviceId)
		if (util.getLuupVariable(USER_OPERATING_MODE_SID, "ModeStatus", g_deviceId, T_STRING) == "HeatOn") then
			settings = initSettings()
			settings.t_heat = delocalizeTemp(lul_settings.NewCurrentSetpoint)
			success = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidUpdateResponse, settings)
		end
	elseif (serviceId == COOL_SETPOINT_SID and action == "SetCurrentSetpoint") then
		setLuupVariable(serviceId, "CurrentSetpoint", lul_settings.NewCurrentSetpoint, g_deviceId)
		if (util.getLuupVariable(USER_OPERATING_MODE_SID, "ModeStatus", g_deviceId, T_STRING) == "CoolOn") then
			settings = initSettings()
			settings.t_cool = delocalizeTemp(lul_settings.NewCurrentSetpoint)
			success = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidUpdateResponse, settings)
		end
	elseif (serviceId == TEMPERATURE_HOLD_SID and action == "SetTarget") then
		setLuupVariable(serviceId, "Target", lul_settings.newTargetValue, g_deviceId)
		settings = initSettings()
		settings.hold = lul_settings.newTargetValue + 0
		success = callThermostatAPI(TSTAT_API_THERMOSTAT_PATH, isValidUpdateResponse, settings)
		if (success) then
			setLuupVariable(serviceId, "Status", lul_settings.newTargetValue, g_deviceId)
		end
	end

	if (success) then
		log.debug("succesfully updated thermostat")
	end

	setLuupVariable(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)

	return success
end

--- retrieve thermostat information (firmware revision, etc.)
-- @return true upon success, false upon failure
local function retrieveThermostatMetadata()
	local response = callThermostatAPI(TSTAT_API_MODEL_PATH, isValidModelResponse, requestParameters)

	if (response ~= nil) then
		luup.attr_set("model", response.model, g_deviceId)
	else
		return false
	end

	response = callThermostatAPI(TSTAT_API_SYSTEM_PATH, isValidSysResponse, requestParameters)
	if (response ~= nil) then
		setLuupVariable(RTCOA_WIFI_SID, "ThermostatUUID", response.uuid, g_deviceId)
		setLuupVariable(RTCOA_WIFI_SID, "APIVersion", response.api_version, g_deviceId)
		setLuupVariable(RTCOA_WIFI_SID, "FirmwareVersion", response.fw_version, g_deviceId)
		setLuupVariable(RTCOA_WIFI_SID, "WLANFirmwareVersion", response.wlan_fw_version, g_deviceId)
	else
		return false
	end

	response = callThermostatAPI(TSTAT_API_SYSTEM_NAME_PATH, isValidNameResponse, requestParameters)
	if (response ~= nil) then
		setLuupVariable(RTCOA_WIFI_SID, "ThermostatName", response.name, g_deviceId)
	else
		return false
	end

	setLuupVariable(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)

	return true
end

--- This is the function thats called by the "set energy mode" UPnP API call. The thermostat itself
-- doesn't provide a way to alter the energy mode via the API, so all we do here is set the
-- state variable.
local function setEnergyMode (lul_settings)
	setLuupVariable(USER_OPERATING_MODE_SID, "EnergyModeTarget", lul_settings.NewModeTarget, g_deviceId)
	setLuupVariable(USER_OPERATING_MODE_SID, "EnergyModeStatus", lul_settings.NewModeTarget, g_deviceId)
	setLuupVariable(MCV_HA_DEVICE_SID, "LastUpdate", os.time(), g_deviceId)
	return true
end

--- Send the current energy LED setting to thermostat, but only if
-- "EnergyLEDSet" is true
local function updateEnergyLED ()
	-- If "EnergyLEDSet" is true, set the LED color
	if (util.getLuupVariable(RTCOA_WIFI_SID, "EnergyLEDSet", g_deviceId, T_BOOLEAN)) then

		local color = util.getLuupVariable(RTCOA_WIFI_SID, "EnergyLEDColor", g_deviceId, T_STRING)
		local value = 0
		if (color == "Green") then
			value = 1
		elseif (color == "Yellow") then
			value = 2
		elseif (color == "Red") then
			value = 4
		end

		-- send the new LED setting to the thermostat
		return (callThermostatAPI(TSTAT_API_LED_PATH, isValidUpdateResponse, { ["energy_led"] = value } ) ~= nil)
	end
end

--- Set the energy LED variable to a new value and send the new value to the thermostat
local function setEnergyLED (lul_settings)
	setLuupVariable(RTCOA_WIFI_SID, "EnergyLEDColor", lul_settings.NewState, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "EnergyLEDSet", 1, g_deviceId)

	return updateEnergyLED()
end

--- Set the energy LED variable to off, send to the thermostat, and then
--  turn off the "EnergyLEDSet" variable so the plugin no longer
-- tries to update the LED on the thermostat until a new value is set.
local function resetEnergyLED ()
	setLuupVariable(RTCOA_WIFI_SID, "EnergyLEDColor", "Off", g_deviceId)
	if (updateEnergyLED()) then
		setLuupVariable(RTCOA_WIFI_SID, "EnergyLEDSet", 0, g_deviceId)
		return true
	else
		return false
	end
end

--- Sends the current state held in the PMA variables to hte thermostat, but only
-- if "PMASet" is true
local function updatePMA ()
	local params = {}
	if (util.getLuupVariable(RTCOA_WIFI_SID, "PMASet", g_deviceId, T_BOOLEAN)) then
		params.message = util.getLuupVariable(RTCOA_WIFI_SID, "PMAMessage", g_deviceId, T_STRING)
		params.line = util.getLuupVariable(RTCOA_WIFI_SID, "PMALine", g_deviceId, T_NUMBER)
	else
		params.mode = 0
	end

	return (callThermostatAPI(TSTAT_API_PMA_PATH, isValidUpdateResponse, params) ~= nil)
end

--- Set the PMA variables to represent the new PMA message and update the
-- thermostat with the new state
local function setPMA (lul_settings)
	setLuupVariable(RTCOA_WIFI_SID, "PMAMessage", lul_settings.NewMessage, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMALine",  lul_settings.NewLine, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMASet", 1, g_deviceId)

	return updatePMA()
end

--- Clear the PMA, and turn off "PMASet" so the thermostat no longer tried to
-- update the PMA.
local function resetPMA ()
	setLuupVariable(RTCOA_WIFI_SID, "PMAMessage", "", g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMALine",  0, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMASet", 0, g_deviceId)

	return updatePMA()
end

--- Reads the temperature from the configured PMA temperature device,
-- and sets the PMA to display the current temperature value.
local function updatePMATempFromTempDevice()
	local tempDevice = util.getLuupVariable(RTCOA_WIFI_SID, "PMATempDevice", g_deviceId, T_NUMBER)
	if (tempDevice > 0) then
		local temp = util.getLuupVariable(TEMP_SENSOR_SID, "CurrentTemperature", tempDevice, T_NUMBER)
		if (temp) then
			log.info("Pulled PMA temperature ", temp, " from device ", tempDevice)
			-- can't display negative values in the PMA, so we add an extra
			-- zero at the front - hopefully the user will notice that this
			-- represents a negative number
			setLuupVariable(RTCOA_WIFI_SID, "PMAMessage", string.gsub(string.format("%5.1f", temp), "-", "0"), g_deviceId)
			setLuupVariable(RTCOA_WIFI_SID, "PMALine",  1, g_deviceId)
			setLuupVariable(RTCOA_WIFI_SID, "PMASet", 1, g_deviceId)
		end
	end

	return updatePMA()
end

--- Sends the current remote temperature variable value to the thermostat
local function updateRemoteTemp ()
	local params = {}
	if (util.getLuupVariable(RTCOA_WIFI_SID, "RemoteTempSet", g_deviceId, T_BOOLEAN)) then
		params.rem_temp = util.round(delocalizeTemp(util.getLuupVariable(RTCOA_WIFI_SID, "RemoteTemp", g_deviceId, T_NUMBER)), 1)
	else
		params.rem_mode = 0
	end

	return (callThermostatAPI(TSTAT_API_REMOTE_TEMP_PATH, isValidUpdateResponse, params) ~= nil)
end

--- Updates the remote temperature variable, and sends the new value to the thermostat
local function setRemoteTemp (lul_settings)
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTemp", lul_settings.NewTemp, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTempSet", 1, g_deviceId)

	return updateRemoteTemp()
end

--- Clears the remote temperature variable, and sets "RemoteTempSet" to false, so
-- remote temp mode is turned off on the thermostat
local function resetRemoteTemp ()
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTemp", 0, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTempSet", 0, g_deviceId)

	return updateRemoteTemp()
end

--- Update the remote temp value from the configured remote temperature device
local function updateRemoteTempFromTempDevice()
	local tempDevice = util.getLuupVariable(RTCOA_WIFI_SID, "RemoteTempDevice", g_deviceId, T_NUMBER)
	if (tempDevice > 0) then
		local temp = util.getLuupVariable(TEMP_SENSOR_SID, "CurrentTemperature", tempDevice, T_NUMBER)
		if (temp) then
			log.info("Pulled remote temperature ", temp, " from device ", tempDevice)
			setLuupVariable(RTCOA_WIFI_SID, "RemoteTemp", temp, g_deviceId)
			setLuupVariable(RTCOA_WIFI_SID, "RemoteTempSet", 1, g_deviceId)
		end
	end

	return updateRemoteTemp()
end

--- Returns true of we received a valid time value from the thermostat
local function isValidTimeResponse(response)
	if (not isValidAPIParameterValue(response.day)) then
		log.error ("Invalid day")
		return false
	elseif (not isValidAPIParameterValue(response.hour)) then
		log.error ("Invalid hour")
		return false
	elseif (not isValidAPIParameterValue(response.minute)) then
		log.error ("Invalid minute")
		return false
	end

	return true
end

--- Returns true if we received a valid thermostat program response
local function isValidProgramResponse(response)
	if (response) then
		local days = 0
		for day,program in pairs(response) do
			days = days + 1
			if ((#program / 2) ~= math.floor(#program / 2)) then
				return false
			end
		end
		if (days ~= 1 and days ~= 7) then
			return false
		end
	end

	return true
end

--- Updates the cached thermostat programs. The reason we even cache the current programs
-- is that the thermostat does nasty things (rapid cycling control relay on/off) when we call the
-- API to retreive (_not set_!!) the current program. It's a serious firmware bug in the
-- thermostat, but it looks like it's not getting fixed. So, we avoid calling the thermostat
-- "get program" API at all costs and just rely on the cached copy.
local function updateProgramCache()
	local programTypes = { ["heat"] = "heat", ["cool"] = "cool"}

	if (g_programs == nil) then
		log.debug ("setting up g_programs")
		if (not util.getLuupVariable(RTCOA_WIFI_SID, "ProgramSetpoints", g_deviceId, T_BOOLEAN)) then
			log.debug("ProgramSetpoints disabled, clearing cached programs")
			g_programs = ""
			setLuupVariable(RTCOA_WIFI_SID, "Programs", "", g_deviceId)
		else
			local programsVar = util.getLuupVariable(RTCOA_WIFI_SID, "Programs", g_deviceId, T_STRING)
			log.debug("programsVar: ", programsVar)

			if (programsVar and programsVar ~= "") then
				g_programs = json.decode(programsVar)
			else
				log.debug ("Retrieving current programs from thermostat")
				local programs = {}
				for programType, variable in pairs(programTypes) do
					local path = TSTAT_API_PROGRAM_PATH .. "/" .. programType
					local oldTimeout = http.TIMEOUT
					http.TIMEOUT = 10
					local result = callThermostatAPI(path, isValidProgramResponse)
					http.TIMEOUT = oldTimeout
					if (result) then
						programs[programType] = result
					else
						return false
					end
				end
				setLuupVariable(RTCOA_WIFI_SID, "Programs", json.encode(programs), g_deviceId)
				g_programs = programs
			end
			log.debug ("g_programs = ", g_programs)
		end
	end

	return true
end

--- Checks to see if the program for a particular day and type (heat, cool)
-- matches the current setpoint. If not, the program is updated
-- and the new program is sent to the thermostat
local function checkAndUpdateProgram(programType, day, setPoint)
	log.debug ("checking program: programType = ", programType, ", day = ", day, ", setPoint = ", setPoint)
	local days = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
	local times = { 0, 540, 1020, 1260 }  -- 12am, 9am, 5pm, 9pm

	local program = g_programs[programType][tostring(day)]
	log.debug ("current program = ", program)

	local needsUpdate = false

	if (#program ~= 8) then
		log.debug ("Number of program entries does not match")
		needsUpdate = true
	else
		for num, time in pairs(times) do
			if (program[num*2-1] ~= time or program[num*2] ~= setPoint) then
				log.debug ("Program time / set point does not match for program #", num)
				needsUpdate = true
				break
			end
		end
	end

	if (needsUpdate) then
		log.debug ("updating program")
		local newProgram = {}

		for num, time in pairs(times) do
			newProgram[num*2-1] = time
			newProgram[num*2] = setPoint
		end

		local path = TSTAT_API_PROGRAM_PATH .. "/" .. programType .. "/" .. days[day+1]

		if (callThermostatAPI(path, isValidUpdateResponse, { [tostring(day)] = newProgram })) then
			log.info ("Updated thermostat program to ", newProgram)
			g_programs[programType][tostring(day)] = newProgram
			setLuupVariable(RTCOA_WIFI_SID, "Programs", json.encode(g_programs), g_deviceId)
		else
			return false
		end
	end

	return true
end

--- This crazy (and slightly complicated function) updates the thermostats
-- built in program so that it always sets the temperature to the
-- current setpoint.
local function programSetpoints ()
	local programTypes = { ["heat"] = HEAT_SETPOINT_SID, ["cool"] = COOL_SETPOINT_SID }

	updateProgramCache()

	if (g_programs and g_programs ~= "") then
		if (g_thermostatTime == nil) then
			return false
		end

		local secondsUntilMidnight = 86400 - ((g_thermostatTime.hour * 60 + g_thermostatTime.minute) * 60)
		local pollInterval = util.getLuupVariable(RTCOA_WIFI_SID, "PollInterval", g_deviceId, T_NUMBER)
		local nextDay = nil
		-- if we're within five polling intervals of the end of the day, check tomorrows schedule as well
		if (secondsUntilMidnight <= (pollInterval * 5)) then
			nextDay = g_thermostatTime.day + 1
			if (nextDay > 6) then
				nextDay = 0
			end
		end

		for programType, sid in pairs(programTypes) do
			local setPoint = util.getLuupVariable(sid, "CurrentSetpoint", g_deviceId, T_NUMBER)

			checkAndUpdateProgram(programType, g_thermostatTime.day, setPoint)

			if (nextDay) then
				checkAndUpdateProgram(programType, nextDay, setPoint)
			end
		end
	end
end

local function initGenericDeviceVariable(sid, variableName)
	luup.variable_set(sid, variableName, luup.variable_get(sid, variableName, g_deviceId), g_genericDeviceId)
end

local function initGenericDeviceVariables()
	initGenericDeviceVariable(TEMP_SENSOR_SID, "CurrentTemperature")
	initGenericDeviceVariable(USER_OPERATING_MODE_SID, "ModeTarget")
	initGenericDeviceVariable(USER_OPERATING_MODE_SID, "ModeStatus")
	initGenericDeviceVariable(USER_OPERATING_MODE_SID, "EnergyModeTarget")
	initGenericDeviceVariable(USER_OPERATING_MODE_SID, "EnergyModeStatus")
	initGenericDeviceVariable(FAN_MODE_SID, "Mode")
	initGenericDeviceVariable(FAN_MODE_SID, "FanStatus")
	initGenericDeviceVariable(HEAT_SETPOINT_SID, "CurrentSetpoint")
	initGenericDeviceVariable(COOL_SETPOINT_SID, "CurrentSetpoint")
	initGenericDeviceVariable(MCV_OPERATING_STATE_SID, "ModeState")
end

--- init Luup variables if they don't have values
local function initLuupVariables()

	-- initialize state variables
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "CreateGenericDevice", 0, g_deviceId)

	util.initVariableIfNotSet(RTCOA_WIFI_SID, "PollInterval", DEFAULT_POLL_INTERVAL, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "SyncClock", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "ProgramSetpoints", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "LooseTempControl", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "Programs", "", g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "LogLevel", log.LOG_LEVEL_INFO, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "InitialPollDelay", 0, g_deviceId)

	util.initVariableIfNotSet(RTCOA_WIFI_SID, "EnergyLEDColor", "Off", g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "EnergyLEDSet", 0, g_deviceId)

	util.initVariableIfNotSet(RTCOA_WIFI_SID, "PMAMessage", "", g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "PMALine", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "PMASet", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "PMATempDevice", 0, g_deviceId)

	util.initVariableIfNotSet(RTCOA_WIFI_SID, "RemoteTempDevice", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "RemoteTempSet", 0, g_deviceId)
	util.initVariableIfNotSet(RTCOA_WIFI_SID, "RemoteTemp", 0, g_deviceId)

	util.initVariableIfNotSet(TEMP_SENSOR_SID, "CurrentTemperature",  0, g_deviceId)
	util.initVariableIfNotSet(USER_OPERATING_MODE_SID, "ModeTarget", "Off", g_deviceId)
	util.initVariableIfNotSet(USER_OPERATING_MODE_SID, "ModeStatus", "Off", g_deviceId)
	util.initVariableIfNotSet(USER_OPERATING_MODE_SID, "EnergyModeTarget", "Normal", g_deviceId)
	util.initVariableIfNotSet(USER_OPERATING_MODE_SID, "EnergyModeStatus", "Normal", g_deviceId)
	util.initVariableIfNotSet(FAN_MODE_SID, "Mode", "Auto", g_deviceId)
	util.initVariableIfNotSet(FAN_MODE_SID, "FanStatus", "Off", g_deviceId)
	util.initVariableIfNotSet(HEAT_SETPOINT_SID, "CurrentSetpoint", localizeTemp(60), g_deviceId)
	util.initVariableIfNotSet(COOL_SETPOINT_SID, "CurrentSetpoint", localizeTemp(80), g_deviceId)
	util.initVariableIfNotSet(TEMPERATURE_HOLD_SID, "Target", 0, g_deviceId)
	util.initVariableIfNotSet(TEMPERATURE_HOLD_SID, "Status", 0, g_deviceId)

	util.initVariableIfNotSet(MCV_OPERATING_STATE_SID, "ModeState", "Off", g_deviceId)
	
	util.initVariableIfNotSet(MCV_ENERGY_METERING_SID, "UserSuppliedWattage", "0,0,0", g_deviceId)
end

local function createGenericDevice()
	if (util.getLuupVariable(RTCOA_WIFI_SID, "CreateGenericDevice", g_deviceId, T_BOOLEAN)) then
		-- Create / sync the "generic" thermostat device
		local deviceName = luup.devices[g_deviceId].description;
		local rootPtr = luup.chdev.start(g_deviceId)
		luup.chdev.append(g_deviceId, rootPtr, "generic_thermostat", deviceName .. " - Generic Interface Device",
		"urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1", "D_HVAC_ZoneThermostat1.xml", "", "", false)
		luup.chdev.sync(g_deviceId, rootPtr)

		-- Now find the device id for the created device
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == g_deviceId and
			device.device_type == "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1") then
				g_genericDeviceId = deviceId
				log.info ("Found child generic thermostat device: deviceId = ", deviceId, ", device = ", device)
			end
		end
		
		initGenericDeviceVariables()
	end
end


--------------------------------------------
---------- GLOBAL FUNCTIONS ----------------
--------------------------------------------

--- Called when remote temperature devices gets new temperature
function remoteTempCallback (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	log.info("Received remote temperature callback, ","lul_device = ", lul_device,", lul_value_new = ", lul_value_new)
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTemp", lul_value_new, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "RemoteTempSet", 1, g_deviceId)

	return updateRemoteTemp()
end

--- Called when PMA temperature devices gets new temperature
function pmaTempCallback (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	log.info("Received PMA temperature callback, ","lul_device = ", lul_device,", lul_value_new = ", lul_value_new)
	setLuupVariable(RTCOA_WIFI_SID, "PMAMessage", string.gsub(string.format("%5.1f", lul_value_new), "-", "0"), g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMALine",  1, g_deviceId)
	setLuupVariable(RTCOA_WIFI_SID, "PMASet", 1, g_deviceId)

	return updatePMA()
end

-- main "polling" function to update and monitor the thermostat settings
function thermostatPoller(pollAgain)
	log.setLevel(util.getLuupVariable(RTCOA_WIFI_SID, "LogLevel", g_deviceId, T_NUMBER))

	log.info ("Polling device " , g_deviceId, ", pollAgain = ", pollAgain)

	local currentTime = os.time()

	if (currentTime < g_nextPollTime and pollAgain and pollAgain == "true") then
		log.info ("Too early for next poll attempt for device " , g_deviceId)
		luup.call_delay("thermostatPoller", g_nextPollTime - currentTime, "true", true)
		return
	end

	if (not g_lastMetadataPollTime) then
		g_lastMetadataPollTime = currentTime
	end

	-- update the thermostat metadata (firmware version, etc.) once per hour
	if (currentTime - g_lastMetadataPollTime > 3600) then
		retrieveThermostatMetadata()
		g_lastMetadataPollTime = currentTime
	end

	if (retrieveThermostatStatus()) then
		programSetpoints()
	end

	if (not g_lastRemoteTempPollTime) then
		g_lastRemoteTempPollTime = 0
	end

	if (currentTime - g_lastRemoteTempPollTime > 900) then
		updateEnergyLED()
		updatePMATempFromTempDevice()
		updateRemoteTempFromTempDevice()
		g_lastRemoteTempPollTime = currentTime
	end

	if (pollAgain and pollAgain == "true") then
		local pollInterval = util.getLuupVariable(RTCOA_WIFI_SID, "PollInterval", g_deviceId, T_NUMBER)
		luup.call_delay("thermostatPoller", pollInterval, "true", true)
	end

	log.debug ("Exiting thermostatPoller")
end

-- Synchronizes thermostat device to Vera clock
-- Because we can't set the seconds value directly
-- we wait until the next "minute rollover" to set the time
function syncClock ()
	log.debug("Entering clockSync")

	local timeToNextCall = 0

	-- get current time on vera
	local rawTime = os.time()
	-- get parsed version of current time
	local currentTime = os.date("*t", rawTime)

	local secondsUntilNextMinute = 60 - currentTime.sec

	-- calculate the new time value for the thermostat
	-- doing it this way handles rollovers to next hour, day, etc.
	local newTime = os.date("*t", rawTime + secondsUntilNextMinute)

	-- only set the time on the thermostat if we're close to the
	-- minute "roll over". This allows us to set the thermostat
	-- time to the nearest second (more or less :)
	if (secondsUntilNextMinute < 5) then
		log.debug("Ready to sync thermostat clock in ",secondsUntilNextMinute," seconds")

		luup.sleep(secondsUntilNextMinute * 1000)
		local thermostatTime = {}
		-- In thermostat API time, Sunday is day 6, Monday is day 0
		-- In Lua API time, Sunday is day 1, Monday is day 2
		thermostatTime.day = newTime.wday - 2
		if (thermostatTime.day == -1) then
			thermostatTime.day = 6
		end
		thermostatTime.hour = newTime.hour
		thermostatTime.minute = newTime.min
		result = callThermostatAPI(TSTAT_API_TIME_PATH, isValidUpdateResponse, thermostatTime, true)
		if (not result) then -- if setting time failed
			log.debug("Thermostat clock sync failed")
			-- try again in a few minutes
			timeToNextCall = 60 * 10
		else
			log.info("Successfully synchronized thermostat clock: day=",thermostatTime.day,
			", hour=",thermostatTime.hour,", minute=",thermostatTime.minute)
			g_thermostatTime = thermostatTime
			-- otherwise, sync the clock again in few hours
			timeToNextCall = 60 * 60 * 3
		end

	else -- wait until we're close until the next minute rollover to set the clock
		timeToNextCall = secondsUntilNextMinute - 4
	end

	log.info("Time to next syncClock call: " , timeToNextCall)
	luup.call_delay("syncClock", timeToNextCall, g_deviceId, true)
end


function initializePhase2(lul_device)
	log.info ("Initialize phase 2")
	
	-- create the generic device (if enabled)
	createGenericDevice()

	-- retrieve the thermostat metadata (firmware version, model, etc.)
	retrieveThermostatMetadata()

	-- retrieve current thermostat status
	retrieveThermostatStatus()

	local pmaTempDevice = util.getLuupVariable(RTCOA_WIFI_SID, "PMATempDevice", g_deviceId, T_NUMBER)
	if (pmaTempDevice > 0) then
		log.info ("Registering PMA temperature callback, device = ", pmaTempDevice)
		luup.variable_watch("pmaTempCallback", TEMP_SENSOR_SID, "CurrentTemperature", pmaTempDevice)
	end

	local remoteTempDevice = util.getLuupVariable(RTCOA_WIFI_SID, "RemoteTempDevice", g_deviceId, T_NUMBER)
	if (remoteTempDevice > 0) then
		log.info ("Registering remote temperature callback, device = ", remoteTempDevice)
		luup.variable_watch("remoteTempCallback", TEMP_SENSOR_SID, "CurrentTemperature", remoteTempDevice)
	end

	local initialPollDelay = util.getLuupVariable(RTCOA_WIFI_SID, "InitialPollDelay", g_deviceId, T_NUMBER)

	-- start the polling loop after the user specified delay
	luup.call_delay("thermostatPoller", initialPollDelay, "true", true)

	if (util.getLuupVariable(RTCOA_WIFI_SID, "SyncClock", g_deviceId, T_BOOLEAN)) then
		-- start the clock sync loop as well
		luup.call_delay("syncClock", initialPollDelay * 60, g_deviceId, true)
	end
end

--- Initialize the thermostat plugin
function initialize(lul_device)
	g_deviceId = tonumber(lul_device)

	luup.attr_set("category_num", "5", lul_device)

	util.initLogging(LOG_PREFIX, LOG_FILTER, RTCOA_WIFI_SID, "LogLevel", g_deviceId)

	log.info ("Initializing thermostat module for device " , g_deviceId)
	
	-- set plugin version number
	luup.variable_set(RTCOA_WIFI_SID, "PluginVersion", PLUGIN_VERSION, g_deviceId)
	
	http.TIMEOUT = 5

	-- get temperature format
	local veraConfigData = doHttpRequest(g_configUrl)
	if (veraConfigData) then
		g_temperatureFormat = veraConfigData.temperature;
		if (not g_temperatureFormat) then
			g_temperatureFormat = "F"
		end
		log.info("Temperature Format = " , g_temperatureFormat)
	else
		local msg = "Unable to retrieve Vera temperature format"
		log.error(msg)
		return false, msg, "Radio Thermostat Wifi"
	end

	-- initalize Luup variables to sane values
	initLuupVariables()

	-- get ip address for thermostat
	g_ipAddress = luup.devices[g_deviceId].ip

	if (g_ipAddress and g_ipAddress ~= "") then
		log.info("Using IP Address: " , g_ipAddress)
	else
		local msg = "No IP Address configured for thermostat"
		log.error(msg)
		return false, msg, "Radio Thermostat Wifi"
	end

	luup.call_delay("initializePhase2", 1, g_deviceId, true)

	log.info("Done with initialization")
end

--- function to handle UPnP api calls
function dispatchJob(lul_device, lul_settings, lul_job, serviceId, action)
	log.info ("Entering dispatchJob, serviceId = " , serviceId , ", action = " , action , ", lul_settings = " , (lul_settings))

	local success = false

	if (serviceId == USER_OPERATING_MODE_SID and action == "SetModeTarget" or
	serviceId == FAN_MODE_SID and action == "SetMode" or
	serviceId == HEAT_SETPOINT_SID and action == "SetCurrentSetpoint" or
	serviceId == COOL_SETPOINT_SID and action == "SetCurrentSetpoint" or
	serviceId == TEMPERATURE_HOLD_SID and action == "SetTarget") then
		-- change the setting
		success = updateThermostatSetting (lul_settings, serviceId, action)
		-- force at least 10 second delay until the next poll attempt
		g_nextPollTime = os.time() + 10
	elseif (serviceId == USER_OPERATING_MODE_SID and action == "SetEnergyModeTarget") then
		success = setEnergyMode (lul_settings)
	elseif (serviceId == RTCOA_WIFI_SID and action =="SetEnergyLED") then
		success = setEnergyLED (lul_settings)
	elseif (serviceId == RTCOA_WIFI_SID and action =="ResetEnergyLED") then
		success = resetEnergyLED ()
	elseif (serviceId == RTCOA_WIFI_SID and action =="SetPMA") then
		success = setPMA (lul_settings)
	elseif (serviceId == RTCOA_WIFI_SID and action =="ResetPMA") then
		success = resetPMA ()
	elseif (serviceId == RTCOA_WIFI_SID and action =="SetRemoteTemp") then
		success = setRemoteTemp (lul_settings)
	elseif (serviceId == RTCOA_WIFI_SID and action =="ResetRemoteTemp") then
		success = resetRemoteTemp ()
	else
		log.error("Unrecognized job request")
	end

	if (success) then
		log.info("job was successful")
		return(JOB_RETURN_SUCCESS)
	else
		log.error("job failed")
		return(JOB_RETURN_FAILURE)
	end
end

function setConfigUrl(url)
	g_configUrl = url
end

-- RETURN GLOBAL FUNCTIONS
return {
	initialize=initialize,
	dispatchJob=dispatchJob,
	setConfigUrl=setConfigUrl
}