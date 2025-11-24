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
	pushANTIntentResolution = 'Push-ANT-Intent-Resolution',
	-- Notice handlers (incoming notices from external processes)
	creditNotice = 'Credit-Notice',
	debitNotice = 'Debit-Notice',
	transferError = 'Transfer-Error',
	stateNotice = 'State-Notice',
	-- Balances handlers
	getPaginatedBalances = 'Get-Paginated-Balances',
	getBalance = 'Get-Balance',
	withdrawArio = 'Withdraw-Ario',
	-- Auction handlers
	bidOnEnglishAuction = 'Bid-On-English-Auction',
}

-- Intent handlers
utils.createHandler('Action', ActionMap.createIntent, intents.createIntentHandler, nil, true) -- Critical: charges listing fee
utils.createHandler('Action', ActionMap.getPaginatedIntents, intents.getPaginatedIntentsHandler)
utils.createHandler('Action', ActionMap.getIntentById, intents.getIntentByIdHandler)
utils.createHandler('Action', ActionMap.pushANTIntentResolution, intents.pushANTIntentResolutionHandler) -- Triggers ANT State query

-- UCM handlers
utils.createHandler('Action', ActionMap.info, ucm.infoHandler)
utils.createHandler('Action', ActionMap.getOrders, ucm.getOrdersHandler)
utils.createHandler('Action', ActionMap.getOrder, ucm.getOrderHandler)
utils.createHandler('Action', ActionMap.createOrder, ucm.createOrderHandler, nil, true) -- Critical: creates order with balance
utils.createHandler('Action', ActionMap.cancelOrder, ucm.cancelOrderHandler, nil, true) -- Critical: returns locked funds
utils.createHandler('Action', ActionMap.settleAuction, ucm.settleAuctionHandler, nil, true) -- Critical: executes transfers
utils.createHandler('Action', ActionMap.withdrawFees, ucm.withdrawFeesHandler, nil, true) -- Critical: transfers fees

-- Notice handlers (incoming notices from external processes)
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler, nil, true) -- Critical: deposits and creates orders
utils.createHandler('Action', ActionMap.debitNotice, notices.debitNoticeHandler, nil, true) -- Critical: confirms transfers
-- Transfer-Error is the token spec aligned error notice for failed transfers
utils.createHandler('Action', ActionMap.transferError, notices.transferErrorHandler, nil, true) -- Critical: handles transfer failures
utils.createHandler('Action', ActionMap.stateNotice, intents.stateNoticeHandler, nil, true) -- Critical: resolves ANT ownership intents

-- Balances handlers for ARIOBalances global
utils.createHandler('Action', ActionMap.getPaginatedBalances, balances.getPaginatedBalancesHandler)
utils.createHandler('Action', ActionMap.getBalance, balances.getBalanceHandler)
utils.createHandler('Action', ActionMap.withdrawArio, balances.withdrawArioHandler, nil, true) -- Critical: withdraws ARIO

-- Auction handlers
local english_auction = require('english_auction')
utils.createHandler('Action', ActionMap.bidOnEnglishAuction, english_auction.bidOnEnglishAuctionHandler, nil, true) -- Critical: locks bid balance