-- Load global state initialization first
require('globals')

local ucm = require('ucm')
local utils = require('utils')
local intents = require('intents')
local notices = require('notices')

-- ActionMap: Maps camelCase action names to Train-Case handler names
ActionMap = {
	-- Activity handlers
	getOrders = 'Get-Orders',
	getOrder = 'Get-Order',
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
	-- Notice handlers (incoming notices from external processes)
	creditNotice = 'Credit-Notice',
	debitNotice = 'Debit-Notice',
	transferError = 'Transfer-Error',
	invalidTransferNotice = 'Invalid-Transfer-Notice',
}

-- Intent handlers
utils.createHandler('Action', ActionMap.createIntent, intents.createIntentHandler)
utils.createHandler('Action', ActionMap.getPaginatedIntents, intents.getPaginatedIntentsHandler)
utils.createHandler('Action', ActionMap.getIntentById, intents.getIntentByIdHandler)

-- UCM handlers
utils.createHandler('Action', ActionMap.info, ucm.infoHandler)
utils.createHandler('Action', ActionMap.getOrders, ucm.getOrdersHandler)
utils.createHandler('Action', ActionMap.getOrder, ucm.getOrderHandler)
utils.createHandler('Action', ActionMap.getOrderbookByPair, ucm.getOrderbookByPairHandler)
utils.createHandler('Action', ActionMap.cancelOrder, ucm.cancelOrderHandler)
utils.createHandler('Action', ActionMap.settleAuction, ucm.settleAuctionHandler)
utils.createHandler('Action', ActionMap.readOrders, ucm.readOrdersHandler)
utils.createHandler('Action', ActionMap.readPair, ucm.readPairHandler)
utils.createHandler('Action', ActionMap.withdrawFees, ucm.withdrawFeesHandler)

-- Notice handlers (incoming notices from external processes)
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler)
utils.createHandler('Action', ActionMap.debitNotice, notices.debitNoticeHandler)
utils.createHandler('Action', ActionMap.transferError, notices.transferErrorHandler)
utils.createHandler('Action', ActionMap.invalidTransferNotice, notices.transferErrorHandler)
