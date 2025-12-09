-- constants.lua
-- Global constants for the marketplace process

local constants = {}

-- Order status constants
constants.ORDER_STATUSES = {
	ACTIVE = 'active',
	EXECUTED = 'executed',
	CANCELLED = 'cancelled',
	READY_FOR_SETTLEMENT = 'ready-for-settlement',
	EXPIRED = 'expired',
}

-- Order status filter constants (for Get-Orders handler)
constants.ORDER_STATUS_FILTERS = {
	ALL = 'all',
	LISTED = 'listed', -- ACTIVE or READY_FOR_SETTLEMENT
	COMPLETED = 'completed', -- EXECUTED, CANCELLED, or EXPIRED
}

-- Order type constants
constants.ORDER_TYPES = {
	FIXED = 'fixed',
	DUTCH = 'dutch',
	ENGLISH = 'english',
}

-- Fee calculation constants (0.5% marketplace fee)
constants.FEE = {
	FACTOR_NUMERATOR = 995, -- Send amount = amount * 995 / 1000 (99.5%)
	FACTOR_DENOMINATOR = 1000,
	AMOUNT_NUMERATOR = 5, -- Fee amount = amount * 5 / 10000 (0.05%)
	AMOUNT_DENOMINATOR = 10000,
	LISTING_FEE_ARIO = '1000000', -- 1 ARIO = 1000000 mARIO
	LISTING_FEE_MULTIPLIER_HOURS = 1, -- 1 hour is one listing fee (1 ARIO per hour)
}

-- Pagination constants
constants.PAGINATION = {
	DEFAULT_LIMIT = 100, -- Default number of items per page
	MAX_LIMIT = 1000, -- Maximum allowed items per page
	DEFAULT_SORT_ORDER = 'desc', -- Default sort order (descending)
	DEFAULT_SORT_BY = 'CreatedAt', -- Default field to sort by
}

-- Address validation constants
constants.ADDRESS = {
	ARWEAVE_LENGTH = 43, -- Standard Arweave address length
	ETHEREUM_PREFIX = '0x', -- Ethereum address prefix
	ETHEREUM_LENGTH = 42, -- Ethereum address length (including 0x)
	UNSAFE_MIN_LENGTH = 1, -- Minimum length for unsafe addresses
	UNSAFE_MAX_LENGTH = 128, -- Maximum length for unsafe addresses
}

-- Time constants (all in milliseconds)
constants.TIME = {
	ONE_MINUTE_MS = 60000,
	ONE_HOUR_MS = 3600000,
	ONE_DAY_MS = 86400000,
	THIRTY_DAYS_MS = 2592000000,
}

-- Quantity constants
constants.QUANTITY = {
	ANT_EXACT_AMOUNT = 1, -- ANT tokens must trade in exact units of 1
}

-- Auction and bidding constants
constants.AUCTION = {
	MINIMUM_BID_INCREMENT = '1000000000', -- Minimum bid increment in ARIO (1 ARIO = 1000000000 mARIO)
}

-- Intent status constants
constants.INTENT_STATUSES = {
	PENDING = 'pending', -- Intent created but not yet resolved
	ACTIVE = 'active', -- Intent is actively being processed
	SETTLING = 'settling', -- Intent is in settlement phase
	RESOLVED = 'resolved', -- Intent has been resolved
	COMPLETED = 'completed', -- Intent has completed successfully
	FAILED = 'failed', -- Intent has failed
}

-- Intent TTL constant (24 hours in milliseconds)
constants.INTENT_TTL_MS = constants.TIME.ONE_DAY_MS

-- Listing expiration limits
constants.LISTING = {
	MIN_EXPIRATION_MS = constants.TIME.ONE_HOUR_MS, -- 1 hour minimum (used for clamping and base fee)
	MAX_EXPIRATION_MS = constants.TIME.THIRTY_DAYS_MS, -- 30 days in milliseconds
}

-- Action name constants (only actively used actions)
constants.ACTIONS = {
	-- Auction actions
	BID_PLACED = 'Bid-Placed',
	BID_UPDATED = 'Bid-Updated',
	-- Balance actions
	DEPOSIT = 'Deposit',
}

return constants
