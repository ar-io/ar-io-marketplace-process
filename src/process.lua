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
	cancelOrder = 'Cancel-Order',
	settleAuction = 'Settle-Auction',
	withdrawFees = 'Withdraw-Fees',
	-- Intent handlers
	createIntent = 'Create-Intent',
	getPaginatedIntents = 'Get-Paginated-Intents',
	getIntentById = 'Get-Intent-By-Id',
	-- Notice handlers (incoming notices from external processes)
	creditNotice = 'Credit-Notice',
	debitNotice = 'Debit-Notice',
	transferError = 'Transfer-Error',
}

-- Intent handlers
utils.createHandler('Action', ActionMap.createIntent, intents.createIntentHandler)
utils.createHandler('Action', ActionMap.getPaginatedIntents, intents.getPaginatedIntentsHandler)
utils.createHandler('Action', ActionMap.getIntentById, intents.getIntentByIdHandler)

-- UCM handlers
utils.createHandler('Action', ActionMap.info, ucm.infoHandler)
utils.createHandler('Action', ActionMap.getOrders, ucm.getOrdersHandler)
utils.createHandler('Action', ActionMap.getOrder, ucm.getOrderHandler)
utils.createHandler('Action', ActionMap.cancelOrder, ucm.cancelOrderHandler)
utils.createHandler('Action', ActionMap.settleAuction, ucm.settleAuctionHandler)
utils.createHandler('Action', ActionMap.withdrawFees, ucm.withdrawFeesHandler)

-- Notice handlers (incoming notices from external processes)
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler)
utils.createHandler('Action', ActionMap.debitNotice, notices.debitNoticeHandler)
-- Transfer-Error is the token spec aligned error notice for failed transfers
utils.createHandler('Action', ActionMap.transferError, notices.transferErrorHandler)