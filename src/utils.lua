local json = require('json')
local bint = require('.bint')(256)
local crypto = require('crypto')
local constants = require('constants')

local utils = {}

--- Add forwarded tags (X-* tags) from one message to another
--- @param oldMsg table The source message
--- @param newMsg table The destination message
--- @return table newMsg The destination message with forwarded tags
function utils.addForwardedTags(oldMsg, newMsg)
	if oldMsg.Cast then
		return newMsg
	end
	for tagName, tagValue in pairs(oldMsg) do
		-- Tags beginning with "X-" are forwarded
		if string.sub(tagName, 1, 2) == 'X-' then
			newMsg[tagName] = tagValue
		end
	end
	return newMsg
end

--- Get all keys from a table
--- @param t table The table to get keys from
--- @return table keys Array of keys
function utils.keys(t)
	assert(type(t) == 'table', 'argument needs to be a table')
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	return keys
end

--- Validate an intent ID format
--- @param intentId string The intent ID to validate
--- @return boolean valid Whether the intent ID is valid
function utils.isValidIntentId(intentId)
	if not intentId or type(intentId) ~= 'string' then
		return false
	end
	
	-- Intent IDs should be non-empty strings containing only digits
	if intentId == '' then
		return false
	end
	
	-- Check if it's a valid string integer (only digits)
	return intentId:match('^%d+$') ~= nil
end

--- Converts a string to camelCase
--- @param str string The string to convert
--- @return string camelCaseString The camelCase string
function utils.camelCase(str)
	-- Remove any leading or trailing spaces
	str = string.gsub(str, '^%s*(.-)%s*$', '%1')
	-- Convert PascalCase to camelCase
	str = string.gsub(str, '^%u', string.lower)
	-- Handle kebab-case, snake_case, and space-separated words
	str = string.gsub(str, '[-_%s](%w)', function(s)
		return string.upper(s)
	end)
	return str
end

--- Error handler for xpcall
--- @param err any The error
--- @return string stackTrace The error with stack trace
function utils.errorHandler(err)
	return debug.traceback(err)
end

--- Checks if an address is a valid Arweave address
--- @param address string The address to check
--- @return boolean isValid Whether the address is valid
function utils.isValidArweaveAddress(address)
	return type(address) == 'string'
		and #address == constants.ADDRESS.ARWEAVE_LENGTH
		and string.match(address, '^[%w-_]+$') ~= nil
end

--- Checks if an address is a valid Ethereum address
--- @param address string The address to check
--- @return boolean isValid Whether the address is valid
function utils.isValidEthAddress(address)
	return type(address) == 'string'
		and #address == constants.ADDRESS.ETHEREUM_LENGTH
		and string.match(address, '^' .. constants.ADDRESS.ETHEREUM_PREFIX .. '[%x]+$') ~= nil
end

--- Checks if an address is a valid unsafe address (less strict validation)
--- @param address string The address to check
--- @return boolean isValid Whether the address is valid
function utils.isValidUnsafeAddress(address)
	if not address then
		return false
	end
	local match = string.match(address, '^[%w_-]+$')
	return match ~= nil
		and #address >= constants.ADDRESS.UNSAFE_MIN_LENGTH
		and #address <= constants.ADDRESS.UNSAFE_MAX_LENGTH
end

--- Checks if an address is a valid AO address (Arweave or Ethereum)
--- @param address string|nil The address to check
--- @param allowUnsafe boolean|nil Whether to allow unsafe addresses
--- @return boolean isValid Whether the address is valid
function utils.isValidAOAddress(address, allowUnsafe)
	allowUnsafe = allowUnsafe or false
	if not address then
		return false
	end
	if allowUnsafe then
		return utils.isValidUnsafeAddress(address)
	end
	return utils.isValidArweaveAddress(address) or utils.isValidEthAddress(address)
end

--- Converts an Ethereum address to EIP-55 checksum format
--- @param address string The Ethereum address to format
--- @return string formattedAddress The EIP-55 formatted address
function utils.formatEIP55Address(address)
	local hex = string.lower(string.sub(address, 3))
	local hash = crypto.digest.keccak256(hex)
	local hashHex = hash.asHex()
	local checksumAddress = '0x'

	for i = 1, #hashHex do
		local hexChar = string.sub(hashHex, i, i)
		local hexCharValue = tonumber(hexChar, 16)
		local char = string.sub(hex, i, i)
		if hexCharValue > 7 then
			char = string.upper(char)
		end
		checksumAddress = checksumAddress .. char
	end

	return checksumAddress
end

--- Formats an address to EIP-55 checksum format if Ethereum, otherwise returns as-is
--- @param address string The address to format
--- @return string formattedAddress The formatted address
function utils.formatAddress(address)
	if utils.isValidEthAddress(address) then
		return utils.formatEIP55Address(address)
	end
	return address
end

--- Validates a message structure
--- @param msg table The message to validate
function utils.validateMessage(msg)
	local ignoredKeys = {
		Tags = true,
		reply = true,
		forward = true,
		Data = true,
	}

	for k, v in pairs(msg) do
		if not ignoredKeys[k] then
			assert(type(k) == 'string', string.format('Key %s must be a string', k))
			assert(type(v) == 'string', string.format('Value %s must be a string', v))
		end
	end

	if msg.Tags then
		for k, v in pairs(msg.Tags) do
			assert(type(k) == 'string', string.format('Key %s must be a string', k))
			assert(type(v) == 'string', string.format('Value %s must be a string', v))
		end
	end
end

--- Splits a string by a delimiter
--- @param input string The string to split
--- @param delimiter string|nil The delimiter, defaults to ","
--- @return table parts The split string parts
function utils.splitString(input, delimiter)
	delimiter = delimiter or ','
	local result = {}
	for token in (input or ''):gmatch(string.format('([^%s]+)', delimiter)) do
		table.insert(result, token)
	end
	return result
end

--- Checks if an address is valid (Arweave length and format)
--- @param address string|nil The address to check
--- @return boolean isValid Whether the address is valid
function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == constants.ADDRESS.ARWEAVE_LENGTH
end

--- Checks if an amount is valid (greater than 0)
--- @param data string|number The amount to check
--- @return boolean isValid Whether the amount is valid
function utils.checkValidAmount(data)
	return bint(data) > bint(0)
end

--- Checks if a token address is the ARIO token
--- @param tokenAddress string The token address to check
--- @return boolean isArioToken Whether the token is ARIO
function utils.isArioToken(tokenAddress)
	return tokenAddress == ARIO_TOKEN_PROCESS_ID
end

--- Validates that at least one token in a trade is ARIO
--- @param dominantToken string The dominant token address
--- @param swapToken string The swap token address
--- @return boolean isValid Whether the trade includes ARIO
--- @return string|nil error The error message if invalid
function utils.validateArioInTrade(dominantToken, swapToken)
	-- At least one of the tokens in the trade must be ARIO
	if dominantToken == ARIO_TOKEN_PROCESS_ID or swapToken == ARIO_TOKEN_PROCESS_ID then
		return true, nil
	end
	return false, 'At least one token in the trade must be ARIO'
end

--- Decodes JSON message data
--- @param data string The JSON string to decode
--- @return boolean success Whether decoding was successful
--- @return table|nil decodedData The decoded data or nil if failed
function utils.decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

--- Validates a trading pair (two token addresses)
--- @param data table The pair data to validate
--- @return table|nil pairData The validated pair data
--- @return string|nil error The error message if invalid
function utils.validatePairData(data)
	if type(data) ~= 'table' or #data ~= 2 then
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		return nil, 'Both pair elements must be strings'
	end

	if not utils.checkValidAddress(data[1]) or not utils.checkValidAddress(data[2]) then
		return nil, 'Both pair elements must be valid addresses'
	end

	if data[1] == data[2] then
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

--- Calculates the send amount after applying fees
--- @param amount string|number The original amount
--- @return string sendAmount The amount to send (after fee deduction)
function utils.calculateSendAmount(amount)
	local factor = bint(constants.FEE.FACTOR_NUMERATOR)
	local divisor = bint(constants.FEE.FACTOR_DENOMINATOR)
	local sendAmount = (bint(amount) * factor) // divisor
	return tostring(sendAmount)
end

--- Calculates the fee amount from an original amount
--- @param amount string|number The original amount
--- @return string feeAmount The fee amount
function utils.calculateFeeAmount(amount)
	local factor = bint(constants.FEE.AMOUNT_NUMERATOR)
	local divisor = bint(constants.FEE.AMOUNT_DENOMINATOR)
	local feeAmount = (bint(amount) * factor) // divisor
	return tostring(feeAmount)
end

--- Calculates the fill amount by flooring the value
--- @param amount string|number The amount to calculate
--- @return string fillAmount The floored fill amount as string
function utils.calculateFillAmount(amount)
	-- Convert to string first (handles bint objects), then to number
	return tostring(math.floor(tonumber(tostring(amount)) or 0))
end

--- Send wrapper for ao.send/msg.reply
--- @param msg Message The original message context
--- @param sendParams SendParams The parameters to pass to ao.send
--- Note: For transfers with intent tracking, use ucm.transfer instead
function utils.Send(msg, sendParams)
	-- Validate message structure
	utils.validateMessage(sendParams)

	-- Use msg.reply if available, otherwise use ao.send
	-- Reference: https://github.com/permaweb/aos/blob/main/blueprints/patch-legacy-reply.lua
	if msg.reply then
		msg.reply(sendParams)
	else
		ao.send(sendParams)
	end
end

--- Checks if an expiration time is valid
--- @param expirationTime string|number|nil The expiration timestamp
--- @param timestamp string|number The current timestamp
--- @return boolean isValid Whether the expiration time is valid
--- @return string|nil error The error message if invalid
function utils.checkValidExpirationTime(expirationTime, timestamp)
	-- If expiration time is nil, return true
	if not expirationTime then
		return true, nil
	end

	-- Check if expiration time is a valid positive integer
	expirationTime = tonumber(expirationTime)
	if not expirationTime or not utils.checkValidAmount(expirationTime) then
		return false, 'Expiration time must be a valid positive integer'
	end

	-- Check if expiration time is greater than current timestamp
	local status, result = pcall(function()
		return bint(expirationTime) <= bint(timestamp)
	end)

	if not status then
		return false, 'Expiration time must be a valid timestamp'
	end

	if result then
		return false, 'Expiration time must be greater than current timestamp'
	end

	return true, nil
end

--- Check if an expiration time has passed
--- @param expirationTime string|number|nil The expiration timestamp
--- @param currentTimestamp string|number The current timestamp
--- @return boolean isExpired Whether the expiration time has passed
function utils.isExpired(expirationTime, currentTimestamp)
	if not expirationTime then
		return false
	end
	return expirationTime < currentTimestamp
end

--- Handles errors by refunding tokens and sending error notice
--- @param args {target: string, action: string, message: string, transferToken: string?, quantity: string?, orderGroupId: string?, msg: table?} Error handling parameters
function utils.handleError(args) -- target, transferToken, quantity, msg
	-- If there is a valid quantity then return the funds
	local msg = args.msg or { Tags = {} }
	if args.transferToken and args.quantity and utils.checkValidAmount(args.quantity) then
		local ucm = require('ucm')
		ucm.transfer(args.target, tostring(args.quantity), args.transferToken, msg)
	end
	utils.Send(msg, {
		Target = args.target,
		Action = args.action,
		Error = args.message,
		Tags = { Status = 'Error', Message = args.message, ['X-Group-ID'] = args.orderGroupId },
	})
end

--- Helper function to refund deposits on validation failures
--- Sends refund and error message, then throws error to stop execution
--- @param msg table The original message
--- @param sender string The sender address to refund to
--- @param message string The error message
--- @param action string|nil The action type (defaults to 'Validation-Error')
function utils.refundAndError(msg, sender, message, action)
	utils.handleError({
		target = sender,
		action = action or 'Validation-Error',
		message = message,
		quantity = msg.Tags.Quantity,
		transferToken = msg.From,
		orderGroupId = msg.Tags['X-Group-ID'] or 'None',
		msg = msg,
	})
	-- Throw error to stop execution (will be caught by pcall wrapper)
	error(message)
end

--- Parses the pagination tags from a message
--- @param msg Message The message provided to a handler (see ao docs for more info)
--- @return PaginationTags paginationTags The pagination tags
function utils.parsePaginationTags(msg)
	local cursor = msg.Tags.Cursor
	local limit = tonumber(msg.Tags['Limit']) or constants.PAGINATION.DEFAULT_LIMIT
	assert(
		limit <= constants.PAGINATION.MAX_LIMIT,
		'Limit must be less than or equal to ' .. constants.PAGINATION.MAX_LIMIT
	)
	local sortOrder = msg.Tags['Sort-Order'] and string.lower(msg.Tags['Sort-Order'])
		or constants.PAGINATION.DEFAULT_SORT_ORDER
	assert(sortOrder == 'asc' or sortOrder == 'desc', "Invalid sortOrder: expected 'asc' or 'desc'")
	local sortBy = msg.Tags['Sort-By']
	local filters = utils.safeDecodeJson(msg.Tags.Filters)
	assert(msg.Tags.Filters == nil or filters ~= nil, 'Invalid JSON supplied in Filters tag')
	return {
		cursor = cursor,
		limit = limit,
		sortBy = sortBy,
		sortOrder = sortOrder,
		filters = filters,
	}
end

--- Parses the Ids tag from a message and returns a set for efficient lookup
--- @param idsParam string|nil JSON array string of IDs (e.g., '["id1", "id2"]')
--- @return table|nil idsSet A table with IDs as keys (set to true) for quick lookup, or nil if input is nil/invalid
function utils.parseIdsFilter(idsParam)
	if not idsParam then
		return nil
	end
	
	local idsArray = utils.safeDecodeJson(idsParam)
	if not idsArray or type(idsArray) ~= 'table' then
		return nil
	end
	
	-- Convert array to set for O(1) lookups
	local idsSet = {}
	for _, id in ipairs(idsArray) do
		if type(id) == 'string' then
			idsSet[id] = true
		end
	end
	
	return idsSet
end

--- Paginate a table with a cursor
--- @param tableArray table The table to paginate
--- @param cursor string|nil The cursor to paginate from (optional)
--- @param cursorField string|nil The field to use as the cursor or nil for lists of primitives
--- @param limit number The limit of items to return
--- @param sortBy string|nil The field to sort by. Nil if sorting by the primitive items themselves.
--- @param sortOrder "asc"|"desc" The order to sort by
--- @param filters table|nil Optional filter table
--- @return PaginatedTable paginatedTable The paginated table result
function utils.paginateTableWithCursor(tableArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
	local filterFn = nil
	if type(filters) == 'table' then
		filterFn = utils.createFilterFunction(filters)
	end

	local filteredArray = filterFn
			and utils.filterArray(tableArray, function(_, value)
				return filterFn(value)
			end)
		or tableArray

	assert(sortOrder == 'asc' or sortOrder == 'desc', "Invalid sortOrder: expected 'asc' or 'desc'")

	-- Default to sorting by CreatedAt if no sortBy is specified
	if not sortBy then
		sortBy = constants.PAGINATION.DEFAULT_SORT_BY
	end

	local sortFields = { { order = sortOrder, field = sortBy } }
	if cursorField ~= nil and cursorField ~= sortBy then
		-- Tie-breaker to guarantee deterministic pagination
		table.insert(sortFields, { order = 'asc', field = cursorField })
	end
	local sortedArray = utils.sortTableByFields(filteredArray, sortFields)

	if not sortedArray or #sortedArray == 0 then
		return {
			items = {},
			limit = limit,
			totalItems = 0,
			sortBy = sortBy,
			sortOrder = sortOrder,
			nextCursor = nil,
			hasMore = false,
		}
	end

	local startIndex = 1

	if cursor then
		-- Advance using consistent cursor field
		local cursorKey = cursorField or sortBy or 'CreatedAt'
		local lastIndex = nil
		for i, obj in ipairs(sortedArray) do
			local value = cursorKey and obj[cursorKey] or obj
			if tostring(value) == tostring(cursor) then
				lastIndex = i
			end
		end
		if lastIndex then
			startIndex = lastIndex + 1
		end
	end

	local items = {}
	local endIndex = math.min(startIndex + limit - 1, #sortedArray)

	for i = startIndex, endIndex do
		table.insert(items, sortedArray[i])
	end

	local nextCursor = nil
	if endIndex < #sortedArray then
		local cursorKey = cursorField or sortBy or 'CreatedAt'
		nextCursor = tostring(sortedArray[endIndex][cursorKey])
	end

	return {
		items = items,
		limit = limit,
		totalItems = #sortedArray,
		sortBy = sortBy,
		sortOrder = sortOrder,
		nextCursor = nextCursor, -- the last item in the current page
		hasMore = nextCursor ~= nil,
	}
end

--- Creates a lookup table from an array or table
--- @param tbl table The table to create lookup from
--- @param valueFn function|nil Optional function to transform values (defaults to returning true)
--- @return table lookupTable The lookup table with keys from input and values from valueFn
function utils.createLookupTable(tbl, valueFn)
	local lookupTable = {}
	valueFn = valueFn or function()
		return true
	end
	for key, value in pairs(tbl or {}) do
		lookupTable[value] = valueFn(key, value)
	end
	return lookupTable
end

--- Deep copies a table with optional exclusion of specified fields, including nested fields
--- Preserves proper sequential ordering of array tables when some of the excluded nested keys are array indexes
--- @generic T: table|nil
--- @param original T The table to copy
--- @param excludedFields table|nil An array of keys or dot-separated key paths to exclude from the deep copy
--- @return T The deep copy of the table or nil if the original is nil
function utils.deepCopy(original, excludedFields)
	if not original then
		return nil
	end

	if type(original) ~= 'table' then
		return original
	end

	-- Fast path: If no excluded fields, copy directly
	if not excludedFields or #excludedFields == 0 then
		local copy = {}
		for key, value in pairs(original) do
			if type(value) == 'table' then
				copy[key] = utils.deepCopy(value) -- Recursive copy for nested tables
			else
				copy[key] = value
			end
		end
		return copy
	end

	-- If excludes are provided, create a lookup table for excluded fields
	local excluded = utils.createLookupTable(excludedFields)

	-- Helper function to check if a key path is excluded
	local function isExcluded(keyPath)
		for excludedKey in pairs(excluded) do
			if keyPath == excludedKey or keyPath:match('^' .. excludedKey .. '%.') then
				return true
			end
		end
		return false
	end

	-- Recursive function to deep copy with nested field exclusion
	local function deepCopyHelper(orig, path)
		if type(orig) ~= 'table' then
			return orig
		end

		local result = {}
		local isArray = true

		-- Check if all keys are numeric and sequential
		for key in pairs(orig) do
			if type(key) ~= 'number' or key % 1 ~= 0 then
				isArray = false
				break
			end
		end

		if isArray then
			-- Collect numeric keys in sorted order for sequential reindexing
			local numericKeys = {}
			for key in pairs(orig) do
				table.insert(numericKeys, key)
			end
			table.sort(numericKeys)

			local index = 1
			for _, key in ipairs(numericKeys) do
				local keyPath = path and (path .. '.' .. key) or tostring(key)
				if not isExcluded(keyPath) then
					result[index] = deepCopyHelper(orig[key], keyPath) -- Sequentially reindex
					index = index + 1
				end
			end
		else
			-- Handle non-array tables (dictionaries)
			for key, value in pairs(orig) do
				local keyPath = path and (path .. '.' .. key) or key
				if not isExcluded(keyPath) then
					result[key] = deepCopyHelper(value, keyPath)
				end
			end
		end

		return result
	end

	-- Use the exclusion-aware deep copy helper
	return deepCopyHelper(original, nil)
end

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

--- Sorts a table by multiple fields with specified orders for each field.
--- Supports tables of non-table values by using `nil` as a field name.
--- Each field is provided as a table with 'field' (string|nil) and 'order' ("asc" or "desc").
--- Supports nested fields using dot notation.
--- @param prevTable table The table to sort
--- @param fields table A list of fields with order specified, e.g., { { field = "name", order = "asc" } }
--- @return table sortedTable - the sorted table
function utils.sortTableByFields(prevTable, fields)
	-- Handle sorting for non-table values with possible nils
	if fields[1].field == nil then
		-- Separate non-nil values and count nil values
		local nonNilValues = {}
		local nilValuesCount = 0

		for _, value in pairs(prevTable) do -- Use pairs instead of ipairs to include all elements
			if value == nil then
				nilValuesCount = nilValuesCount + 1
			else
				table.insert(nonNilValues, value)
			end
		end

		-- Sort non-nil values
		table.sort(nonNilValues, function(a, b)
			if fields[1].order == 'asc' then
				return a < b
			else
				return a > b
			end
		end)

		-- Append nil values to the end
		for _ = 1, nilValuesCount do
			table.insert(nonNilValues, nil)
		end

		return nonNilValues
	end

	-- Deep copy for sorting complex nested values
	local tableCopy = utils.deepCopy(prevTable) or {}

	-- If no elements or no fields, return the copied table as-is
	if #tableCopy == 0 or #fields == 0 then
		return tableCopy
	end

	-- Helper function to retrieve a nested field value by path
	local function getNestedValue(tbl, fieldPath)
		local current = tbl
		for segment in fieldPath:gmatch('[^.]+') do
			if type(current) == 'table' then
				current = current[segment]
			else
				return nil
			end
		end
		return current
	end

	-- Sort table using table.sort with multiple fields and specified orders
	table.sort(tableCopy, function(a, b)
		for _, fieldSpec in ipairs(fields) do
			local fieldPath = fieldSpec.field
			local order = fieldSpec.order
			local aField, bField

			-- Check if field is nil, treating a and b as simple values
			if fieldPath == nil then
				aField = a
				bField = b
			else
				aField = getNestedValue(a, fieldPath)
				bField = getNestedValue(b, fieldPath)
			end

			-- Validate order
			if order ~= 'asc' and order ~= 'desc' then
				error("Invalid sort order. Expected 'asc' or 'desc'")
			end

			-- Handle nil values to ensure they go to the end
			if aField == nil and bField ~= nil then
				return false
			elseif aField ~= nil and bField == nil then
				return true
			elseif aField ~= nil and bField ~= nil then
				-- Compare based on the specified order
				if aField ~= bField then
					if order == 'asc' then
						return aField < bField
					else
						return aField > bField
					end
				end
			end
		end
		-- All fields are equal
		return false
	end)

	return tableCopy
end

--- Creates a filter function from a filter object
--- @param filters table The filter object with field-value pairs
--- @return function filterFn - the filter function
function utils.createFilterFunction(filters)
	return function(item)
		for key, value in pairs(filters) do
			if item[key] ~= value then
				return false
			end
		end
		return true
	end
end

--- Filters an array using a custom filter function
--- @param array table The array to filter
--- @param filterFn function The filter function that takes index and value, returns boolean
--- @return table filteredArray - the filtered array
function utils.filterArray(array, filterFn)
	local result = {}
	for i, item in ipairs(array) do
		if filterFn(i, item) then
			table.insert(result, item)
		end
	end
	return result
end

--- Sends fee amount to treasury address
--- @param originalAmount string|number The original amount before fees
--- @param calculatedAmount string|number The calculated amount after fees
--- @param feeToken string The token process ID for the fee
--- @param msg table|nil The message context (optional)
function utils.sendFeeToTreasury(originalAmount, calculatedAmount, feeToken, msg)
	if not TREASURY_ADDRESS then
		return
	end

	local feeAmount = bint(originalAmount) - bint(calculatedAmount)

	if feeAmount > bint(0) then
		local msgContext = msg or { Tags = {} }
		local ucm = require('ucm')
		ucm.transfer(TREASURY_ADDRESS, tostring(feeAmount), feeToken, msgContext)
	end
end

--- Pre-process handler execution - formats addresses
---
--- This function is called BEFORE every handler executes. It's separated from the
--- handler wrapper to allow hot-reloading: by requiring this function dynamically
--- at execution time, we can update the pre-processing logic without remounting handlers.
---
--- Current responsibilities:
--- - Format Ethereum addresses to EIP-55 checksum format
--- - Format known address tags (Recipient, etc.)
--- - Normalize address formats across Arweave and Ethereum ecosystems
---
--- Design note: This function mutates the msg object in-place for performance.
--- It does not return a value as the msg object is modified directly.
---
--- @param msg Message The incoming message
function utils.onBeforeHandler(msg)
	-- Format addresses using EIP-55 format for Ethereum compatibility
	-- Arweave addresses pass through unchanged
	msg.From = utils.formatAddress(msg.From)

	-- List of known tags that contain addresses
	-- Add to this list as new address-containing tags are identified
	local knownAddressTags = {
		'Recipient',
	}

	for _, tName in ipairs(knownAddressTags) do
		-- Format all incoming addresses in tags
		msg.Tags[tName] = msg.Tags[tName] and utils.formatAddress(msg.Tags[tName]) or nil
		-- aos assigns tag values to the base message level as well, so format there too
		msg[tName] = msg[tName] and utils.formatAddress(msg[tName]) or nil
	end

	-- Normalize timestamp to ensure it's always a number
	if msg.Timestamp then
		msg.Timestamp = tonumber(msg.Timestamp) or msg.Timestamp
	end

	-- Prune expired orders from the orderbook (and auto-settle auctions)
	-- The pruning function handles its own scheduling checks
	local ucm = require('ucm')
	ucm.pruneOrderbook(msg.Timestamp, msg)
end

--- Post-process handler execution - sends notices
---
--- This function is called AFTER every handler executes. Like onBeforeHandler, it's
--- separated to allow hot-reloading of post-processing logic without remounting handlers.
---
--- Current responsibilities:
--- - Send error notices when handlers fail (xpcall caught an error)
--- - Send success notices when handlers return results
--- - Forward tags from the original message to responses (X-Intent-Id, etc.)
---
--- Design note: This function handles both success and failure cases uniformly,
--- providing a consistent response format across all handlers. The handler result
--- is passed through to allow for potential chaining or additional processing.
---
--- Future considerations: This is where you'd add:
--- - Metrics/logging for handler execution
--- - State change notifications (if needed)
--- - Rate limiting or throttling logic
--- - Custom response transformations
---
--- @param msg Message The incoming message
--- @param tagValue string The action/tag value for the handler (e.g., "Create-Order")
--- @param handlerStatus boolean Whether handler executed successfully (from xpcall)
--- @param handlerRes any The result from the handler (error message if failed, return value if succeeded)
--- @return any handlerRes The handler result (passed through for potential chaining)
function utils.onAfterHandler(msg, tagValue, handlerStatus, handlerRes)
	local resultNotice = nil

	if not handlerStatus then
		-- Handler threw an error - handlerRes contains the error message with stack trace
		-- Send an Invalid-{Action}-Notice with the error details
		resultNotice = utils.addForwardedTags(msg, {
			Target = msg.From,
			Action = 'Invalid-' .. tagValue .. '-Notice',
			Error = tagValue .. '-Error',
			['Message-Id'] = msg.Id,
			Data = handlerRes, -- Error message from xpcall
		})
	elseif handlerRes then
		-- Handler succeeded and returned a result
		-- Send a {Action}-Notice with the result data
		resultNotice = utils.addForwardedTags(msg, {
			Target = msg.From,
			Action = tagValue .. '-Notice',
			Data = type(handlerRes) == 'string' and handlerRes or json.encode(handlerRes),
		})
	end
	-- If handlerRes is nil/false, no notice is sent (silent success)

	if resultNotice then
		utils.Send(msg, resultNotice)
	end

	return handlerRes
end

--- Creates a handler for a specific tag with pre/post processing
---
--- This is the core of our hot-reloadable handler wrapper system. It wraps user-defined
--- handler functions with standardized pre/post processing while allowing that processing
--- logic to be updated at runtime without remounting handlers.
---
--- HOW IT WORKS:
--- 1. The handler is mounted ONCE when this function is called (during process initialization)
--- 2. On EVERY message, the wrapper function executes and dynamically requires 'utils'
--- 3. This dynamic require pulls the LATEST version of onBeforeHandler/onAfterHandler
--- 4. To update handler behavior, simply reload the utils module: package.loaded['utils'] = nil
---
--- WHY THIS PATTERN:
--- - Long-running AO processes need to update logic without redeploying
--- - Handlers.add() is expensive and mounts persist in the Handlers.list
--- - Remounting handlers creates duplicate entries and ordering issues
--- - Dynamic require at execution time bypasses Lua's module caching for the wrapper
---
--- TRADEOFFS:
--- - Small performance cost: require() call on every message (minimal, Lua caches modules)
--- - Slight memory cost: uses _utils to avoid shadowing the outer utils variable
--- - Big benefit: Can fix bugs, add features, or change behavior without process restart
---
--- USAGE PATTERN:
--- ```lua
--- utils.createHandler("Action", "Create-Order", function(msg)
---   -- Your handler logic here
---   return { orderId = "123" }
--- end)
--- ```
---
--- HOT-RELOAD PATTERN:
--- ```lua
--- -- In aos console or via message
--- package.loaded['utils'] = nil
--- utils = require('utils')
--- -- Next message will use updated onBeforeHandler/onAfterHandler
--- ```
---
--- @param tagName string The tag name to match (e.g., "Action")
--- @param tagValue string The tag value to match (e.g., "Create-Order")
--- @param handler function The handler function to execute
--- @param position "add" | "prepend" | "append" | nil Where to add the handler in Handlers.list
--- @example
--- ```lua
--- utils.createHandler("Action", "Info", function(msg)
---   return { Name = "Marketplace" }
--- end)
--- ```
function utils.createHandler(tagName, tagValue, handler, position)
	assert(type(position) == 'string' or type(position) == 'nil', 'Position must be a string or nil')
	assert(
		position == nil or position == 'add' or position == 'prepend' or position == 'append',
		"Position must be one of 'add', 'prepend', 'append'"
	)

	return Handlers[position or 'add'](
		utils.camelCase(tagValue),
		Handlers.utils.continue(Handlers.utils.hasMatchingTag(tagName, tagValue)),
		function(msg)
			-- CRITICAL: Dynamically require at execution time to allow hot-reloading
			-- This pulls the LATEST version of onBeforeHandler/onAfterHandler each time
			-- Use _utils to avoid shadowing the outer 'utils' variable
			local _utils = require('utils')

			-- Pre-process: format addresses, normalize input
			-- This call uses the dynamically-loaded version, so updates apply immediately
			_utils.onBeforeHandler(msg)

			-- Execute the user-defined handler with error handling
			-- xpcall catches errors and provides stack traces via errorHandler
			local handlerStatus, handlerRes = xpcall(function()
				return handler(msg)
			end, _utils.errorHandler)

			-- Post-process: send success/error notices
			-- Like onBeforeHandler, this uses the dynamically-loaded version
			return _utils.onAfterHandler(msg, tagValue, handlerStatus, handlerRes)
		end
	)
end

return utils
