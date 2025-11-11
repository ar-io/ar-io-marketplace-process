
local ucm = require('ucm')
local activity = require('activity')
local utils = require('utils')
local intents = require('intents')
local notices = require('notices')

-- CHANGEME
ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

-- ActionMap: Maps camelCase action names to Train-Case handler names
ActionMap = {
	-- Activity handlers
	getListedOrders = 'Get-Listed-Orders',
	getCompletedOrders = 'Get-Completed-Orders',
	getOrderById = 'Get-Order-By-Id',
	getActivity = 'Get-Activity',
	getOrderCountsByAddress = 'Get-Order-Counts-By-Address',
	getSalesByAddress = 'Get-Sales-By-Address',
	getVolume = 'Get-Volume',
	getMostTradedTokens = 'Get-Most-Traded-Tokens',
	getActivityLengths = 'Get-Activity-Lengths',
	migrateActivityDryrun = 'Migrate-Activity-Dryrun',
	migrateActivity = 'Migrate-Activity',
	migrateActivityBatch = 'Migrate-Activity-Batch',
	migrateActivityStats = 'Migrate-Activity-Stats',
	-- UCM handlers
	info = 'Info',
	getOrderbookByPair = 'Get-Orderbook-By-Pair',
	cancelOrder = 'Cancel-Order',
	settleAuction = 'Settle-Auction',
	readOrders = 'Read-Orders',
	readPair = 'Read-Pair',
	withdrawFees = 'Withdraw-Fees',
	-- Intent handlers
	createIntent = 'Create-Intent',
	getPaginatedIntents = 'Get-Paginated-Intents',
	getIntentById = 'Get-Intent-By-Id',
	getIntentStats = 'Get-Intent-Stats',
	-- Notice handlers (incoming notices from external processes)
	creditNotice = 'Credit-Notice',
	debitNotice = 'Debit-Notice',
	transferError = 'Transfer-Error',
	invalidTransferNotice = 'Invalid-Transfer-Notice',
}

-- Activity process handlers
utils.createHandler('Action', ActionMap.getListedOrders, activity.getListedOrders)
utils.createHandler('Action', ActionMap.getCompletedOrders, activity.getCompletedOrders)
utils.createHandler('Action', ActionMap.getOrderById, activity.getOrderById)
utils.createHandler('Action', ActionMap.getActivity, activity.getActivity)
utils.createHandler('Action', ActionMap.getOrderCountsByAddress, activity.getOrderCountsByAddress)
utils.createHandler('Action', ActionMap.getSalesByAddress, activity.getSalesByAddress)
utils.createHandler('Action', ActionMap.getVolume, activity.getVolume)
utils.createHandler('Action', ActionMap.getMostTradedTokens, activity.getMostTradedTokens)
utils.createHandler('Action', ActionMap.getActivityLengths, activity.getActivityLengths)
utils.createHandler('Action', ActionMap.migrateActivityDryrun, activity.migrateActivityDryrun)
utils.createHandler('Action', ActionMap.migrateActivity, activity.migrateActivity)
utils.createHandler('Action', ActionMap.migrateActivityBatch, activity.migrateActivityBatch)
utils.createHandler('Action', ActionMap.migrateActivityStats, activity.migrateActivityStats)

-- Intent handlers
utils.createHandler('Action', ActionMap.createIntent, intents.createIntentHandler)
utils.createHandler('Action', ActionMap.getPaginatedIntents, intents.getPaginatedIntentsHandler)
utils.createHandler('Action', ActionMap.getIntentById, intents.getIntentByIdHandler)
utils.createHandler('Action', ActionMap.getIntentStats, intents.getIntentStatsHandler)

-- UCM handlers
utils.createHandler('Action', ActionMap.info, ucm.info)
utils.createHandler('Action', ActionMap.getOrderbookByPair, ucm.getOrderbookByPair)
utils.createHandler('Action', ActionMap.cancelOrder, ucm.cancelOrder)
utils.createHandler('Action', ActionMap.settleAuction, ucm.settleAuctionHandler)
utils.createHandler('Action', ActionMap.readOrders, ucm.readOrders)
utils.createHandler('Action', ActionMap.readPair, ucm.readPair)
utils.createHandler('Action', ActionMap.withdrawFees, ucm.withdrawFeesHandler)

-- Notice handlers (incoming notices from external processes)
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler)
utils.createHandler('Action', ActionMap.debitNotice, notices.debitNoticeHandler)
utils.createHandler('Action', ActionMap.transferError, notices.transferErrorHandler)
utils.createHandler('Action', ActionMap.invalidTransferNotice, notices.transferErrorHandler)
