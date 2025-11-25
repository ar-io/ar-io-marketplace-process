-- Test-specific globals setup
-- This file sets up mocks and utilities for testing
-- The actual state variables are initialized in src/globals.lua

print('Setting up test mocks and utilities...')

-- Mock ao.send for testing
_G.ao = _G.ao or {}
_G.ao.send = function(_)
	return true
end
_G.ao.id = _G.ao.id or 'test-process'

-- Mock Handlers
_G.Handlers = _G.Handlers or {}
_G.Handlers.add = _G.Handlers.add or function() end
_G.Handlers.prepend = _G.Handlers.prepend or function() end
_G.Handlers.utils = _G.Handlers.utils or {}
_G.Handlers.utils.reply = function()
	return true
end
_G.Handlers.utils.hasMatchingTag = function(tagName, tagValue)
	return function(msg)
		return msg.Tags and msg.Tags[tagName] == tagValue
	end
end

print('✓ Test mocks created (ao, Handlers)')

-- Mock utils functions that are needed for testing
_G.utils = _G.utils or {}
_G.utils.isValidAddress = _G.utils.isValidAddress or function(address, allowUnsafe)
	-- Simple mock: just check if address is a string and non-empty
	if allowUnsafe then
		return type(address) == 'string' and #address > 0
	end
	return type(address) == 'string' and #address > 40
end

-- Track sent messages for assertions
_G.sentMessages = {}

return {
	-- Utility function to reset global state between tests
	resetState = function()
		_G.Orderbook = {}
		_G.OrderIndex = {}
		_G.Intents = {}
		_G.Pruning = { nextScheduledOrderbookPruning = nil, nextScheduledIntentsPruning = nil }
		_G.AccruedFeesAmount = '0'
		_G.ARIOBalances = {}
		_G.IntentCounter = "0"
		_G.sentMessages = {}
	end,

	-- Utility to reset ARIO token ID (useful if tests need different values)
	setArioTokenId = function(tokenId)
		_G.ARIO_TOKEN_PROCESS_ID = tokenId
	end,

	-- Utility to create mock messages
	mockMsg = function(overrides)
		local msg = {
			Id = 'test-msg-123',
			From = 'test-sender',
			Timestamp = 1000,
			['Block-Height'] = 100,
			Owner = 'test-owner',
			Tags = {},
			Data = '',
		}
		
		-- Merge overrides
		if overrides then
			for k, v in pairs(overrides) do
				if k == 'Tags' and type(v) == 'table' then
					for tk, tv in pairs(v) do
						msg.Tags[tk] = tv
					end
				else
					msg[k] = v
				end
			end
		end
		
		return msg
	end,

	-- Expose sent messages for test assertions
	sentMessages = _G.sentMessages,
}
