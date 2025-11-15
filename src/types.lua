--- Type definitions for the AR.IO Marketplace Process
--- This file contains type aliases and class definitions for better IDE support and linting

--- @class Message
--- @field Id string Message identifier
--- @field From string Sender address
--- @field Owner string Process owner address
--- @field Timestamp number Unix timestamp in milliseconds
--- @field Tags table<string, string> Message tags
--- @field Data string Message data payload
--- @field ['Block-Height'] number Block height
--- @field reply function|nil Optional reply function for sending responses

--- @class Intent
--- @field intentId string Unique intent identifier (msg.Id)
--- @field type "parent"|"child" Intent type
--- @field initiator string Address that created the intent (msg.From)
--- @field parentIntentId string|nil Parent intent ID for child intents
--- @field childIntentIds table<string, boolean> Map of child intent IDs (O(1) lookup)
--- @field action string Action being performed (Create-Order, Cancel-Order, Settle-Auction, Transfer)
--- @field status "pending"|"active"|"settling"|"completed"|"resolved"|"failed" Intent status
--- @field createdAt number Creation timestamp
--- @field resolvedAt number|nil Resolution timestamp
--- @field completedAt number|nil Completion timestamp
--- @field failureReason string|nil Failure reason if status is failed
--- @field forwardedTags table<string, any> Tags forwarded with the intent
--- @field expectedMessage string|nil Expected message type for child intents (e.g., "Debit-Notice")
--- @field expectedFrom string|nil Expected sender for child intents (token process ID)

--- @class ParentIntent : Intent
--- @field type "parent"
--- @field childIntentIds table<string, boolean>

--- @class ChildIntent : Intent
--- @field type "child"
--- @field parentIntentId string
--- @field expectedMessage string
--- @field expectedFrom string

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
--- @field orderId string Order identifier
--- @field orderGroupId string Order group identifier
--- @field dominantToken string Token being deposited
--- @field swapToken string Token being requested
--- @field sender string Order creator address
--- @field quantity string Quantity of tokens
--- @field createdAt number Creation timestamp
--- @field blockheight number Block height at creation
--- @field orderType "fixed"|"dutch"|"english" Order type
--- @field price string|nil Price for the order
--- @field expirationTime number|nil Expiration timestamp
--- @field minimumPrice string|nil Minimum price (dutch auction)
--- @field decreaseInterval string|nil Decrease interval (dutch auction)
--- @field requestedOrderId string|nil Requested order ID (for buying)
--- @field transferDenomination string|nil Transfer denomination
--- @field executionPrice string|nil Execution price (dutch auction)
--- @field msg Message|nil Message context for intent tracking

--- @class EnglishAuctionBidArgs : OrderArgs
--- @field pair Pair The orderbook pair object containing orders

--- @class Order
--- @field id string Order identifier
--- @field creator string Order creator address
--- @field quantity string Quantity of tokens
--- @field originalQuantity string Original quantity
--- @field token string Token process ID
--- @field dateCreated number Creation timestamp
--- @field price string|nil Order price
--- @field expirationTime number|nil Expiration timestamp
--- @field orderType "fixed"|"dutch"|"english" Order type
--- @field status "active"|"executed"|"cancelled"|"ready-for-settlement"|"expired" Order status
--- @field minimumPrice string|nil Minimum price (dutch auction)
--- @field decreaseInterval string|nil Decrease interval (dutch auction)
--- @field decreaseStep string|nil Decrease step (dutch auction)
--- @field sender string|nil Order sender (set after execution)
--- @field receiver string|nil Order receiver (set after execution)
--- @field endedAt number|nil Timestamp when order ended

--- @class Pair
--- @field pair string[] Token pair [dominantToken, swapToken] - directional
--- @field orders table<string, Order> Dictionary of orders keyed by OrderId
--- @field priceData table|nil Price data for the pair
--- Note: Pairs are stored in Orderbook as Orderbook[dominantToken][swapToken] = Pair

--- @class SendParams
--- @field Target string Target process ID
--- @field Action string Action to perform
--- @field Tags table<string, string>|nil Message tags
--- @field Data string|nil Message data

--- @class ErrorHandlerArgs
--- @field target string Target to send error to
--- @field action string Action type
--- @field message string Error message
--- @field quantity string|nil Quantity to refund
--- @field transferToken string|nil Token to refund
--- @field orderGroupId string|nil Order group ID
--- @field msg Message|nil Message context for intent tracking

--- @class SettleArgs
--- @field orderId string Order ID to settle
--- @field sender string Settlement initiator
--- @field timestamp number Settlement timestamp
--- @field orderGroupId string Order group ID
--- @field dominantToken string Dominant token
--- @field swapToken string Swap token
--- @field msg Message|nil Message context for intent tracking

--- @class IntentStats
--- @field total number Total number of intents
--- @field byStatus table<string, number> Intent counts by status
--- @field byType table<string, number> Intent counts by type
--- @field byAction table<string, number> Intent counts by action

--- @class ExecutedOrder
--- @field id string Executed order ID
--- @field dominantToken string Token that was deposited
--- @field swapToken string Token that was received
--- @field sender string Order sender address
--- @field receiver string Order receiver address
--- @field quantity string Quantity transferred
--- @field price string Execution price
--- @field createdAt number Creation timestamp
--- @field executedAt number Execution timestamp
--- @field orderType "fixed"|"dutch"|"english" Type of order

--- @class BidInfo
--- @field bidder string Address of the bidder
--- @field amount string Bid amount
--- @field timestamp number When bid was placed
--- @field orderId string Order being bid on

--- @class AuctionBidInfo
--- @field bids table<string, BidInfo> Dictionary mapping user address to their bid
--- @field highestBid string|nil Current highest bid amount
--- @field highestBidder string|nil Address of current highest bidder
--- @field settlement table|nil Settlement information if auction completed

--- @class OrderIndexEntry
--- @field dominantToken string The dominant token in the pair
--- @field swapToken string The swap token in the pair

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
--- @field accruedFees string Total fees collected by the marketplace
--- @field arioTokenProcess string The ARIO token process ID

--- @class InfoResponse
--- @field name string The marketplace name
--- @field processId string The AO process ID
--- @field activity ActivityInfo Activity statistics
--- @field intents IntentStats Intent workflow statistics
--- @field ucm UCMInfo UCM marketplace information

return {}
