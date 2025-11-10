local bint = require('.bint')(256)

local utils = require('utils')
local json = require('json')
local fixed_price = require('fixed_price')
local dutch_auction = require('dutch_auction')
local english_auction = require('english_auction')
local activity = require('activity')

if Name ~= 'ANT Marketplace' then
	Name = 'ANT Marketplace'
end

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price
-- 		ExpirationTime
-- 		Type
-- 		MinimumPrice (dutch)
-- 		DecreaseInterval (dutch)
-- 		DecreaseStep (dutch)
-- 	} []
-- } []

if not Orderbook then
	Orderbook = {}
end

local ucm = {}

function ucm.getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
			break
		end
	end

	return pairIndex
end

-- Helper function to validate ANT dominant token orders (selling ANT for ARIO)
local function validateAntDominantOrder(args, validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(1) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'ANT tokens can only be sold in quantities of exactly 1',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Price is required when selling ANT
	if not args.price then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Price is required when selling ANT tokens',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Validate expiration time is valid
	local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.createdAt)
	if not isValidExpiration then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = expirationError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Validate price is valid
	local isValidPrice, priceError = utils.checkValidAmount(args.price)
	if not isValidPrice then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = priceError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	return true
end

-- Helper function to validate ARIO dominant token orders (buying ANT with ARIO)
local function validateArioDominantOrder(args, validPair)
	-- Currently no specific validation rules for ARIO dominant orders
	-- All general validations (quantity, pair, etc.) are handled in validateOrderParams
	-- This function is a placeholder for future ARIO-specific validation rules
	if not args.requestedOrderId then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Requested order ID is required',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	return true
end

-- Helper function to validate order parameters
local function validateOrderParams(args)
	-- 1. Check pair data
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })
	if not validPair then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- 2. Validate ARIO is in trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = arioError or 'Invalid trade - ARIO must be involved',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return nil
	end


	-- 3. Check quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- 4. Check order type is supported
	if not args.orderType or args.orderType ~= "fixed" and args.orderType ~= "dutch" and args.orderType ~= "english" then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Order type must be "fixed" or "dutch" or "english"',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end
	-- 5. Check if it's ANT dominant (selling ANT) or ARIO dominant (buying ANT)
	local isAntDominant = not utils.isArioToken(args.dominantToken)

	if isAntDominant then
		-- ANT dominant: validate ANT-specific requirements
		if not validateAntDominantOrder(args, validPair) then
			return nil
		end

		-- Dutch auction specific validation
		if args.orderType == "dutch" then
			local isValidDutch, dutchError = dutch_auction.validateDutchParams(args)
			if not isValidDutch then
				utils.handleError({
					Target = args.sender,
					Action = 'Validation-Error',
					Message = dutchError,
					Quantity = args.quantity,
					TransferToken = validPair[1],
					OrderGroupId = args.orderGroupId
				})
				return nil
			end
		end

	else
		-- ARIO dominant: validate ARIO-specific requirements
		if not validateArioDominantOrder(args, validPair) then
			return nil
		end
	end

	return validPair
end

-- Helper function to ensure trading pair exists in orderbook
local function ensurePairExists(validPair)
	local pairIndex = ucm.getPairIndex(validPair)

	-- Create new pair entry if it doesn't exist
	if pairIndex == -1 then
		table.insert(Orderbook, { Pair = validPair, Orders = {} })
		pairIndex = ucm.getPairIndex(validPair)
	end

	return pairIndex
end

local function handleAntOrderAuctions(args, validPair, pairIndex)
	if args.orderType == "fixed" then
		fixed_price.handleAntOrder(args, validPair, pairIndex)
	elseif args.orderType == "dutch" then
		dutch_auction.handleAntOrder(args, validPair, pairIndex)
	elseif args.orderType == "english" then
		english_auction.handleAntOrder(args, validPair, pairIndex)
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

local function handleArioOrderAuctions(args, validPair, pairIndex)

	-- Check if the desired token is already being sold (prevent duplicate sell orders)
	local currentOrders = Orderbook[pairIndex].Orders
	for _, existingOrder in ipairs(currentOrders) do
		if existingOrder.Token == args.dominantToken then
			utils.handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'This ANT token is already being sold - cannot create duplicate sell order',
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return
		end
	end

	if args.orderType == "fixed" then
		fixed_price.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == "dutch" then
		dutch_auction.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == "english" then
		english_auction.handleArioOrder(args, validPair, pairIndex)
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

function ucm.createOrder(args)
	-- Validate order parameters
	local validPair = validateOrderParams(args)
	if not validPair then
		return
	end

	-- Ensure trading pair exists in orderbook
	local pairIndex = ensurePairExists(validPair)

	if pairIndex > -1 then
		-- Check if the desired token is ARIO (add to orderbook) or ANT (immediate trade only)
		local isBuyingAnt = utils.isArioToken(args.dominantToken) -- If dominantToken is ARIO, we're buying ANT
		local isBuyingArio = not isBuyingAnt -- If dominantToken is not ARIO, we're selling ANT

		-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
		if isBuyingAnt then
			handleAntOrderAuctions(args, validPair, pairIndex)
			return
		end

		-- Handle ARIO token orders - add to orderbook for buy now
		if isBuyingArio then
			handleArioOrderAuctions(args, validPair, pairIndex)
			return
		end

		-- Placeholder for future order type handling
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return

	else
		-- Pair not found in orderbook (shouldn't happen after creation)
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

function ucm.settleAuction(args)
	english_auction.settleAuction(args)
end

-- Cancel an order
-- Accepts the original msg so we can keep consistent behavior and responses
function ucm.cancelOrder(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.OrderId then
			ao.send({
				Target = msg.From,
				Action = 'Input-Error',
				Tags = { Status = 'Error', Message = 'Invalid arguments, required { OrderId }' }
			})
			return
		end

		local activityData = activity.findOrderById(data.OrderId, msg.Timestamp)
		if not activityData then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Check if the sender is the order creator
		if msg.From ~= activityData.Sender then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Unauthorized to cancel this order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Block cancellation of English auctions that have bids
		if activityData.OrderType == 'english' and activityData.Bids and #activityData.Bids > 0 then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = {
					Status = 'Error',
					Message = 'You cannot cancel an English auction that has bids',
					['X-Group-ID'] = data['X-Group-ID'] or 'None',
					Handler = 'Cancel-Order'
				}
			})
			return
		end

		-- Only allow cancelling active or expired orders
		if activityData.Status ~= 'active' and activityData.Status ~= 'expired' then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order cannot be cancelled because it is not active or expired', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Find and remove order from orderbook
		local orderFound = false
		for pairIdx, pairData in ipairs(Orderbook) do
			for orderIdx, currentOrderEntry in ipairs(pairData.Orders) do
				if data.OrderId == currentOrderEntry.Id then
					-- Return funds to the creator
					ao.send({
						Target = currentOrderEntry.Token,
						Action = 'Transfer',
						Tags = {
							Recipient = currentOrderEntry.Creator,
							Quantity = currentOrderEntry.Quantity
						}
					})

					-- Remove the order from the orderbook
					table.remove(Orderbook[pairIdx].Orders, orderIdx)
					orderFound = true
					break
				end
			end
			if orderFound then break end
		end

		if orderFound then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Success', Message = 'Order cancelled', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})

			-- Record cancellation internally
			activity.recordCancelledOrder({
				Id = data.OrderId,
				DominantToken = activityData.DominantToken,
				SwapToken = activityData.SwapToken,
				Sender = msg.From,
				Receiver = nil,
				Quantity = tostring(activityData.Quantity),
				Price = tostring(activityData.Price),
				CreatedAt = msg.Timestamp,
				EndedAt = msg.Timestamp,
				CancellationTime = msg.Timestamp
			})
		else
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order not found in orderbook', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
		end
	else
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { OrderId }')
			}
		})
	end
end

return ucm
