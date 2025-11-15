-- Global state initialization
-- This file initializes all global state variables used by the marketplace process
-- It should be loaded first, before any other modules

-- Import type definitions from types.lua
require('types')

---@alias TokenId string Process ID of a token
---@alias OrderId string Unique identifier for an order
---@alias Address string Process ID or wallet address

-- Note: AuctionBidInfo is defined in types.lua

-- Global constants
---@type TokenId Process ID for ARIO token (CHANGEME in production)
ARIO_TOKEN_PROCESS_ID = ARIO_TOKEN_PROCESS_ID or 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

---@type Address Treasury address for fee collection
TREASURY_ADDRESS = TREASURY_ADDRESS or 'cqnFNTEDGuWOOpnrrdoQZ262Be8e_kGT2na-BlGFyks'

---@type Address Activity tracking process ID
ACTIVITY_PROCESS = ACTIVITY_PROCESS or '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'

-- Global state tables
---@type table<string, table<string, Pair>> Nested dictionary: Orderbook[dominantToken][swapToken] = Pair
--- All orders remain in Orderbook with a 'status' field ('active', 'executed', 'cancelled', etc.)
Orderbook = Orderbook or {}

---@type table<OrderId, {dominantToken: TokenId, swapToken: TokenId}> Dictionary mapping orderId to pair location
OrderIndex = OrderIndex or {}

---@type table<string, Intent> Dictionary mapping intentId to intent data
Intents = Intents or {}

-- Pruning schedule tracking
---@type table Pruning schedule configuration
Pruning = Pruning or {
	nextScheduledOrderbookPruning = nil, -- timestamp of next scheduled prune
}

-- Process metadata
---@type string Process name
Name = Name or 'ANT Marketplace'

---@type string|nil Process owner address
Owner = Owner or nil

-- Accrued fees tracking
---@type number Total accrued fees in mARIO
AccruedFeesAmount = AccruedFeesAmount or 0

return {
	-- Constants
	ARIO_TOKEN_PROCESS_ID = ARIO_TOKEN_PROCESS_ID,
	TREASURY_ADDRESS = TREASURY_ADDRESS,
	ACTIVITY_PROCESS = ACTIVITY_PROCESS,
	Name = Name,
}
