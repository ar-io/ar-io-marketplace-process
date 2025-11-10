local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

local activity = {}

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end
if not AuctionBids then AuctionBids = {} end

-- Normalize timestamp fields for a single order copy
local function normalizeOrderTimestamps(oc)
	if oc.CreatedAt then
		oc.CreatedAt = tonumber(oc.CreatedAt)
	end
	if oc.ExpirationTime then
		oc.ExpirationTime = tonumber(oc.ExpirationTime)
	end
	if oc.EndedAt then
		oc.EndedAt = tonumber(oc.EndedAt)
	end
	return oc
end

-- Helper: attach english-auction fields onto a single order-like table
local function applyEnglishAuctionFields(orderCopy)
	if orderCopy and orderCopy.OrderType == 'english' then
		local auctionBids = AuctionBids[orderCopy.OrderId]
		orderCopy.StartingPrice = orderCopy.StartingPrice or orderCopy.Price
		if auctionBids then
			orderCopy.Bids = auctionBids.Bids
			orderCopy.HighestBid = auctionBids.HighestBid
			orderCopy.HighestBidder = auctionBids.HighestBidder
			if auctionBids.Settlement then
				orderCopy.Settlement = auctionBids.Settlement
			end
		else
			orderCopy.Bids = {}
			orderCopy.HighestBid = orderCopy.HighestBid or nil
			orderCopy.HighestBidder = orderCopy.HighestBidder or nil
		end
	end
	return orderCopy
end

-- Pure status computation for orders currently in ListedOrders
local function computeListedStatus(order, now)
	local status = 'active'
	local endedAt = nil
	if order.ExpirationTime then
		local expirationTime = tonumber(order.ExpirationTime)
		if now >= expirationTime then
			if order.OrderType == 'english' then
				local auctionBids = AuctionBids[order.OrderId]
				if auctionBids and auctionBids.HighestBidder then
					status = 'ready-for-settlement'
				else
					status = 'expired'
					endedAt = expirationTime
				end
			else
				status = 'expired'
				endedAt = expirationTime
			end
		end
	end
	return status, endedAt
end

-- Decorate orders with normalized timestamps, auction fields, and type-specific extras
local function decorateOrder(order, status)
	local oc = utils.deepCopy(order)
	if status then oc.Status = status end
	oc = normalizeOrderTimestamps(oc)
	oc = applyEnglishAuctionFields(oc)
	if status == 'settled' then
		oc.Buyer = oc.Receiver
		if order.OrderType == 'dutch' or order.OrderType == 'fixed' then
			oc.FinalPrice = oc.Price
		end
	elseif status == 'expired' and oc.ExpirationTime and not oc.EndedAt then
		oc.EndedAt = oc.ExpirationTime
	end
	
	return oc
end

-- Build a unified, pure snapshot of all orders at a given time without mutating globals
local function getListedSnapshot(now)
	local active, ready, expired = {}, {}, {}
	for _, order in ipairs(ListedOrders) do
		local status, endedAt = computeListedStatus(order, now)
		local oc = decorateOrder(order, status)
		if endedAt then oc.EndedAt = endedAt end
		if status == 'active' then table.insert(active, oc)
		elseif status == 'ready-for-settlement' then table.insert(ready, oc)
		elseif status == 'expired' then table.insert(expired, oc)
		end
	end
	return active, ready, expired
end

local function getExecutedSnapshot()
	local executed = {}
	for _, order in ipairs(ExecutedOrders) do
		local oc = decorateOrder(order, 'settled')
		oc.EndedAt = oc.EndedAt or order.EndedAt or order.ExecutionTime
		table.insert(executed, oc)
	end
	return executed
end

local function getCancelledSnapshot()
	local cancelled = {}
	for _, order in ipairs(CancelledOrders) do
		local oc = decorateOrder(order, 'cancelled')
		oc.EndedAt = oc.EndedAt or order.EndedAt or order.CancellationTime
		table.insert(cancelled, oc)
	end
	return cancelled
end


-- Reusable state updater to move expired orders from Listed to Expired
-- updateOrderStates removed: we compute status on the fly for reads

-- Business logic for getting listed orders
function activity.getListedOrders(msg)
	local page = utils.parsePaginationTags(msg)

	local now = tonumber(msg.Timestamp)
	local active, ready = getListedSnapshot(now)
	local ordersArray = {}
	for _, oc in ipairs(active) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(ready) do table.insert(ordersArray, oc) end

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, 'CreatedAt', page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end

-- Business logic for getting completed orders
function activity.getCompletedOrders(msg)
	local page = utils.parsePaginationTags(msg)

	local now = tonumber(msg.Timestamp)
	local cancelled = getCancelledSnapshot()
	local settled = getExecutedSnapshot()
	local _, _, expired = getListedSnapshot(now)
	local ordersArray = {}
	for _, oc in ipairs(cancelled) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(settled) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(expired) do table.insert(ordersArray, oc) end

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, 'CreatedAt', page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end

-- Business logic for getting order by ID
function activity.getOrderById(msg)
	local orderId = msg.Tags.Orderid or msg.Tags.OrderId
	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	
	if (not decodeCheck or not data) and not orderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end
	if data and data.OrderId then
		orderId = data.OrderId
	end
	
	-- Final check		-- For English auctions, prefer Settlement.WinningBid; otherwise use recorded Price
	if not orderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end

	local now = tonumber(msg.Timestamp)
	local active, ready, expired = getListedSnapshot(now)
	local listedById = {}
	for _, oc in ipairs(active) do listedById[oc.OrderId] = oc end
	for _, oc in ipairs(ready) do listedById[oc.OrderId] = oc end
	for _, oc in ipairs(expired) do listedById[oc.OrderId] = oc end

	local executed = getExecutedSnapshot()
	local cancelled = getCancelledSnapshot()
	local executedById, cancelledById = {}, {}
	for _, oc in ipairs(executed) do executedById[oc.OrderId] = oc end
	for _, oc in ipairs(cancelled) do cancelledById[oc.OrderId] = oc end

	local foundOrder = cancelledById[orderId] or executedById[orderId] or listedById[orderId]
	local orderStatus = foundOrder and foundOrder.Status or nil

	if not foundOrder then
		ao.send({
			Target = msg.From,
			Action = 'Order-Not-Found',
			Message = 'Order with ID ' .. orderId .. ' not found'
		})
		return
	end

	-- foundOrder is already decorated by snapshot
	local response = foundOrder

	if msg.Tags.Functioninvoke or msg.Tags.FunctionInvoke then
		msg.reply({Data = json.encode(response)})
	else
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode(response)
		})
	end
end

-- Internal helper: find order by id without messaging
function activity.findOrderById(orderId, now)
    if not orderId then return nil end
    local nowNum = tonumber(now or 0)
    local active, ready, expired = getListedSnapshot(nowNum)
    local listedById = {}
    for _, oc in ipairs(active) do listedById[oc.OrderId] = oc end
    for _, oc in ipairs(ready) do listedById[oc.OrderId] = oc end
    for _, oc in ipairs(expired) do listedById[oc.OrderId] = oc end

    local executed = getExecutedSnapshot()
    local cancelled = getCancelledSnapshot()
    local executedById, cancelledById = {}, {}
    for _, oc in ipairs(executed) do executedById[oc.OrderId] = oc end
    for _, oc in ipairs(cancelled) do cancelledById[oc.OrderId] = oc end

    local foundOrder = cancelledById[orderId] or executedById[orderId] or listedById[orderId]
    return foundOrder
end

-- Business logic for getting activity
function activity.getActivity(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	-- If the data is not valid, set it to an empty object, returning everything as is
	if not decodeCheck then
		data = {}
	end

	local now = tonumber(msg.Timestamp)
	local active, ready, expired = getListedSnapshot(now)
	local executed = getExecutedSnapshot()
	local cancelled = getCancelledSnapshot()

	local filteredListedOrders = {}
	local filteredExecutedOrders = {}
	local filteredCancelledOrders = {}

	local function filterOrders(orders, assetIdsSet, owner, startDate, endDate)
		local filteredOrders = {}
		for _, order in ipairs(orders) do
			local isAssetMatch = not assetIdsSet or assetIdsSet[order.DominantToken]
			local isOwnerMatch = not owner or order.Sender == owner or order.Receiver == owner

			local isDateMatch = true
			if order.CreatedAt and (startDate or endDate) then
				local orderDate = bint(order.CreatedAt)

				if startDate then startDate = bint(startDate) end
				if endDate then endDate = bint(endDate) end

				if startDate and orderDate < startDate then
					isDateMatch = false
				end
				if endDate and orderDate > endDate then
					isDateMatch = false
				end
			end

			if isAssetMatch and isOwnerMatch and isDateMatch then
				table.insert(filteredOrders, order)
			end
		end
		return filteredOrders
	end

	local assetIdsSet = nil
	if data.AssetIds and #data.AssetIds > 0 then
		assetIdsSet = {}
		for _, assetId in ipairs(data.AssetIds) do
			assetIdsSet[assetId] = true
		end
	end

	local startDate = nil
	local endDate = nil
	if data.StartDate then startDate = data.StartDate end
	if data.EndDate then endDate = data.EndDate end

	local baseListed = {}
	for _, oc in ipairs(active) do table.insert(baseListed, oc) end
	for _, oc in ipairs(ready) do table.insert(baseListed, oc) end
	filteredListedOrders = filterOrders(baseListed, assetIdsSet, data.Address, startDate, endDate)
	filteredExecutedOrders = filterOrders(executed, assetIdsSet, data.Address, startDate, endDate)
	filteredCancelledOrders = filterOrders(cancelled, assetIdsSet, data.Address, startDate, endDate)

	-- All orders already decorated/normalized by snapshot
	local listedWithFields = filteredListedOrders
	local executedWithFields = filteredExecutedOrders
	local cancelledWithFields = filteredCancelledOrders
	-- Expired are from snapshot as well (no filter applied previously); apply filters if provided
	local expiredBase = expired
	local expiredWithFields = filterOrders(expiredBase, assetIdsSet, data.Address, startDate, endDate)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			ListedOrders = listedWithFields,
			ExecutedOrders = executedWithFields,
			CancelledOrders = cancelledWithFields,
			ExpiredOrders = expiredWithFields,
		})
	})
end

-- Business logic for getting order counts by address
function activity.getOrderCountsByAddress(msg)
	local salesByAddress = SalesByAddress
	local purchasesByAddress = PurchasesByAddress

	if msg.Tags.Count then
		local function getTopN(data, n)
			local sortedData = {}
			for k, v in pairs(data) do
				table.insert(sortedData, { key = k, value = v })
			end
			table.sort(sortedData, function(a, b) return a.value > b.value end)
			local topN = {}
			for i = 1, n do
				topN[sortedData[i].key] = sortedData[i].value
			end
			return topN
		end

		salesByAddress = getTopN(SalesByAddress, msg.Tags.Count)
		purchasesByAddress = getTopN(PurchasesByAddress, msg.Tags.Count)
	end

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			SalesByAddress = salesByAddress,
			PurchasesByAddress = purchasesByAddress
		})
	})
end

-- Business logic for getting sales by address
function activity.getSalesByAddress(msg)
	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			SalesByAddress = SalesByAddress
		})
	})
end

-- Business logic for updating executed orders
function activity.recordExecutedOrder(executedOrder)
    if not executedOrder or not executedOrder.Id then return end

    -- Search for the order in ListedOrders
    local foundOrder = nil
    for i, order in ipairs(ListedOrders) do
        if order.OrderId == executedOrder.Id then
            foundOrder = order
            table.remove(ListedOrders, i)
            break
        end
    end

    if not foundOrder then return end

    if foundOrder and foundOrder.OrderType == 'english' then
        foundOrder.StartingPrice = foundOrder.Price
    end

    foundOrder.EndedAt = executedOrder.EndedAt or executedOrder.ExecutionTime
    -- Merge execution payload fields to ensure buyer/price are recorded
    foundOrder.DominantToken = executedOrder.DominantToken or foundOrder.DominantToken
    foundOrder.SwapToken = executedOrder.SwapToken or foundOrder.SwapToken
    foundOrder.Sender = executedOrder.Sender or foundOrder.Sender
    foundOrder.Receiver = executedOrder.Receiver or foundOrder.Receiver
    foundOrder.Quantity = executedOrder.Quantity or foundOrder.Quantity
    foundOrder.Price = executedOrder.Price or foundOrder.Price

    -- Add the order to ExecutedOrders
    table.insert(ExecutedOrders, foundOrder)

    if foundOrder.Sender then
        if not SalesByAddress[foundOrder.Sender] then
            SalesByAddress[foundOrder.Sender] = 0
        end
        SalesByAddress[foundOrder.Sender] = SalesByAddress[foundOrder.Sender] + 1
    end

    if foundOrder.Receiver then
        if not PurchasesByAddress[foundOrder.Receiver] then
            PurchasesByAddress[foundOrder.Receiver] = 0
        end
        PurchasesByAddress[foundOrder.Receiver] = PurchasesByAddress[foundOrder.Receiver] + 1
    end
end

function activity.recordListedOrder(order)
    if not order or not order.Id then return end
    table.insert(ListedOrders, {
        OrderId = order.Id,
        DominantToken = order.DominantToken,
        SwapToken = order.SwapToken,
        Sender = order.Sender,
        Receiver = nil,
        Quantity = order.Quantity,
        Price = order.Price,
        CreatedAt = order.CreatedAt,
        OrderType = order.OrderType,
        MinimumPrice = order.MinimumPrice,
        DecreaseInterval = order.DecreaseInterval,
        DecreaseStep = order.DecreaseStep,
        ExpirationTime = order.ExpirationTime
    })
end

function activity.recordCancelledOrder(order)
    if not order or not order.Id then return end
    local foundOrder = nil
    for i, o in ipairs(ListedOrders) do
        if o.OrderId == order.Id then
            foundOrder = o
            table.remove(ListedOrders, i)
            break
        end
    end
    if not foundOrder then return end
    foundOrder.EndedAt = order.EndedAt or order.CancellationTime
    table.insert(CancelledOrders, foundOrder)
end

function activity.recordAuctionBid(bid)
    if not bid or not bid.OrderId then return end
    local orderId = bid.OrderId
    if not AuctionBids[orderId] then
        AuctionBids[orderId] = { Bids = {}, HighestBid = nil, HighestBidder = nil }
    end
    table.insert(AuctionBids[orderId].Bids, {
        Bidder = bid.Bidder,
        Amount = bid.Amount,
        Timestamp = bid.Timestamp,
        OrderId = bid.OrderId
    })
    if not AuctionBids[orderId].HighestBid or bint(bid.Amount) > bint(AuctionBids[orderId].HighestBid) then
        AuctionBids[orderId].HighestBid = bid.Amount
        AuctionBids[orderId].HighestBidder = bid.Bidder
    end
end

function activity.recordAuctionSettlement(settlement)
    if not settlement or not settlement.OrderId then return end
    local orderId = settlement.OrderId
    if AuctionBids[orderId] then
        AuctionBids[orderId].Settlement = {
            Winner = settlement.Winner,
            Quantity = settlement.Quantity,
            Timestamp = settlement.Timestamp
        }
    end
end

-- Business logic for getting volume
function activity.getVolume(msg)
	local function validNumber(value)
		return type(value) == 'number' or (type(value) == 'string' and tonumber(value) ~= nil)
	end

	local totalVolume = bint(0)
	for _, order in ipairs(ExecutedOrders) do
		if order.Receiver and order.Quantity and validNumber(order.Quantity) and order.Price and validNumber(order.Price) then
			local price = bint(math.floor(order.Price)) // bint(1000000000000)

			local quantity = bint(math.floor(order.Quantity))
			if order.DominantToken == 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY' then
				quantity = quantity // bint(1000000000000)
			end
			if order.DominantToken == 'Btm_9_fvwb7eXbQ2VswA4V19HxYWnFsYRB4gIl3Dahw' then
				quantity = quantity // bint(1000000000000)
			end

			totalVolume = totalVolume + quantity * price
		end
	end

	print('Total Volume: ' .. tostring(totalVolume))

	ao.send({
		Target = msg.From,
		Action = 'Volume-Notice',
		Volume = tostring(totalVolume)
	})
end

-- Business logic for getting most traded tokens
function activity.getMostTradedTokens(msg)
	local tokenVolumes = {}

	for _, order in ipairs(ExecutedOrders) do
		if order.DominantToken and order.Quantity and type(order.Quantity) == 'string' then
			local quantity = bint(math.floor(order.Quantity))
			tokenVolumes[order.DominantToken] = (tokenVolumes[order.DominantToken] or bint(0)) + quantity
		end
	end

	local sortedTokens = {}
	for token, volume in pairs(tokenVolumes) do
		table.insert(sortedTokens, { token = token, volume = volume })
	end

	table.sort(sortedTokens, function(a, b) return a.volume > b.volume end)

	local topN = tonumber(msg.Tags.Count) or 10
	local result = {}
	for i = 1, math.min(topN, #sortedTokens) do
		result[i] = {
			Token = sortedTokens[i].token,
			Volume = tostring(sortedTokens[i].volume)
		}
	end

	ao.send({
		Target = msg.From,
		Action = 'Most-Traded-Tokens-Result',
		Data = json.encode(result)
	})
end

-- Business logic for getting activity lengths
function activity.getActivityLengths(msg)
	local function countTableEntries(tbl)
		local count = 0
		for _ in pairs(tbl) do
			count = count + 1
		end
		return count
	end

	ao.send({
		Target = msg.From,
		Action = 'Table-Lengths-Result',
		Data = json.encode({
			ListedOrders = #ListedOrders,
			ExecutedOrders = #ExecutedOrders,
			CancelledOrders = #CancelledOrders,
			SalesByAddress = countTableEntries(SalesByAddress),
			PurchasesByAddress = countTableEntries(PurchasesByAddress)
		})
	})
end

-- Business logic for migrate activity dryrun
function activity.migrateActivityDryrun(msg)
	local orderTable = {}
	local orderType = msg.Tags['Order-Type']
	local stepBy = tonumber(msg.Tags['Step-By'])
	if orderType == 'ListedOrders' then
		orderTable = table.move(
			ListedOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	elseif orderType == 'ExecutedOrders' then
		orderTable = table.move(
			ExecutedOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	elseif orderType == 'CancelledOrders' then
		orderTable = table.move(
			CancelledOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	else
		print('Invalid Order-Type: ' .. orderType)
		return
	end
end

-- Business logic for migrate activity
function activity.migrateActivity(msg)
	if msg.From ~= ao.id and msg.From ~= Owner then return end
	print('Starting migration process...')

	local function sendBatch(orders, orderType, startIndex)
		local batch = {}

		for i = startIndex, math.min(startIndex + 29, #orders) do
			table.insert(batch, {
				OrderId = orders[i].OrderId or '',
				DominantToken = orders[i].DominantToken or '',
				SwapToken = orders[i].SwapToken or '',
				Sender = orders[i].Sender or '',
				Receiver = orders[i].Receiver or nil,
				Quantity = orders[i].Quantity and tostring(orders[i].Quantity) or '0',
				Price = orders[i].Price and tostring(orders[i].Price) or '0',
				Timestamp = orders[i].Timestamp or ''
			})
		end

		if #batch > 0 then
			print('Sending ' .. orderType .. ' Batch: ' .. #batch .. ' orders starting at index ' .. startIndex)

			local success, encoded = pcall(json.encode, batch)
			if not success then
				print('Failed to encode batch: ' .. tostring(encoded))
				return
			end

			ao.send({
				Target = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4',
				Action = 'Migrate-Activity-Batch',
				Tags = {
					['Order-Type'] = orderType,
					['Start-Index'] = tostring(startIndex)
				},
				Data = encoded
			})
		end
	end

	local orderType = msg.Tags['Order-Type']
	if not orderType then
		print('No Order-Type specified in message tags')
		return
	end

	local orderTable
	if orderType == 'ListedOrders' then
		orderTable = ListedOrders
	elseif orderType == 'ExecutedOrders' then
		orderTable = ExecutedOrders
	elseif orderType == 'CancelledOrders' then
		orderTable = CancelledOrders
	else
		print('Invalid Order-Type: ' .. orderType)
		return
	end

	print('Starting ' .. orderType .. 'Orders migration (total: ' .. #orderTable .. ')')
	sendBatch(orderTable, orderType, tonumber(msg.Tags.StartIndex))
	print('Migration initiation completed')
end

-- Business logic for migrate activity batch
function activity.migrateActivityBatch(msg)
	if msg.Owner ~= Owner then
		print('Rejected batch: unauthorized sender')
		return
	end

	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	if not decodeCheck or not data then
		print('Failed to decode batch data')
		return
	end

	local orderType = msg.Tags['Order-Type']
	local startIndex = tonumber(msg.Tags['Start-Index'])
	if not orderType or not startIndex then
		print('Missing required tags in batch message')
		return
	end

	print('Processing ' .. orderType .. ' batch: ' .. #data .. ' orders at index ' .. startIndex)

	-- Select the appropriate table based on order type
	local targetTable
	if orderType == 'ListedOrders' then
		targetTable = ListedOrders
	elseif orderType == 'ExecutedOrders' then
		targetTable = ExecutedOrders
	elseif orderType == 'CancelledOrders' then
		targetTable = CancelledOrders
	else
		print('Invalid order type: ' .. orderType)
		return
	end

	local existingOrders = {}
	for _, order in ipairs(targetTable) do
		if order.OrderId then
			existingOrders[order.OrderId] = true
		end
	end

	-- Insert only non-duplicate orders
	local insertedCount = 0
	for _, order in ipairs(data) do
		if order.OrderId and not existingOrders[order.OrderId] then
			table.insert(targetTable, order)
			existingOrders[order.OrderId] = true
			insertedCount = insertedCount + 1
		end
	end

	print('Successfully processed ' .. orderType .. ' batch of ' .. #data .. ' orders')

	ao.send({
		Target = msg.From,
		Action = 'Batch-Processed'
	})
end

-- Business logic for migrate activity stats
function activity.migrateActivityStats(msg)
	if msg.From ~= '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4' then
		print('Rejected stats: unauthorized sender')
		return
	end

	local decodeCheck, stats = utils.decodeMessageData(msg.Data)
	if not decodeCheck or not stats then
		print('Failed to decode stats data')
		return
	end

	print('Processing address statistics...')

	-- Update the tables
	if stats.SalesByAddress then
		SalesByAddress = stats.SalesByAddress
	end

	if stats.PurchasesByAddress then
		PurchasesByAddress = stats.PurchasesByAddress
	end

	print('Successfully processed address statistics')
end

-- Helper function to record match and send activity data
function activity.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
	-- Record the successful match
	local match = {
		Id = currentOrderEntry.Id,
		Quantity = calculatedFillAmount,
		Price = tostring(currentOrderEntry.Price)
	}

	-- Record execution internally (no messaging)
	activity.recordExecutedOrder({
		Id = currentOrderEntry.Id,
		MatchId = args.orderId,
		DominantToken = validPair[2],
		SwapToken = validPair[1],
		Sender = currentOrderEntry.Creator,
		Receiver = args.sender,
		Quantity = calculatedFillAmount,
		Price = args.executionPrice or tostring(currentOrderEntry.Price),
		CreatedAt = args.createdAt,
		EndedAt = args.createdAt,
		ExecutionTime = args.createdAt
	})

	return match
end

activity._internal = {
	normalizeOrderTimestamps = normalizeOrderTimestamps,
	applyEnglishAuctionFields = applyEnglishAuctionFields,
	computeListedStatus = computeListedStatus,
	decorateOrder = decorateOrder,
	getListedSnapshot = getListedSnapshot,
	getExecutedSnapshot = getExecutedSnapshot,
	getCancelledSnapshot = getCancelledSnapshot
}
return activity
