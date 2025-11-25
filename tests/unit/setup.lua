-- Set up package paths for both source and test directories
package.path = './src/?.lua;./src/common/?.lua;./tests/unit/?.lua;' .. package.path

-- Set up essential mocks BEFORE loading globals (needed by src/globals.lua)
_G.ao = _G.ao or {}
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
	'dutch_auction',
	'english_auction',
	'fixed_price',
	'intents',
	'notices',
	'types',
	'ucm',
	'utils',
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
