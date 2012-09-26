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

luup = require ("LuupTestHarness")
log = require("L_RTCOA_Wifi_log")


local LOG_FILTER =  {
	["Tests.lua$"] = {
	}
}

log.addFilter(LOG_FILTER)

luup.devices = { [0] = { ["ip"] = "10.23.46.32" } }
luup.variable_set("urn:schemas-hugheaves-com::serviceId:HVAC_RTCOA_Wifi1", "LogLevel", 30, 0)
luup.variable_set("urn:hugheaves-com:serviceId:HVAC_RTCOA_Wifi1", "InitialPollDelay", 5, 0)

core = require("L_RTCOA_Wifi_core")
core.setConfigUrl("http://veralite:3480/data_request?id=lu_sdata")
luup._addFunctions(core)

luup.call_delay("thermostatInitialize", 1, "0", "0")

luup._callbackLoop()