--- Type definitions for the AR.IO Marketplace Process
--- This file contains type aliases and class definitions for better IDE support and linting
--- Type aliases (TokenId, OrderId, Address, BalanceAmount, IntentId) are defined in globals.lua

--- @class Message
--- @field Id string Message identifier
--- @field From Address Sender address
--- @field Owner Address Process owner address
--- @field Timestamp number Unix timestamp in milliseconds
--- @field Tags table<string, string> Message tags
--- @field Data string Message data payload
--- @field ['Block-Height'] number Block height
--- @field reply function|nil Optional reply function for sending responses

--- @class Intent
--- @field intentId IntentId Unique intent identifier (msg.Id)
--- @field initiator Address Address that created the intent (msg.From)
--- @field action string Action being performed (Create-Order, Cancel-Order, Settle-Auction, Transfer)
--- @field status "pending"|"active"|"settling"|"completed"|"resolved"|"failed" Intent status
--- @field createdAt number Creation timestamp
--- @field ttl number|nil Time-to-live timestamp (24 hours from creation)
--- @field resolvedAt number|nil Resolution timestamp
--- @field completedAt number|nil Completion timestamp
--- @field failureReason string|nil Failure reason if status is failed
--- @field forwardedTags table<string, any> Tags forwarded with the intent
--- @field antProcessId TokenId|nil ANT process ID (set during Credit-Notice for ANT transfers)

--- @class PaginationTags
--- @field cursor string|nil The cursor to paginate from
--- @field limit number The limit of results to return
--- @field sortBy string|nil The field to sort by
--- @field sortOrder "asc"|"desc" The order to sort by
--- @field filters table|nil Optional filters to apply

--- @class PaginatedTable
--- @field items table[] Array of items for the current page
--- @field limit number The limit of items requested
--- @field totalItems number Total number of items available
--- @field sortBy string The field used for sorting
--- @field sortOrder "asc"|"desc" The sort order used
--- @field nextCursor string|nil Cursor for the next page (nil if no more pages)
--- @field hasMore boolean Whether there are more pages available

--- @class OrderArgs
--- @field orderId OrderId Order identifier
--- @field dominantToken TokenId Token being deposited
--- @field swapToken TokenId Token being requested
--- @field sender Address Order creator address
--- @field quantity BalanceAmount Quantity of tokens
--- @field createdAt number Creation timestamp
--- @field blockheight number Block height at creation
--- @field orderType "fixed"|"dutch"|"english" Order type
--- @field price BalanceAmount|nil Price for the order
--- @field expirationTime number|nil Expiration timestamp
--- @field minimumPrice BalanceAmount|nil Minimum price (dutch auction)
--- @field decreaseInterval BalanceAmount|nil Decrease interval (dutch auction)
--- @field requestedOrderId OrderId|nil Requested order ID (for buying)
--- @field transferDenomination string|nil Transfer denomination
--- @field executionPrice BalanceAmount|nil Execution price (dutch auction)
--- @field msg Message|nil Message context for intent tracking

--- @class EnglishAuctionBidArgs : OrderArgs
--- @field pair Pair The orderbook pair object containing orders

--- @class Order
--- @field id OrderId Order identifier
--- @field creator Address Order creator address
--- @field quantity BalanceAmount Quantity of tokens
--- @field originalQuantity BalanceAmount Original quantity
--- @field token TokenId Token process ID
--- @field dominantToken TokenId The dominant token in the trading pair
--- @field swapToken TokenId The swap token in the trading pair
--- @field dateCreated number Creation timestamp
--- @field price BalanceAmount|nil Order price
--- @field expirationTime number|nil Expiration timestamp
--- @field orderType "fixed"|"dutch"|"english" Order type
--- @field status "active"|"executed"|"cancelled"|"ready-for-settlement"|"expired" Order status
--- @field minimumPrice BalanceAmount|nil Minimum price (dutch auction)
--- @field decreaseInterval BalanceAmount|nil Decrease interval (dutch auction)
--- @field decreaseStep BalanceAmount|nil Decrease step (dutch auction)
--- @field sender Address|nil Order sender (set after execution)
--- @field receiver Address|nil Order receiver (set after execution)
--- @field endedAt number|nil Timestamp when order ended
--- @field bids table<Address, boolean>|nil Bidders for English auctions (bidder address -> true)

--- @class Pair
--- @field pair TokenId[] Token pair [dominantToken, swapToken] - directional
--- @field orders table<OrderId, Order> Dictionary of orders keyed by OrderId
--- @field priceData table|nil Price data for the pair
--- Note: Pairs are stored in Orderbook as Orderbook[dominantToken][swapToken] = Pair

--- @class SendParams
--- @field Target Address Target process ID
--- @field Action string Action to perform
--- @field Tags table<string, string>|nil Message tags
--- @field Data string|nil Message data

--- @class ErrorHandlerArgs
--- @field target Address Target to send error to
--- @field action string Action type
--- @field message string Error message
--- @field quantity BalanceAmount|nil Quantity to refund
--- @field transferToken TokenId|nil Token to refund
--- @field msg Message|nil Message context for intent tracking

--- @class SettleArgs
--- @field orderId OrderId Order ID to settle
--- @field sender Address Settlement initiator
--- @field timestamp number Settlement timestamp
--- @field dominantToken TokenId Dominant token
--- @field swapToken TokenId Swap token
--- @field msg Message|nil Message context for intent tracking

--- @class ExecuteTokenTransfersArgs
--- @field sender Address The buyer/order sender address
--- @field dominantToken TokenId The dominant token process ID
--- @field swapToken TokenId The swap token process ID
--- @field originalSendAmount BalanceAmount|nil Original send amount before fees (for fee calculation)
--- @field msg Message|nil Message context for intent tracking
--- @field currentOrderEntry Order The order being matched
--- @field calculatedSendAmount BalanceAmount|number The amount of dominant tokens to transfer (after fees)
--- @field calculatedFillAmount BalanceAmount|number The amount of swap tokens to transfer

--- @class IntentStats
--- @field total number Total number of intents
--- @field byStatus table<string, number> Intent counts by status
--- @field byAction table<string, number> Intent counts by action

--- @class ExecutedOrder
--- @field id OrderId Executed order ID
--- @field dominantToken TokenId Token that was deposited
--- @field swapToken TokenId Token that was received
--- @field sender Address Order sender address
--- @field receiver Address Order receiver address
--- @field quantity BalanceAmount Quantity transferred
--- @field price BalanceAmount Execution price
--- @field createdAt number Creation timestamp
--- @field executedAt number Execution timestamp
--- @field orderType "fixed"|"dutch"|"english" Type of order

--- @class BidInfo
--- @field bidder Address Address of the bidder
--- @field amount BalanceAmount Bid amount
--- @field timestamp number When bid was placed
--- @field orderId OrderId Order being bid on

--- @class OrderIndexEntry
--- @field dominantToken TokenId The dominant token in the pair
--- @field swapToken TokenId The swap token in the pair

--- @class ActivityInfo
--- @field totalOrders number Total number of orders in the orderbook
--- @field activeOrders number Number of currently active orders
--- @field readyForSettlement number Number of orders ready for settlement
--- @field executedOrders number Number of executed orders
--- @field cancelledOrders number Number of cancelled orders
--- @field expiredOrders number Number of expired orders
--- @field listedOrders number Total listed orders (active + ready for settlement)

--- @class UCMInfo
--- @field totalPairs number Number of trading pairs in the orderbook
--- @field accruedFees BalanceAmount Total fees collected by the marketplace
--- @field arioTokenProcess TokenId The ARIO token process ID

--- @class InfoResponse
--- @field name string The marketplace name
--- @field processId Address The AO process ID
--- @field activity ActivityInfo Activity statistics
--- @field intents IntentStats Intent workflow statistics
--- @field ucm UCMInfo UCM marketplace information

return {}
