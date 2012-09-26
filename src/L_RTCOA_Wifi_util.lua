-- MiOS Utility Functions
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

--
-- This logging module provides some higher level
-- functionality on top of Luup logging.
--

-- IMPORT GLOBALS
local luup = luup
local string = string

-- IMPORT REQUIRED MODULES
local log = require("L_RTCOA_Wifi_log")

-- CONSTANTS
local T_NUMBER = "T_NUMBER"
local T_BOOLEAN = "T_BOOLEAN"
local T_STRING = "T_STRING"

-- initalize a Luup variable to a value if it's not already set
local function initVariableIfNotSet(serviceId, variableName, initValue, lul_device)
	local value = luup.variable_get(serviceId, variableName, lul_device)
	log.debug ("initVariableIfNotSet: lul_device [",lul_device,"] serviceId [",serviceId,"] Variable Name [",variableName,
	"] Lua Type [", type(value), "] Value [", value, "]")
	if (value == nil or value == "") then
		luup.variable_set(serviceId, variableName, initValue, lul_device)
	end
end

--- return a Luup variable with the added capability to convert to a the
-- appropriate Lua type.
-- The Luup API _should_ do this automatically as the variables are
-- all declared with types, but it doesn't. Grrrr.....
local function getLuupVariable(serviceId, variableName, lul_device, varType) 
	local value = luup.variable_get(serviceId, variableName, lul_device)
	log.debug ("getLuupVariable: lul_device [",lul_device,"] serviceId [",serviceId,"] Variable Name [",variableName,
	"] Lua Type [", type(value), "] Value [", value, "]", "] varType [", varType, "]")
	if (varType == T_BOOLEAN) then
		return (value == "1")
	elseif (varType == T_NUMBER) then
		return (value + 0)
	elseif (varType == T_STRING) then
		return tostring(value)
	else
		error ("Invalid varType passed to getLuupVariable, serviceId = " .. serviceId ..
			", variableName = " .. variableName .. ", lul_device = " .. lul_device ..
			", varType = " .. tostring(varType) )
	end
end

local function luupLog(message, level)
	local luupLogLevel 
	if (level <= log.LOG_LEVEL_ERROR) then
		luupLogLevel = 1
	elseif (level <= log.LOG_LEVEL_INFO) then
		luupLogLevel = 2
	else
		luupLogLevel = 50
	end
	luup.log(message, luupLogLevel)
end

-- RETURN GLOBAL FUNCTION TABLE
return {
	initVariableIfNotSet = initVariableIfNotSet,
	getLuupVariable = getLuupVariable,
	luupLog = luupLog,
	T_NUMBER = T_NUMBER,
	T_BOOLEAN = T_BOOLEAN,
	T_STRING = T_STRING
}

