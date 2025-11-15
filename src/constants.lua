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

-- Auction and bidding constants
constants.AUCTION = {
	MINIMUM_BID_INCREMENT = 1, -- Minimum bid increment in ARIO
	ANT_EXACT_QUANTITY = 1, -- ANT tokens must trade in exact units of 1
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

-- Intent type constants
constants.INTENT_TYPES = {
	PARENT = 'parent', -- Parent intent (user-initiated)
	CHILD = 'child', -- Child intent (system-generated)
}

-- Expected message constants
constants.EXPECTED_MESSAGES = {
	DEBIT_NOTICE = 'Debit-Notice', -- Expected debit notice from token process
}

-- Action name constants
constants.ACTIONS = {
	-- Order actions
	ORDER_SUCCESS = 'Order-Success',
	ORDER_ERROR = 'Order-Error',
	VALIDATION_ERROR = 'Validation-Error',
	SETTLEMENT_ERROR = 'Settlement-Error',
	INPUT_ERROR = 'Input-Error',
	-- Auction actions
	BID_SUCCESS = 'Bid-Success',
	BID_RETURNED = 'Bid-Returned',
	AUCTION_WON = 'Auction-Won',
	SETTLEMENT_SUCCESS = 'Settlement-Success',
	-- Transfer actions
	TRANSFER = 'Transfer',
	CREDIT_NOTICE = 'Credit-Notice',
	DEBIT_NOTICE = 'Debit-Notice',
	TRANSFER_ERROR = 'Transfer-Error',
	INVALID_TRANSFER_NOTICE = 'Invalid-Transfer-Notice',
	-- Read actions
	READ_SUCCESS = 'Read-Success',
	ORDER_NOT_FOUND = 'Order-Not-Found',
	-- Notice actions
	VOLUME_NOTICE = 'Volume-Notice',
	MOST_TRADED_TOKENS_RESULT = 'Most-Traded-Tokens-Result',
	TABLE_LENGTHS_RESULT = 'Table-Lengths-Result',
	INVALID_NOTICE = 'Invalid-{Action}-Notice', -- Template for invalid action notices
}

-- Tag name constants
constants.TAGS = {
	-- Common tags
	STATUS = 'Status',
	MESSAGE = 'Message',
	GROUP_ID = 'X-Group-ID',
	-- Intent tags
	INTENT_ID = 'X-Intent-Id',
	INTENT_ACTION = 'X-Intent-Action',
	INTENT_ORDER_TYPE = 'X-Intent-Order-Type',
	INTENT_SWAP_TOKEN = 'X-Intent-Swap-Token',
	INTENT_QUANTITY = 'X-Intent-Quantity',
	INTENT_PRICE = 'X-Intent-Price',
	INTENT_EXPIRATION_TIME = 'X-Intent-Expiration-Time',
	INTENT_MINIMUM_PRICE = 'X-Intent-Minimum-Price',
	INTENT_DECREASE_INTERVAL = 'X-Intent-Decrease-Interval',
	INTENT_REQUESTED_ORDER_ID = 'X-Intent-Requested-Order-Id',
	INTENT_ORDER_ID = 'X-Intent-Order-Id',
	INTENT_DOMINANT_TOKEN = 'X-Intent-Dominant-Token',
	-- Order tags
	ORDER_ACTION = 'X-Order-Action',
	ORDER_ID = 'Order-Id',
	ORDER_TYPE = 'X-Order-Type',
	SWAP_TOKEN = 'X-Swap-Token',
	DOMINANT_TOKEN = 'Dominant-Token',
	EXPIRATION_TIME = 'X-Expiration-Time',
	MINIMUM_PRICE = 'X-Minimum-Price',
	DECREASE_INTERVAL = 'X-Decrease-Interval',
	REQUESTED_ORDER_ID = 'X-Requested-Order-Id',
	PRICE = 'X-Price',
	TRANSFER_DENOMINATION = 'X-Transfer-Denomination',
}

-- Token denomination constants
constants.TOKEN = {
	DENOMINATION_DIVISOR = 1000000000000, -- Divisor for token denomination (12 decimals)
}

return constants

