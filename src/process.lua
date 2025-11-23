-- Load global state initialization first
require('globals')

local ucm = require('ucm')
local utils = require('utils')
local intents = require('intents')
local notices = require('notices')
local balances = require('balances')

-- ActionMap: Maps camelCase action names to Train-Case handler names
-- TODO: should this be ActionMap = ActionMap or {...}?
ActionMap = {
	-- Activity handlers
	getOrders = 'Get-Orders',
	getOrder = 'Get-Order',
	-- UCM handlers
	info = 'Info',
	createOrder = 'Create-Order',
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
	-- Balances handlers
	getPaginatedBalances = 'Get-Paginated-Balances',
	getBalance = 'Get-Balance',
	withdrawArio = 'Withdraw-Ario',
	-- Auction handlers
	bidOnEnglishAuction = 'Bid-On-English-Auction',
}

-- Intent handlers
utils.createHandler('Action', ActionMap.createIntent, intents.createIntentHandler)
utils.createHandler('Action', ActionMap.getPaginatedIntents, intents.getPaginatedIntentsHandler)
utils.createHandler('Action', ActionMap.getIntentById, intents.getIntentByIdHandler)

-- UCM handlers
utils.createHandler('Action', ActionMap.info, ucm.infoHandler)
utils.createHandler('Action', ActionMap.getOrders, ucm.getOrdersHandler)
utils.createHandler('Action', ActionMap.getOrder, ucm.getOrderHandler)
utils.createHandler('Action', ActionMap.createOrder, ucm.createOrderHandler)
utils.createHandler('Action', ActionMap.cancelOrder, ucm.cancelOrderHandler)
utils.createHandler('Action', ActionMap.settleAuction, ucm.settleAuctionHandler)
utils.createHandler('Action', ActionMap.withdrawFees, ucm.withdrawFeesHandler)

-- Notice handlers (incoming notices from external processes)
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler)
utils.createHandler('Action', ActionMap.debitNotice, notices.debitNoticeHandler)
-- Transfer-Error is the token spec aligned error notice for failed transfers
utils.createHandler('Action', ActionMap.transferError, notices.transferErrorHandler)

-- Balances handlers for ARIOBalances global
utils.createHandler('Action', ActionMap.getPaginatedBalances, balances.getPaginatedBalancesHandler)
utils.createHandler('Action', ActionMap.getBalance, balances.getBalanceHandler)
utils.createHandler('Action', ActionMap.withdrawArio, balances.withdrawArioHandler)

-- Auction handlers
local english_auction = require('english_auction')
utils.createHandler('Action', ActionMap.bidOnEnglishAuction, english_auction.bidOnEnglishAuctionHandler)