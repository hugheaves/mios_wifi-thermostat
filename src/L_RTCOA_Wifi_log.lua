-- Generic Lua Logging Facility
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
local luadebug = debug
local string = string

--
-- Constants
--

-- Module specific logging levels. Call the  "setLevel" function
-- with one of these
local LOG_LEVEL_ERROR = 10
local LOG_LEVEL_INFO = 20
local LOG_LEVEL_DEBUG = 30

local LOG_LEVELS = {
[LOG_LEVEL_ERROR] = "ERROR",
[LOG_LEVEL_INFO] = "INFO",
[LOG_LEVEL_DEBUG] = "DEBUG"
}

local g_logLevel = LOG_LEVEL_INFO
local g_logPrefix = ""
local g_logFilter = {}
local g_logFunc = print

-- silly function that returns value, or "nil" if value is nil
local function nilSafe(value)
	if (value) then
		return value
	else
		return "nil"
	end
end

-- lookup a key in a table by its value
local function findKeyByValue(table, value)
	for k,v in pairs(table) do
		if (v == value) then
			return k
		end
	end

	return nil;
end


-- function adapted from http://www.luafaq.org/
local function deepToString(o)
	if (o == nil) then
		return "nil"
	elseif type(o) == 'string' then
		return o
	elseif type(o) == 'number' then
		return tostring(o)
	elseif type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then
				k = '"'..k..'"'
			end
			if type(v) == 'string' then
				v = '"' .. v .. '"'
			else
				v = deepToString(v)
			end
			s = s .. '['..k..'] = ' .. v .. ','
		end
		return s .. '} '
	else
		return '"' .. tostring(o) .. '"'
	end
end

--- internal function builds a message
-- and logs at the given level using g_logFunc
local function doLog(level, callerLevel, arg)
	local name = "unknown"
	local line = "unknown"
	local messageLevel = LOG_LEVELS[level]
	
	local info = luadebug.getinfo(callerLevel, "nlS")
	if (info and info.name) then
		name = info.name
	elseif (info and info.short_src) then
		name = info.short_src
	end
	if (info and info.currentline) then
		line = info.currentline
	end
	
	local message = g_logPrefix .. " " .. messageLevel .. " (" .. name .. ":" .. line .. ") - "
	for i = 1, arg.n, 1 do
		message = message .. deepToString(arg[i])
	end

	g_logFunc(message, level)
end

-- log an error message
local function error(...)
	doLog (LOG_LEVEL_ERROR, 3, arg)
end

-- log an informational message
local function info(...)
	if (g_logLevel >= LOG_LEVEL_INFO) then
		doLog (LOG_LEVEL_INFO, 3, arg)
	end
end

-- log a debugging message
local function debug(...)
	if (g_logLevel >= LOG_LEVEL_DEBUG) then
		doLog (LOG_LEVEL_DEBUG, 3, arg)
	end
end

--- This function is registered with Lua debug.sethook()
-- when the logLevel is setup to DEBUG.
-- It provides logging of function exit and entry to assist with debugging
local function logHook(hookType)
	local message = ""
	local callerLevel = 2

	local info = luadebug.getinfo(callerLevel, "S")
	if (not info or info.what ~= "Lua") then
		return
	end
	
	if (not info.source or info.source:len() < 1 or info.source:byte(1) ~= 64) then
		return
	end
	
	local functionList = nil
	for k, v in pairs(g_logFilter) do
		match = info.source:match(k) 
		if (match) then
			functionList = v
			break
		end
	end
	
	if (not functionList) then
		return
	end
	
	if (#functionList > 0) then
		info = luadebug.getinfo(callerLevel, "nl")
		if (not info or not info.name) then
			return
		end
		if (findKeyByValue(functionList, info.name)) then
			return
		end
	end
	
	if (hookType == "call") then
		message = "Called FROM:"
	elseif (hookType == "return") then
		message = "Returning TO:"
	end

	local seperator = " "
	repeat
		callerLevel = callerLevel + 1
		info = luadebug.getinfo(callerLevel, "nlS")
		if (info) then
			local src = info.short_src or "nil"
			local name = info.name and info.name or src
			local line = info.currentline and info.currentline or "unknown"
			message = message .. seperator .. "(" .. name .. ":" .. line .. ")"
			if (hookType == "call") then
				seperator = " <- "
			else
				seperator = " -> "
			end
		end
	until (not info)

	doLog(LOG_LEVEL_DEBUG, 3, { ["n"] = 1, [1] = message })
end

--- set the log level and install or remove the debug hook depending on the new level
local function setLevel(newLogLevel)
	if (newLogLevel < LOG_LEVEL_DEBUG and g_logLevel == LOG_LEVEL_DEBUG) then
		luadebug.sethook ()
	elseif (newLogLevel == LOG_LEVEL_DEBUG and g_logLevel < LOG_LEVEL_DEBUG) then
		luadebug.sethook (logHook, "cr")
	end
	g_logLevel = newLogLevel
end

local function setPrefix(logPrefix) 
	g_logPrefix = logPrefix
end

--- initialize the logging module
local function setLogFunction(logFunction)
	g_logFunc = logFunction
end

local function addFilter(logFilter)
	if (logFilter) then
		for k, v in pairs(logFilter) do
			g_logFilter[k] = logFilter[k]
		end
	end
end

-- RETURN GLOBAL FUNCTION TABLE
return {
	init = init,
	debug = debug,
	info = info,
	error = error,
	setPrefix = setPrefix,
	setLevel = setLevel,
	addFilter = addFilter,
	setLogFunction = setLogFunction,
	LOG_LEVEL_ERROR = LOG_LEVEL_ERROR,
	LOG_LEVEL_INFO = LOG_LEVEL_INFO,
	LOG_LEVEL_DEBUG = LOG_LEVEL_DEBUG
}

