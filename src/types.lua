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
--- @field IntentId string Unique intent identifier (msg.Id)
--- @field Type "parent"|"child" Intent type
--- @field Initiator string Address that created the intent (msg.From)
--- @field ParentIntentId string|nil Parent intent ID for child intents
--- @field ChildIntentIds table<string, boolean> Map of child intent IDs (O(1) lookup)
--- @field Action string Action being performed (Create-Order, Cancel-Order, Settle-Auction, Transfer)
--- @field Status "pending"|"active"|"settling"|"completed"|"resolved"|"failed" Intent status
--- @field CreatedAt number Creation timestamp
--- @field ResolvedAt number|nil Resolution timestamp
--- @field CompletedAt number|nil Completion timestamp
--- @field FailureReason string|nil Failure reason if status is failed
--- @field ForwardedTags table<string, any> Tags forwarded with the intent
--- @field ExpectedMessage string|nil Expected message type for child intents (e.g., "Debit-Notice")
--- @field ExpectedFrom string|nil Expected sender for child intents (token process ID)

--- @class ParentIntent : Intent
--- @field Type "parent"
--- @field ChildIntentIds table<string, boolean>

--- @class ChildIntent : Intent
--- @field Type "child"
--- @field ParentIntentId string
--- @field ExpectedMessage string
--- @field ExpectedFrom string

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

--- @class Order
--- @field Id string Order identifier
--- @field Creator string Order creator address
--- @field Quantity string Quantity of tokens
--- @field OriginalQuantity string Original quantity
--- @field Token string Token process ID
--- @field DateCreated number Creation timestamp
--- @field Price string|nil Order price
--- @field ExpirationTime number|nil Expiration timestamp
--- @field OrderType "fixed"|"dutch"|"english" Order type
--- @field MinimumPrice string|nil Minimum price (dutch auction)
--- @field DecreaseInterval string|nil Decrease interval (dutch auction)
--- @field DecreaseStep string|nil Decrease step (dutch auction)

--- @class Pair
--- @field Pair string[] Token pair [tokenA, tokenB]
--- @field Orders Order[] Orders for this pair
--- @field PriceData table|nil Price data for the pair

--- @class SendParams
--- @field Target string Target process ID
--- @field Action string Action to perform
--- @field Tags table<string, string>|nil Message tags
--- @field Data string|nil Message data

--- @class ErrorHandlerArgs
--- @field Target string Target to send error to
--- @field Action string Action type
--- @field Message string Error message
--- @field Quantity string|nil Quantity to refund
--- @field TransferToken string|nil Token to refund
--- @field OrderGroupId string|nil Order group ID
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
--- @field Total number Total number of intents
--- @field ByStatus table<string, number> Intent counts by status
--- @field ByType table<string, number> Intent counts by type
--- @field ByAction table<string, number> Intent counts by action

return {}
