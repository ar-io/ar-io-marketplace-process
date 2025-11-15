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

return {
	-- Utility function to reset global state between tests
	resetState = function()
		_G.Orderbook = {}
		_G.OrderIndex = {}
		_G.Intents = {}
		_G.Pruning = { nextScheduledOrderbookPruning = nil }
		_G.AccruedFeesAmount = 0
	end,

	-- Utility to reset ARIO token ID (useful if tests need different values)
	setArioTokenId = function(tokenId)
		_G.ARIO_TOKEN_PROCESS_ID = tokenId
	end,
}
