-- Global state initialization
-- This file initializes all global state variables used by the marketplace process
-- It should be loaded first, before any other modules

-- Import type definitions from types.lua
require('types')

---@alias TokenId string Process ID of a token
---@alias OrderId string Unique identifier for an order
---@alias Address string Process ID or wallet address
---@alias BalanceAmount string Amount of ARIO in mARIO
---@alias IntentId string Unique identifier for an intent

-- Global constants
---@type TokenId Process ID for ARIO token (can be overridden before loading process)
ARIO_TOKEN_PROCESS_ID = ARIO_TOKEN_PROCESS_ID or 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

---@type Address Treasury address for fee collection
TREASURY_ADDRESS = TREASURY_ADDRESS or ao.id

---@type Address Authority allowed to push intent resolution (defaults to Owner)
IntentPushingAuthority = IntentPushingAuthority or Owner

-- Global state tables
---@type table<string, table<string, Pair>> Nested dictionary: Orderbook[dominantToken][swapToken] = Pair
--- All orders remain in Orderbook with a 'status' field ('active', 'executed', 'cancelled', etc.)
Orderbook = Orderbook or {}

---@type table<OrderId, {dominantToken: TokenId, swapToken: TokenId}> Dictionary mapping orderId to pair location
OrderIndex = OrderIndex or {}


---@type table<IntentId, Intent> Dictionary mapping intentId to intent data
Intents = Intents or {}

---@type IntentId Global counter for intent IDs (string integer)
IntentCounter = IntentCounter or "0"

-- Pruning schedule tracking
---@type table<string, number|nil> Pruning schedule configuration
Pruning = Pruning or {
	nextScheduledOrderbookPruning = nil, -- timestamp of next scheduled prune
	nextScheduledIntentsPruning = nil, -- timestamp of next scheduled intents pruning
}

-- Process metadata
---@type string Process name
Name = Name or 'ANT Marketplace'

---@type string|nil Process owner address
Owner = Owner or nil

-- Accrued fees tracking
---@type string Total accrued fees in mARIO (stored as string for bint compatibility)
AccruedFeesAmount = AccruedFeesAmount or '0'

---[[
--- ARIO Balances tracks both available and locked ARIO balances for users.
--- Structure: ARIOBalances[address] = { balance: "amount", orders: {[orderId]: "lockedAmount"} }
--- - balance: Available ARIO that can be used for new bids/orders or withdrawn
--- - orders: ARIO locked in active orders/bids, indexed by orderId
---
--- This unified structure replaces the previous separate globals:
--- - Old ARIOBalances (just available balance)
--- - EnglishAuctionBalances (auction bids)
--- - OrderLockedBalances (buy order locks)
--- - UserOrdersIndex (reverse lookup from user to orders)
---
--- To find all orders a user is involved in: iterate ARIOBalances[user].orders
--- To find all bidders on an auction: use order.bids field (English auctions only)
---]]
---@type table<Address, {balance: BalanceAmount, orders: table<OrderId, BalanceAmount>}> Dictionary mapping address to account data
ARIOBalances = ARIOBalances or {}


---@type table<string, boolean> Dictionary mapping module name to boolean indicating if the module whitelisted
WhitelistedModules = WhitelistedModules or {}

--- Deferred send queue - stores messages to be sent after handler completes
--- This ensures handler response messages are sent before any side-effect messages (like pruning transfers)
--- @type table<{msg: Message, params: SendParams}> Dictionary mapping message ID to message and parameters
DeferredSends = DeferredSends or {}


return {}