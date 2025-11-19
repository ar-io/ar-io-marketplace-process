

-- module: ".common.json"
local function _loaded_mod_common_json()
--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
	["\\"] = "\\",
	['"'] = '"',
	["\b"] = "b",
	["\f"] = "f",
	["\n"] = "n",
	["\r"] = "r",
	["\t"] = "t",
}

local escape_char_map_inv = { ["/"] = "/" }
for k, v in pairs(escape_char_map) do
	escape_char_map_inv[v] = k
end

local function escape_char(c)
	return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end

local function encode_nil(val)
	return "null"
end

local function encode_table(val, stack)
	local res = {}
	stack = stack or {}

	-- Circular reference?
	if stack[val] then
		error("circular reference")
	end

	stack[val] = true

	if rawget(val, 1) ~= nil or next(val) == nil then
		-- Treat as array -- check keys are valid and it is not sparse
		local n = 0
		for k in pairs(val) do
			if type(k) ~= "number" then
				error("invalid table: mixed or invalid key types")
			end
			n = n + 1
		end
		if n ~= #val then
			error("invalid table: sparse array")
		end
		-- Encode
		for i, v in ipairs(val) do
			table.insert(res, encode(v, stack))
		end
		stack[val] = nil
		return "[" .. table.concat(res, ",") .. "]"
	else
		-- Treat as an object
		for k, v in pairs(val) do
			if type(k) ~= "string" then
				error("invalid table: mixed or invalid key types")
			end
			table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
		end
		stack[val] = nil
		return "{" .. table.concat(res, ",") .. "}"
	end
end

local function encode_string(val)
	return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(val)
	-- Check for NaN, -inf and inf
	if val ~= val or val <= -math.huge or val >= math.huge then
		error("unexpected number value '" .. tostring(val) .. "'")
	end
	return string.format("%.14g", val)
end

local type_func_map = {
	["nil"] = encode_nil,
	["table"] = encode_table,
	["string"] = encode_string,
	["number"] = encode_number,
	["boolean"] = tostring,
}

encode = function(val, stack)
	local t = type(val)
	local f = type_func_map[t]
	if f then
		return f(val, stack)
	end
	error("unexpected type '" .. t .. "'")
end

function json.encode(val)
	return (encode(val))
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
	local res = {}
	for i = 1, select("#", ...) do
		res[select(i, ...)] = true
	end
	return res
end

local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals = create_set("true", "false", "null")

local literal_map = {
	["true"] = true,
	["false"] = false,
	["null"] = nil,
}

local function next_char(str, idx, set, negate)
	for i = idx, #str do
		if set[str:sub(i, i)] ~= negate then
			return i
		end
	end
	return #str + 1
end

local function decode_error(str, idx, msg)
	local line_count = 1
	local col_count = 1
	for i = 1, idx - 1 do
		col_count = col_count + 1
		if str:sub(i, i) == "\n" then
			line_count = line_count + 1
			col_count = 1
		end
	end
	error(string.format("%s at line %d col %d", msg, line_count, col_count))
end

local function codepoint_to_utf8(n)
	-- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
	local f = math.floor
	if n <= 0x7f then
		return string.char(n)
	elseif n <= 0x7ff then
		return string.char(f(n / 64) + 192, n % 64 + 128)
	elseif n <= 0xffff then
		return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
	elseif n <= 0x10ffff then
		return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128)
	end
	error(string.format("invalid unicode codepoint '%x'", n))
end

local function parse_unicode_escape(s)
	local n1 = tonumber(s:sub(1, 4), 16)
	local n2 = tonumber(s:sub(7, 10), 16)
	-- Surrogate pair?
	if n2 then
		return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
	else
		return codepoint_to_utf8(n1)
	end
end

local function parse_string(str, i)
	local res = ""
	local j = i + 1
	local k = j

	while j <= #str do
		local x = str:byte(j)

		if x < 32 then
			decode_error(str, j, "control character in string")
		elseif x == 92 then -- `\`: Escape
			res = res .. str:sub(k, j - 1)
			j = j + 1
			local c = str:sub(j, j)
			if c == "u" then
				local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
					or str:match("^%x%x%x%x", j + 1)
					or decode_error(str, j - 1, "invalid unicode escape in string")
				res = res .. parse_unicode_escape(hex)
				j = j + #hex
			else
				if not escape_chars[c] then
					decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
				end
				res = res .. escape_char_map_inv[c]
			end
			k = j + 1
		elseif x == 34 then -- `"`: End of string
			res = res .. str:sub(k, j - 1)
			return res, j + 1
		end

		j = j + 1
	end

	decode_error(str, i, "expected closing quote for string")
end

local function parse_number(str, i)
	local x = next_char(str, i, delim_chars)
	local s = str:sub(i, x - 1)
	local n = tonumber(s)
	if not n then
		decode_error(str, i, "invalid number '" .. s .. "'")
	end
	return n, x
end

local function parse_literal(str, i)
	local x = next_char(str, i, delim_chars)
	local word = str:sub(i, x - 1)
	if not literals[word] then
		decode_error(str, i, "invalid literal '" .. word .. "'")
	end
	return literal_map[word], x
end

local function parse_array(str, i)
	local res = {}
	local n = 1
	i = i + 1
	while 1 do
		local x
		i = next_char(str, i, space_chars, true)
		-- Empty / end of array?
		if str:sub(i, i) == "]" then
			i = i + 1
			break
		end
		-- Read token
		x, i = parse(str, i)
		res[n] = x
		n = n + 1
		-- Next token
		i = next_char(str, i, space_chars, true)
		local chr = str:sub(i, i)
		i = i + 1
		if chr == "]" then
			break
		end
		if chr ~= "," then
			decode_error(str, i, "expected ']' or ','")
		end
	end
	return res, i
end

local function parse_object(str, i)
	local res = {}
	i = i + 1
	while 1 do
		local key, val
		i = next_char(str, i, space_chars, true)
		-- Empty / end of object?
		if str:sub(i, i) == "}" then
			i = i + 1
			break
		end
		-- Read key
		if str:sub(i, i) ~= '"' then
			decode_error(str, i, "expected string for key")
		end
		key, i = parse(str, i)
		-- Read ':' delimiter
		i = next_char(str, i, space_chars, true)
		if str:sub(i, i) ~= ":" then
			decode_error(str, i, "expected ':' after key")
		end
		i = next_char(str, i + 1, space_chars, true)
		-- Read value
		val, i = parse(str, i)
		-- Set
		res[key] = val
		-- Next token
		i = next_char(str, i, space_chars, true)
		local chr = str:sub(i, i)
		i = i + 1
		if chr == "}" then
			break
		end
		if chr ~= "," then
			decode_error(str, i, "expected '}' or ','")
		end
	end
	return res, i
end

local char_func_map = {
	['"'] = parse_string,
	["0"] = parse_number,
	["1"] = parse_number,
	["2"] = parse_number,
	["3"] = parse_number,
	["4"] = parse_number,
	["5"] = parse_number,
	["6"] = parse_number,
	["7"] = parse_number,
	["8"] = parse_number,
	["9"] = parse_number,
	["-"] = parse_number,
	["t"] = parse_literal,
	["f"] = parse_literal,
	["n"] = parse_literal,
	["["] = parse_array,
	["{"] = parse_object,
}

parse = function(str, idx)
	local chr = str:sub(idx, idx)
	local f = char_func_map[chr]
	if f then
		return f(str, idx)
	end
	decode_error(str, idx, "unexpected character '" .. chr .. "'")
end

function json.decode(str)
	if type(str) ~= "string" then
		error("expected argument of type string, got " .. type(str))
	end
	local res, idx = parse(str, next_char(str, 1, space_chars, true))
	idx = next_char(str, idx, space_chars, true)
	if idx <= #str then
		decode_error(str, idx, "trailing garbage")
	end
	return res
end

return json

end

_G.package.loaded[".common.json"] = _loaded_mod_common_json()

-- module: ".common.utils"
local function _loaded_mod_common_utils()
-- the majority of this file came from https://github.com/permaweb/aos/blob/main/process/utils.lua

local json = require(".common.json")
local utils = { _version = "0.0.1" }

local function isArray(table)
	if type(table) == "table" then
		local maxIndex = 0
		for k, v in pairs(table) do
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
				return false -- If there's a non-integer key, it's not an array
			end
			maxIndex = math.max(maxIndex, k)
		end
		-- If the highest numeric index is equal to the number of elements, it's an array
		return maxIndex == #table
	end
	return false
end

-- @param {function} fn
-- @param {number} arity
utils.curry = function(fn, arity)
	assert(type(fn) == "function", "function is required as first argument")
	arity = arity or debug.getinfo(fn, "u").nparams
	if arity < 2 then
		return fn
	end

	return function(...)
		local args = { ... }

		if #args >= arity then
			return fn(table.unpack(args))
		else
			return utils.curry(function(...)
				return fn(table.unpack(args), ...)
			end, arity - #args)
		end
	end
end

--- Concat two Array Tables.
-- @param {table<Array>} a
-- @param {table<Array>} b
utils.concat = utils.curry(function(a, b)
	assert(type(a) == "table", "first argument should be a table that is an array")
	assert(type(b) == "table", "second argument should be a table that is an array")
	assert(isArray(a), "first argument should be a table")
	assert(isArray(b), "second argument should be a table")

	local result = {}
	for i = 1, #a do
		result[#result + 1] = a[i]
	end
	for i = 1, #b do
		result[#result + 1] = b[i]
	end
	return result
end, 2)

--- reduce applies a function to a table
-- @param {function} fn
-- @param {any} initial
-- @param {table<Array>} t
utils.reduce = utils.curry(function(fn, initial, t)
	assert(type(fn) == "function", "first argument should be a function that accepts (result, value, key)")
	assert(type(t) == "table" and isArray(t), "third argument should be a table that is an array")
	local result = initial
	for k, v in pairs(t) do
		if result == nil then
			result = v
		else
			result = fn(result, v, k)
		end
	end
	return result
end, 3)

-- @param {function} fn
-- @param {table<Array>} data
utils.map = utils.curry(function(fn, data)
	assert(type(fn) == "function", "first argument should be a unary function")
	assert(type(data) == "table" and isArray(data), "second argument should be an Array")

	local function map(result, v, k)
		result[k] = fn(v, k)
		return result
	end

	return utils.reduce(map, {}, data)
end, 2)

-- @param {function} fn
-- @param {table<Array>} data
utils.filter = utils.curry(function(fn, data)
	assert(type(fn) == "function", "first argument should be a unary function")
	assert(type(data) == "table" and isArray(data), "second argument should be an Array")

	local function filter(result, v, _k)
		if fn(v) then
			table.insert(result, v)
		end
		return result
	end

	return utils.reduce(filter, {}, data)
end, 2)

-- @param {function} fn
-- @param {table<Array>} t
utils.find = utils.curry(function(fn, t)
	assert(type(fn) == "function", "first argument should be a unary function")
	assert(type(t) == "table", "second argument should be a table that is an array")
	for _, v in pairs(t) do
		if fn(v) then
			return v
		end
	end
end, 2)

-- @param {string} propName
-- @param {string} value
-- @param {table} object
utils.propEq = utils.curry(function(propName, value, object)
	assert(type(propName) == "string", "first argument should be a string")
	-- assert(type(value) == "string", "second argument should be a string")
	assert(type(object) == "table", "third argument should be a table<object>")

	return object[propName] == value
end, 3)

-- @param {table<Array>} data
utils.reverse = function(data)
	assert(type(data) == "table", "argument needs to be a table that is an array")
	return utils.reduce(function(result, v, i)
		result[#data - i + 1] = v
		return result
	end, {}, data)
end

-- @param {string} propName
-- @param {table} object
utils.prop = utils.curry(function(propName, object)
	return object[propName]
end, 2)

-- @param {any} val
-- @param {table<Array>} t
utils.includes = utils.curry(function(val, t)
	assert(type(t) == "table", "argument needs to be a table")
	return utils.find(function(v)
		return v == val
	end, t) ~= nil
end, 2)

-- @param {table} t
utils.keys = function(t)
	assert(type(t) == "table", "argument needs to be a table")
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	return keys
end

-- @param {table} t
utils.values = function(t)
	assert(type(t) == "table", "argument needs to be a table")
	local values = {}
	for _, value in pairs(t) do
		table.insert(values, value)
	end
	return values
end

function utils.hasMatchingTag(tag, value)
	return Handlers.utils.hasMatchingTag(tag, value)
end

function utils.reply(msg)
	Handlers.utils.reply(msg)
end

function utils.parseAntState(antJsonStr)
	assert(type(antJsonStr) == "string", "Data must be a string")
	local decoded = json.decode(antJsonStr)
	assert(type(decoded.Controllers) == "table", "Controllers must be a table")
	assert(type(decoded.Owner) == "string" or type(decoded.Owner) == nil, "Owner must be a string or nil")

	return {
		Owner = decoded.Owner,
		Controllers = utils.controllerTableFromArray(decoded.Controllers),
	}
end

function utils.camelCase(str)
	-- Remove any leading or trailing spaces
	str = string.gsub(str, "^%s*(.-)%s*$", "%1")

	-- Convert PascalCase to camelCase
	str = string.gsub(str, "^%u", string.lower)

	-- Handle kebab-case, snake_case, and space-separated words
	str = string.gsub(str, "[-_%s](%w)", function(s)
		return string.upper(s)
	end)

	return str
end

function utils.indexOf(t, value)
	for i, v in ipairs(t) do
		if v == value then
			return i
		end
	end
	return -1
end

function utils.controllerTableFromArray(t)
	assert(type(t) == "table", "argument needs to be a table")
	local map = {}
	for _, v in ipairs(t) do
		map[v] = true
	end
	return map
end

function utils.updateAffiliations(antId, newAnt, addresses, ants, currentReference)
	-- Remove previous affiliations for old owner and controllers
	local maybeOldAnt = ants[antId]
	local newAffliates = utils.affiliatesForAnt(newAnt)
	local affiliatesToRemoveAntIdFrom = {}

	-- Remove stale address affiliations
	if maybeOldAnt ~= nil then
		local lastReference = maybeOldAnt.lastReference
		assert(
			lastReference == nil or lastReference <= currentReference,
			"Last updated timestamp is greater than the current timestamp"
		)
		local oldAffliates = utils.affiliatesForAnt(maybeOldAnt)
		for oldAffliate, _ in pairs(oldAffliates) do
			if not newAffliates[oldAffliate] and addresses[oldAffliate] then
				table.insert(affiliatesToRemoveAntIdFrom, oldAffliate)
				addresses[oldAffliate][antId] = nil
			end
		end
	end

	-- Create new affiliations
	for address, _ in pairs(newAffliates) do
		-- Instantiate the address table if it doesn't exist
		addresses[address] = addresses[address] or {}
		-- Finalize the affiliation
		addresses[address][antId] = true
	end

	-- Update the ants table with the newest ANT state
	if #utils.keys(newAffliates) == 0 then
		ants[antId] = nil
	else
		ants[antId] = newAnt
		ants[antId].lastReference = currentReference
	end

	return {
		affiliatesToRemoveAntIdFrom = affiliatesToRemoveAntIdFrom,
	}
end

function utils.errorHandler(err)
	return debug.traceback(err)
end

--[[
		position defaults to "add"
		
		Behavior:
		- "add" - Adds the handler to the end of the list
		- "prepend" - Adds the handler to the beginning of the list
		- "append" - Adds the handler to the end of the list

		create a handler by matching an action name to an Action tag on the message
		if the handler function throws an error, send an error message to the sender

	]]
function utils.createActionHandler(action, msgHandler, position)
	assert(
		type(position) == "string" or type(position) == "nil",
		utils.errorHandler("Position must be a string or nil")
	)
	assert(
		position == nil or position == "add" or position == "prepend" or position == "append",
		"Position must be one of 'add', 'prepend', 'append'"
	)

	return Handlers[position or "add"](
		utils.camelCase(action),
		Handlers.utils.hasMatchingTag("Action", action),
		function(msg)
			-- backwards compatibility for old message types
			msg.Reference = msg._Ref or msg.Reference
			print("Handling Action [" .. msg.Id .. "]: " .. action)
			local handlerStatus, handlerRes = xpcall(function()
				msgHandler(msg)
			end, utils.errorHandler)

			if not handlerStatus then
				ao.send({
					Target = msg.From,
					Action = "Invalid-" .. action .. "-Notice",
					Error = action .. "-Error",
					["Message-Id"] = msg.Id,
					Data = handlerRes,
				})
			end

			return handlerRes
		end
	)
end

function utils.affiliatesForAnt(ant)
	local affliates = {}
	if ant.Owner then
		affliates[ant.Owner] = true
	end
	for address, _ in pairs(ant.Controllers) do
		affliates[address] = true
	end
	return affliates
end

---@param address string
---@param ants ANTMap
---@return ACL
function utils.affiliationsForAddress(address, ants)
	---@type ACL
	local affiliations = {
		Owned = {},
		Controlled = {},
	}
	for antId, ant in pairs(ants) do
		if ant.Owner == address then
			table.insert(affiliations.Owned, antId)
		elseif ant.Controllers[address] then
			table.insert(affiliations.Controlled, antId)
		end
	end
	return affiliations
end

---@param ants ANTMap
---@param processId string
---@return ACLMap
function utils.affiliationsForAnt(processId, ants)
	assert(ants[processId], "Unable to get affiliations for ANT " .. processId .. " because it does not exist")
	---@type ACLMap
	local affiliations = {}
	affiliations[ants[processId].Owner] = utils.affiliationsForAddress(ants[processId].Owner, ants)
	for controller, _ in pairs(ants[processId].Controllers) do
		affiliations[controller] = utils.affiliationsForAddress(controller, ants)
	end

	return affiliations
end

--- Checks if an address is a valid Arweave address
--- @param address string The address to check
--- @return boolean isValidArweaveAddress - whether the address is a valid Arweave address
function utils.validateArweaveId(address)
	return type(address) == "string" and #address == 43 and string.match(address, "^[%w-_]+$") ~= nil
end

function utils.unregisterAnt(caller, ants, antId, addresses)
	assert(type(antId) == "string", "Process-Id is required")
	assert(ants[antId], "Unable to unregister ANT " .. antId .. " because it does not exist")

	local antOwner = ants[antId].Owner
	local isAntOwner = antOwner == caller
	local isRegistryOwner = caller == Owner or caller == ao.id
	local isAnt = antId == caller
	-- Should allow flexibility while protecting against attacks deregistering other peoples assets.
	assert(isAntOwner or isAnt or isRegistryOwner, "Only ANT owner, ANT, or registry owner, or ao.id can unregister")

	-- Remove from ADDRESSES table
	addresses[antOwner][antId] = nil
	for controller, _ in pairs(ants[antId].Controllers) do
		addresses[controller][antId] = nil
	end
	ants[antId] = nil
end

---@param antId string
---@param ants ANTMap
---@return ACLMap
function utils.generateAffiliationsDelta(antId, ants)
	local aclMap = utils.affiliationsForAnt(antId, ants)
	for user, _ in pairs(aclMap) do
		-- remove ant from owned using filter approach
		local filteredOwned = {}
		for _, processId in ipairs(aclMap[user].Owned) do
			if processId ~= antId then
				table.insert(filteredOwned, processId)
			end
		end
		aclMap[user].Owned = filteredOwned

		-- remove ant from controllers using filter approach
		local filteredControlled = {}
		for _, processId in ipairs(aclMap[user].Controlled) do
			if processId ~= antId then
				table.insert(filteredControlled, processId)
			end
		end
		aclMap[user].Controlled = filteredControlled
	end
	return aclMap
end

-- Copied from https://github.com/ar-io/ar-io-network-process/blob/develop/src/utils.lua#L363
--- Safely decodes a JSON string
--- @param jsonString string|nil The JSON string to decode
--- @return table|nil decodedJson - the decoded JSON or nil if the string is nil or the decoding fails
function utils.safeDecodeJson(jsonString)
	if not jsonString then
		return nil
	end
	local status, result = pcall(json.decode, jsonString)
	if not status then
		return nil
	end
	return result
end
return utils

end

_G.package.loaded[".common.utils"] = _loaded_mod_common_utils()

-- module: ".common.main"
local function _loaded_mod_common_main()
local json = require(".common.json")
local utils = require(".common.utils")
local main = {}
-- just to ignore lint warnings
local ao = ao or {}

---@alias ACL { Owned: string[], Controlled: string[] }
---@alias ACLMap {[string]: ACL}
---@alias ANT { Owner: string, Controllers: {[string]: boolean} }
---@alias ANTMap {[string]: ANT}
---@alias AddressMap {[string]: {[string]: boolean}}
---@alias VersionMap {[string]: { messageId: string, moduleId: string, luaSourceId: string, notes: string }}

main.init = function()
	-- Example ANT structure
	-- ANTS["antId"] = {
	--     Owner = "userId",
	--     Controllers = {"userId1" = true, "userId2" = true},
	-- }
	---@type ANTMap
	ANTS = ANTS or {}

	-- Example ADDRESSES structure - maps a user address to a table keyed on ANT process IDs
	-- ADDRESSES["userAddress"] = {"antProcessId1" = true, "antProcessId2" = true}
	---@type AddressMap
	ADDRESSES = ADDRESSES or {}

	-- Example ANTVersions structure - maps a version number to a table with the messageId, moduleId, luaSourceId, and notes
	-- ANTVersions["1"] = { messageId = "messageId1", moduleId = "moduleId1", luaSourceId = "luaSourceId1", notes = "notes1" }
	---@type VersionMap
	ANTVersions = ANTVersions or {}

	local ActionMap = {
		Register = "Register",
		Unregister = "Unregister",
		BatchUnregister = "Batch-Unregister",
		StateNotice = "State-Notice",
		AccessControlList = "Access-Control-List",
		AddVersion = "Add-Version",
		RemoveVersion = "Remove-Version",
		GetVersions = "Get-Versions",
	}

	utils.createActionHandler(ActionMap.Register, function(msg)
		local antId = msg.Tags["Process-Id"]
		assert(type(antId) == "string", "Process-Id is required")

		ao.send({
			Target = antId,
			Action = "State",
		})
		ao.send({
			Target = msg.From,
			Action = "Register-Notice",
			["Message-Id"] = msg.Id,
		})
	end)

	utils.createActionHandler(ActionMap.Unregister, function(msg)
		local antId = msg.Tags["Process-Id"]
		assert(type(antId) == "string", "Process-Id is required")

		-- generate the acl here so we can path to the relevant addresses in the mappings
		local acl = utils.generateAffiliationsDelta(antId, ANTS)

		utils.unregisterAnt(msg.From, ANTS, antId, ADDRESSES)
		ao.send({
			Target = msg.From,
			Action = "Unregister-Notice",
			["Message-Id"] = msg.Id,
		})
		-- Send HyperBEAM patch message with updated ACL that has the ant removed
		-- only send if the acl is not empty, as we will nuke the entire ACL from the patch device if it is empty
		if #utils.keys(acl) > 0 then
			ao.send({
				device = "patch@1.0",
				cache = { acl = acl },
			})
		end
	end)

	utils.createActionHandler(ActionMap.BatchUnregister, function(msg)
		assert(msg.From == Owner, "Only ANT Registry owner can batch unregister")
		local antIds = utils.safeDecodeJson(msg.Data)
		assert(antIds, "msg.Data must be a valid JSON string")
		assert(
			type(antIds) == "table" and #antIds > 0,
			"msg.Data must be a table of ANT IDs, received " .. type(antIds)
		)
		assert(#antIds <= 1000, "msg.Data must be a table of less than or equal to 1000 ANT IDs")

		-- de-dupe and validate the antIds
		local antIdsToUnregister = {}
		--- At the end of the loop, if there are any errors, we will send a notice to the owner with the error
		--- messages for each antId that had an error.
		local errors = {}

		for _, antId in ipairs(antIds) do
			local normalizedAntId = tostring(antId)
			if not antIdsToUnregister[normalizedAntId] and not errors[normalizedAntId] then
				if not utils.validateArweaveId(normalizedAntId) then
					errors[normalizedAntId] = "Invalid antId: " .. tostring(normalizedAntId)
				elseif not ANTS[normalizedAntId] then
					errors[normalizedAntId] = "ANT " .. normalizedAntId .. " is not registered"
				else
					antIdsToUnregister[normalizedAntId] = true
				end
			end
		end

		--- for the patch device
		local patchAcl = {}

		for antId, _ in pairs(antIdsToUnregister) do
			-- generate the acl here so we can path to the relevant addresses in the mappings
			-- only apply to the patchAcl if unregister succeeds

			local deltaAcl = utils.generateAffiliationsDelta(antId, ANTS)

			--- the entire batch unregister from failing unnecessarily.
			utils.unregisterAnt(msg.From, ANTS, antId, ADDRESSES)

			-- unregister succeeded, so we apply the delta to the patchAcl
			for address, newAcl in pairs(deltaAcl) do
				patchAcl[address] = newAcl
			end
		end

		ao.send({
			Target = msg.From,
			Action = "Batch-Unregister-Notice",
			["Message-Id"] = msg.Id,
			Error = #utils.keys(errors) > 0 and "Batch unregister failed for " .. #utils.keys(errors) .. " ANTs" or nil,
			Data = json.encode({ errors = errors }),
		})

		--- we need to make sure that the patchAcl is not empty, other we will nuke the entire ACL from the patch device
		if #utils.keys(patchAcl) > 0 then
			-- Send HyperBEAM patch message with updated ACL that has the ant removed
			ao.send({
				device = "patch@1.0",
				cache = { acl = patchAcl },
			})
		end
	end)

	utils.createActionHandler(ActionMap.StateNotice, function(msg)
		local ant = utils.parseAntState(msg.Data)
		-- we pass in the reference as the state nonce
		local updateResult = utils.updateAffiliations(msg.From, ant, ADDRESSES, ANTS, tonumber(msg.Reference))
		local affiliatesToRemoveAntIdFrom = updateResult.affiliatesToRemoveAntIdFrom

		-- this may need to be batched for operation within limits of hyperbeam messages, specifically http header size
		local aclMap = utils.affiliationsForAnt(msg.From, ANTS)

		for _, affiliate in ipairs(affiliatesToRemoveAntIdFrom) do
			aclMap[affiliate] = utils.affiliationsForAddress(affiliate, ANTS)
			-- TODO: DELETE the ant from the affiliations on the address mapping. Currently do not know how to do this, or if its even possible with the current state of patch@1.0\
			-- this will set the mapping to { Owned: [], Controlled: [] } in the hb state

			-- aclMap[affiliate].Owned[utils.indexOf(aclMap[affiliate].Owned, msg.From)] = nil
			-- aclMap[affiliate].Controlled[utils.indexOf(aclMap[affiliate].Controlled, msg.From)] = nil
		end

		-- only send if the aclMap is not empty, as we will nuke the entire ACL from the patch device if it is empty
		if #utils.keys(aclMap) > 0 then
			ao.send({
				device = "patch@1.0",
				cache = { acl = aclMap },
			})
		end
	end)

	utils.createActionHandler(ActionMap.AccessControlList, function(msg)
		local address = msg.Tags["Address"]
		assert(type(address) == "string", "Address is required")

		-- Send the affiliations table
		ao.send({
			Target = msg.From,
			Action = "Access-Control-List-Notice",
			["Message-Id"] = msg.Id,
			Data = json.encode(utils.affiliationsForAddress(address, ANTS)),
		})
	end)

	utils.createActionHandler(ActionMap.AddVersion, function(msg)
		assert(msg.From == Owner, "Only ANT Registry owner can add versions")
		local version = tonumber(msg.Version)
		local moduleId = msg["Module-Id"]
		local luaSourceId = msg["Lua-Source-Id"]
		local notes = msg.Notes or ""
		local releaseTimestamp = tonumber(msg.Timestamp)

		assert(
			version ~= nil and math.type(version) == "integer" and version >= 0,
			"Version must be a positive integer, recieved " .. tostring(version)
		)
		utils.validateArweaveId(moduleId)
		assert(
			type(luaSourceId) == "string" and utils.validateArweaveId(luaSourceId) or luaSourceId == nil,
			"Lua-Source-Id should be a valid arweave ID"
		)
		assert(type(notes) == "string", "Notes must be a string")

		ANTVersions[tostring(version)] = {
			messageId = msg.Id,
			moduleId = moduleId,
			luaSourceId = luaSourceId,
			notes = notes,
			releaseTimestamp = releaseTimestamp,
		}

		ao.send({
			Target = msg.From,
			Action = "Add-Version-Notice",
			["Message-Id"] = msg.Id,
			Data = json.encode(ANTVersions),
		})
	end)

	utils.createActionHandler(ActionMap.RemoveVersion, function(msg)
		assert(msg.From == Owner, "Only ANT Registry owner can add versions")
		local version = tostring(msg.Version)

		assert(ANTVersions[version], "Version " .. version .. " does not exist")

		ANTVersions[version] = nil
		ao.send({
			Target = msg.From,
			Action = "Remove-Version-Notice",
			["Message-Id"] = msg.Id,
			Data = json.encode(ANTVersions),
		})
	end)

	utils.createActionHandler(ActionMap.GetVersions, function(msg)
		ao.send({
			Target = msg.From,
			Action = "Get-Versions-Notice",
			["Message-Id"] = msg.Id,
			Data = json.encode(ANTVersions),
		})
	end)
end

return main

end

_G.package.loaded[".common.main"] = _loaded_mod_common_main()

local entry = require(".common.main")

entry.init()
