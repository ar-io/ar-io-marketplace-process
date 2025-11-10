local json = require('json')

local ucm = require('ucm')
local activity = require('activity')
local utils = require('utils')


-- CHANGEME
ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

function Trusted(msg)
	local mu = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY'
	if msg.Owner == mu then
		return false
	end
	if msg.From == msg.Owner then
		return false
	end
	return true
end

-- Activity process handlers
-- Get listed orders
Handlers.add('Get-Listed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Listed-Orders'), activity.getListedOrders)

-- Get completed orders
Handlers.add('Get-Completed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Completed-Orders'), activity.getCompletedOrders)

-- Get order by ID
Handlers.add('Get-Order-By-Id', Handlers.utils.hasMatchingTag('Action', 'Get-Order-By-Id'), activity.getOrderById)

-- Read activity
Handlers.add('Get-Activity', Handlers.utils.hasMatchingTag('Action', 'Get-Activity'), activity.getActivity)

-- Read order counts by address
Handlers.add('Get-Order-Counts-By-Address', Handlers.utils.hasMatchingTag('Action', 'Get-Order-Counts-By-Address'), activity.getOrderCountsByAddress)

Handlers.add('Get-Sales-By-Address', Handlers.utils.hasMatchingTag('Action', 'Get-Sales-By-Address'), activity.getSalesByAddress)

Handlers.add('Get-Volume', Handlers.utils.hasMatchingTag('Action', 'Get-Volume'), activity.getVolume)

Handlers.add('Get-Most-Traded-Tokens', Handlers.utils.hasMatchingTag('Action', 'Get-Most-Traded-Tokens'), activity.getMostTradedTokens)

Handlers.add('Get-Activity-Lengths', Handlers.utils.hasMatchingTag('Action', 'Get-Activity-Lengths'), activity.getActivityLengths)

Handlers.add('Migrate-Activity-Dryrun', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Dryrun'), activity.migrateActivityDryrun)

Handlers.add('Migrate-Activity', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity'), activity.migrateActivity)

Handlers.add('Migrate-Activity-Batch', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Batch'), activity.migrateActivityBatch)

Handlers.add('Migrate-Activity-Stats', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Stats'), activity.migrateActivityStats)

-- End of activity process handlers

Handlers.prepend('qualify message',
	Trusted,
	function(msg)
		print('This Msg is not trusted!')
	end
)

Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'),
	function(msg)
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				Name = Name,
				Orderbook = Orderbook
			})
		})
	end)

Handlers.add('Get-Orderbook-By-Pair', Handlers.utils.hasMatchingTag('Action', 'Get-Orderbook-By-Pair'),
	function(msg)
		if not msg.Tags.DominantToken or not msg.Tags.SwapToken then return end
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		if pairIndex > -1 then
			ao.send({
				Target = msg.From,
				Action = 'Read-Success',
				Data = json.encode({ Orderbook = Orderbook[pairIndex] })
			})
		end
	end)

Handlers.add('Credit-Notice', Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), function(msg)
	if not msg.Tags['X-Dominant-Token'] or msg.From ~= msg.Tags['X-Dominant-Token'] then return end

	local data = {
		Sender = msg.Tags.Sender,
		Quantity = msg.Tags.Quantity
	}

	-- Ensure we refund deposits on early validation failures
	local function refundAndError(message, action)
		utils.handleError({
			Target = data.Sender,
			Action = action or 'Validation-Error',
			Message = message,
			Quantity = msg.Tags.Quantity,
			TransferToken = msg.From,
			OrderGroupId = msg.Tags['X-Group-ID'] or 'None'
		})
	end

	-- Check if sender is a valid address
	if not utils.checkValidAddress(data.Sender) then
		refundAndError('Sender must be a valid address')
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not utils.checkValidAmount(data.Quantity) then
		refundAndError('Quantity must be an integer greater than zero')
		return
	end

	-- Check if all required fields are present
	if not data.Sender or not data.Quantity then
		refundAndError('Invalid arguments, required { Sender, Quantity }', 'Input-Error')
		return
	end

	-- If Order-Action then create the order
	if msg.Tags['X-Order-Action'] == 'Create-Order' then
		-- Validate that at least one token in the trade is ARIO
		local isArioValid, arioError = utils.validateArioInTrade(msg.From, msg.Tags['X-Swap-Token'])
		if not isArioValid then
			ao.send({
				Target = msg.From,
				Action = 'Validation-Error',
				Tags = { Status = 'Error', Message = arioError or 'At least one token in the trade must be ARIO' }
			})
			return
		end

		local orderArgs = {
			orderId = msg.Id,
			orderGroupId = msg.Tags['X-Group-ID'] or 'None',
			dominantToken = msg.From,
			swapToken = msg.Tags['X-Swap-Token'],
			sender = data.Sender,
			quantity = msg.Tags.Quantity,
			createdAt = msg.Timestamp,
			blockheight = msg['Block-Height'],
			orderType = msg.Tags['X-Order-Type'] or 'fixed',
			expirationTime = msg.Tags['X-Expiration-Time'] and tonumber(msg.Tags['X-Expiration-Time']),
			minimumPrice = msg.Tags['X-Minimum-Price'],
			decreaseInterval = msg.Tags['X-Decrease-Interval'],
			requestedOrderId = msg.Tags['X-Requested-Order-Id']
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		-- Protect order creation to refund on unexpected runtime errors
		local ok, err = pcall(function()
			ucm.createOrder(orderArgs)
		end)
		if not ok then
			refundAndError('Order creation failed: ' .. tostring(err), 'Order-Error')
			return
		end
	end
end)

Handlers.add('Cancel-Order', Handlers.utils.hasMatchingTag('Action', 'Cancel-Order'), function(msg)
    ucm.cancelOrder(msg)
end)

Handlers.add('Read-Orders', Handlers.utils.hasMatchingTag('Action', 'Read-Orders'), function(msg)
	if msg.From == ao.id then
		local readOrders = {}
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		print('Pair index: ' .. pairIndex)

		if pairIndex > -1 then
			for i, order in ipairs(Orderbook[pairIndex].Orders) do
				if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
					table.insert(readOrders, {
						index = i,
						id = order.Id,
						creator = order.Creator,
						quantity = order.Quantity,
						price = order.Price,
						CreatedAt = order.CreatedAt
					})
				end
			end

			ao.send({
				Target = msg.From,
				Action = 'Read-Orders-Response',
				Data = json.encode(readOrders)
			})
		end
	end
end)

Handlers.add('Read-Pair', Handlers.utils.hasMatchingTag('Action', 'Read-Pair'), function(msg)
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })
	if pairIndex > -1 then
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				Pair = tostring(pairIndex),
				Orderbook =
					Orderbook[pairIndex]
			})
		})
	end
end)

Handlers.add('Settle-Auction', Handlers.utils.hasMatchingTag('Action', 'Settle-Auction'), function(msg)
	print('Settling auctionXXX')
	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	
	if not decodeCheck or not data.OrderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = { Status = 'Error', Message = 'OrderId is required' }
		})
		return
	end
	
	-- Use internal activity lookup instead of messaging
	local foundOrder = activity.findOrderById(data.OrderId, msg.Timestamp)
	if not foundOrder then
		ao.send({
			Target = msg.From,
			Action = 'Settlement-Error',
			Tags = { Status = 'Error', Message = 'Order not found' }
		})
		return
	end
	
	if foundOrder.Status ~= 'ready-for-settlement' then
		ao.send({
			Target = msg.From,
			Action = 'Settlement-Error',
			Tags = { 
				Status = 'Error', 
				Message = 'Order is not ready for settlement. Status: ' .. tostring(foundOrder.Status),
				CurrentStatus = tostring(foundOrder.Status)
			}
		})
		return
	end
	
	local settleArgs = {
		orderId = data.OrderId,
		sender = msg.From,
		timestamp = msg.Timestamp,
		orderGroupId = msg.Tags['X-Group-ID'] or 'None',
		dominantToken = data.DominantToken,
		swapToken = data.SwapToken
	}
	
	ucm.settleAuction(settleArgs)
	print('Settled auction')
end)

Handlers.add('Withdraw-Fees', Handlers.utils.hasMatchingTag('Action', 'Withdraw-Fees'), function(msg)
	-- Only the process owner can withdraw fees
	if msg.From ~= msg.Owner then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Unauthorized: only process owner can withdraw fees' } })
		return
	end

	local amount = AccruedFeesAmount
	if not amount or amount == 0 then
		return
	end

	-- transfer fees to requester
	ao.send({
		Target = ARIO_TOKEN_PROCESS_ID,
		Action = 'Transfer',
		Tags = {
			Recipient = msg.From,
			Quantity = tostring(amount)
		}
	})

	AccruedFeesAmount = 0
end)
