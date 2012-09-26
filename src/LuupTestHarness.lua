-- MiOS Plugin Test Harness
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
local os = os

-- IMPORT REQUIRED MODULES
local log = require("L_RTCOA_Wifi_log")
local socket = require("socket")

-----------------------------
---- Globals ----------------
-----------------------------
local luup = {}

-----------------------------
---- File Globals -----------
-----------------------------

local g_luupVariables = {}

local g_callbackFunctions = {}

local g_functions = {}

-----------------------------
---- File Constants -----------
-----------------------------
local LOG_FILTER =  {
	["LuupTestHarness.lua$"] = {
		"log",
		"getVariableTable"
	}
}

--------------------------------
---- Stub Support Functions ----
--------------------------------

local function getVariableTable(serviceId, lul_device)
	if (not g_luupVariables[lul_device]) then
		g_luupVariables[lul_device] = {}
	end
	if (not g_luupVariables[lul_device][serviceId]) then
		g_luupVariables[lul_device][serviceId] = {}
	end
	return g_luupVariables[lul_device][serviceId]
end

local function findFunction(functionTable, name)
	assert(type(name) == "string")
	for k, v in pairs(functionTable) do
		if (type(v) == "table") then
			local func = findFunction(v, name)
			if (func) then
				return func
			end
		elseif (type(v) == "function" and k == name) then
			return v
		end
	end
	return nil
end

--local function sleep(n)
--	os.execute("sleep " .. tonumber(n) / 1000)
--end

-------------------------------
---- Luup Stub Functions ------
-------------------------------

function luup.log (message, luupLogLevel)
	if (not luupLogLevel) then
		luupLogLevel = 50
	end
	print(os.date("%m/%d/%Y %H:%M:%S") .. " [" .. luupLogLevel .. "] " ..message)
end

function luup.variable_set(serviceId, name, value, lul_device)
	log.debug("Setting [" .. lul_device .."][" .. serviceId .."][" .. name .. "] = " .. value .. " (" .. type(value) .. ")")
	getVariableTable(serviceId, lul_device)[name] = value
end


function luup.variable_get(serviceId, name, lul_device)
	local value = getVariableTable(serviceId, lul_device)[name]
	log.debug("Getting [" .. lul_device .."][" .. serviceId .."][" .. name .. "] = " .. tostring(value) .. " (" .. type(value) .. ")")
	return(value)
end


function luup.call_delay(functionName, delay, data, thread)
	log.debug("luup.call_delay called, functionName = " .. functionName ..
	", delay = " .. delay)
	g_callbackFunctions[functionName] = {}
	g_callbackFunctions[functionName].name = functionName
	g_callbackFunctions[functionName].executionTime = os.time() + delay
	g_callbackFunctions[functionName].data = data
end


function luup.sleep(sleepTime)
	log.debug ("Sleeping for " .. sleepTime .. " milliseconds")
	--sleep(sleepTime)
	socket.sleep(sleepTime / 1000)
end

function luup.attr_set(...)

end


function luup.task(...)

end

function luup._addFunctions(functionsTable)
	table.insert(g_functions, functionsTable)
end

function luup._callbackLoop()
	local nextFunc = nil

	repeat
		nextFunc = nil
		
		-- find the next function that needs execution
		for k,v in pairs(g_callbackFunctions) do
			if (not nextFunc or v.executionTime < nextFunc.executionTime) then
				nextFunc = v
			end
		end

		if (nextFunc) then
			g_callbackFunctions[nextFunc.name] = nil
			now = os.time()
			if (nextFunc.executionTime > now) then
				log.debug ("Sleeping for " .. nextFunc.executionTime - now .. " seconds")
				luup.sleep((nextFunc.executionTime - now) * 1000)
			end
			local func = findFunction(g_functions, nextFunc.name)
			if (func ~= nil) then
				log.debug ("Calling function " .. nextFunc.name)
				func (nextFunc.data)
			else
				log.debug ("Couldn't find function " .. nextFunc.name)
			end
		end
	until (not nextFunc)
end

log.addFilter(LOG_FILTER)

return (luup)


