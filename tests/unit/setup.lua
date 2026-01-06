-- Set up package paths for both source and test directories
package.path = './src/?.lua;./src/common/?.lua;./tests/unit/?.lua;' .. package.path

-- Set up essential mocks BEFORE loading globals (needed by src/globals.lua)
_G.ao = _G.ao or {}
---@diagnostic disable-next-line: duplicate-set-field
_G.ao.send = function(_)
	return true
end
_G.ao.id = _G.ao.id or 'test-process'

-- Load source globals FIRST to initialize all state variables
print('Loading source globals...')
require('globals')
print('✓ Source globals loaded\n')

-- Load test globals for mocks and utilities
print('Loading test setup...')
require('test_globals')
print('✓ Test setup loaded and initialized\n')

-- Load luacov for code coverage tracking
print('Loading luacov for coverage tracking...')
local success, luacov = pcall(require, 'luacov')
if success then
	print('✓ luacov loaded successfully')
else
	print('✗ Failed to load luacov: ' .. tostring(luacov))
end

-- Force-load all source modules for coverage tracking
print('\nForce-loading modules for coverage...')
local modules_to_load = {
	'utils',  -- Load utils FIRST so we can mock it before other modules use it
	'types',
	'intents',
	'ucm',
	'dutch_auction',
	'english_auction',
	'fixed_price',
	'notices',
}

for _, module_name in ipairs(modules_to_load) do
	local load_success, result = pcall(require, module_name)
	if load_success then
		print('  ✓ Loaded: ' .. module_name)
		-- Add mocks to utils module after loading
		if module_name == 'utils' and type(result) == 'table' then
			result.isValidAddress = result.isValidAddress or function(address, allowUnsafe)
				-- Simple mock: just check if address is a string and non-empty
				if allowUnsafe then
					return type(address) == 'string' and #address > 0
				end
				return type(address) == 'string' and #address > 40
			end
			print('  ✓ Added isValidAddress mock to utils')

		-- Mock Send to track messages for test assertions (when utils.Send is called)
		local mockSend = function(_msg, data)
			-- Validate message first (use the real validator)
			if result.validateMessage then
				local validateSuccess, err = pcall(result.validateMessage, data)
				if not validateSuccess then
					error(err)
				end
			end

				-- Track the message in global array
				-- Create a copy of data with all fields preserved
				local trackedMsg = {
					Target = data.Target,
					Action = data.Action,
					Data = data.Data or '',
				}

				-- Copy all other fields (including tag-like fields)
				for k, v in pairs(data) do
					if k ~= 'Target' and k ~= 'Action' and k ~= 'Data' and k ~= 'Tags' then
						trackedMsg[k] = v
					end
				end

				-- If Tags exists, copy it
				if data.Tags then
					trackedMsg.Tags = {}
					for k, v in pairs(data.Tags) do
						trackedMsg.Tags[k] = v
					end
				end

				table.insert(_G.sentMessages, trackedMsg)

				-- Call ao.send if it exists (for tests that mock it)
				if _G.ao and _G.ao.send then
					_G.ao.send(data)
				end

				return data
			end

			-- Mock deferredSend to immediately send in unit tests
			-- This is necessary because unit tests call handlers directly (not through createHandler wrapper)
			-- so onAfterHandler (which flushes deferred sends) never gets called
			local mockDeferredSend = function(msg, sendParams)
				return mockSend(msg, sendParams)
			end

			-- Apply mocks to both the module return value and global utils
			result.Send = mockSend
			result.deferredSend = mockDeferredSend
			if _G.utils then
				_G.utils.Send = mockSend
				_G.utils.deferredSend = mockDeferredSend
			end

			print('  ✓ Added Send and deferredSend mocks to utils')
		end
	else
		print('  ✗ Failed to load: ' .. module_name .. ' - ' .. tostring(result))
	end
end
print('✓ All modules loaded for coverage tracking\n')

-- Add a test completion handler
local busted = require('busted')
busted.subscribe({ 'suite', 'end' }, function()
	print('\n=== All tests completed ===')
	print('Coverage data will be written to: coverage/luacov.stats.out')
	print("Run 'luacov' to generate the coverage report")
end)
