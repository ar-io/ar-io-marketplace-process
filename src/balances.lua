
local json = require("json")
local bint = require('.bint')(256)
local balances = {}

--- Ensure an account exists in ARIOBalances with the correct structure
--- @param address Address The address to ensure exists
function balances.ensureAccountExists(address)
	if not ARIOBalances[address] then
		ARIOBalances[address] = {
			balance = '0',
			orders = {}
		}
	end
end

--- Transfer ARIO from one address to another within the marketplace
--- @param recipient Address The recipient address
--- @param from Address The sender address
--- @param qty BalanceAmount The quantity to transfer (string integer in mARIO)
--- @param allowUnsafeAddresses boolean Whether to allow non-standard addresses
--- @return table Balance update result with from and recipient balances
function balances.transfer(recipient, from, qty, allowUnsafeAddresses)
	local _utils = require("utils")
	assert(type(recipient) == "string", "Recipient is required!")
	assert(type(from) == "string", "From is required!")
	assert(from ~= recipient, "Cannot transfer to self")
	assert(_utils.isValidAOAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(bint(qty) ~= nil, "Quantity is required and must be a number!")
	assert(recipient ~= from, "Cannot transfer to self")
	assert(bint(qty) > 0, "Quantity must be greater than 0")

	balances.reduceBalance(from, qty)
	balances.increaseBalance(recipient, qty)

	return {
		[from] = balances.getBalance(from),
		[recipient] = balances.getBalance(recipient),
	}
end

--- Get the ARIO balance for a target address
--- @param target Address The address to check
--- @return BalanceAmount The balance as a string integer (or '0' if no balance)
function balances.getBalance(target)
	if not ARIOBalances[target] then
		return '0'
	end
	return ARIOBalances[target].balance or '0'
end

--- Get all ARIO balances (safe copy)
--- @return table<Address, BalanceAmount> Dictionary of address to balance (string integers)
function balances.getBalances()
	local balancesOnly = {}
	for address, account in pairs(ARIOBalances) do
		balancesOnly[address] = account.balance
	end
	return balancesOnly
end

--- Get all ARIO balances (unsafe - direct reference)
--- @return table<Address, BalanceAmount> Direct reference to ARIOBalances table
function balances.getBalancesUnsafe()
	return ARIOBalances or {}
end

--- Reduce the ARIO balance for a target address
--- @param target Address The address to reduce balance from
--- @param qty BalanceAmount The quantity to reduce (string integer in mARIO)
function balances.reduceBalance(target, qty)
	assert(balances.walletHasSufficientBalance(target, qty), "Insufficient balance")
	assert(bint(qty) > 0, "Quantity must be greater than 0")

	balances.ensureAccountExists(target)
	local prevBalance = balances.getBalance(target)
	ARIOBalances[target].balance = tostring(bint(prevBalance) - bint(qty))
end

--- Increase the ARIO balance for a target address
--- @param target Address The address to increase balance for
--- @param qty BalanceAmount The quantity to add (string integer in mARIO)
function balances.increaseBalance(target, qty)
	assert(bint(qty) ~= nil, "Quantity is required and must be a number!")
	assert(bint(qty) > 0, "Quantity must be greater than 0")

	balances.ensureAccountExists(target)
	local prevBalance = balances.getBalance(target)
	ARIOBalances[target].balance = tostring(bint(prevBalance) + bint(qty))
end

--- Gets paginated list of all balances
--- @param cursor Address|nil The address to start from
--- @param limit number Max number of results to return
--- @param sortBy string|nil Field to sort by
--- @param sortOrder string "asc" or "desc" sort direction
--- @return table Array of balance breakdown objects with address, balance, locked, total, orders
function balances.getPaginatedBalances(cursor, limit, sortBy, sortOrder)
	local _utils = require("utils")
	local balancesArray = {}
	local cursorField = "address" -- the cursor will be the wallet address
	for address, account in pairs(ARIOBalances) do
		local locked = balances.getUserTotalLockedBalance(address)
		local available = account.balance
		local total = bint(available) + bint(locked)

		table.insert(balancesArray, {
			address = address,
			balance = available, -- Available balance
			lockedBalance = locked, -- Total locked in orders
			totalBalance = tostring(total), -- Available + locked
			orders = account.orders or {}, -- Per-order locked amounts
		})
	end

	return _utils.paginateTableWithCursor(balancesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

--- Checks if a wallet has a sufficient balance
--- @param wallet Address The address of the wallet
--- @param quantity BalanceAmount The amount to check against the balance (string integer in mARIO)
--- @return boolean True if the wallet has a sufficient balance, false otherwise
function balances.walletHasSufficientBalance(wallet, quantity)
	local balance = balances.getBalance(wallet)
	if not balance or balance == '0' then
		return false
	end
	return bint(balance) >= bint(quantity)
end

--- Handle a deposit of ARIO into the marketplace
--- @param msg table The Credit-Notice message with Sender and Quantity tags
function balances.handleDeposit(msg)
	local _utils = require("utils")
	local sender = msg.Tags.Sender
	local quantity = msg.Tags.Quantity
	balances.increaseBalance(sender, quantity)
	_utils.Send(msg, { Target = sender, Action = "Deposit-Notice", Data = json.encode(quantity) })
end

--- Handler for withdrawing ARIO from the marketplace
--- @param msg table The message with Quantity tag
--- @return string JSON-encoded response with status and quantity
function balances.withdrawArioHandler(msg)
	local _utils = require("utils")
	local account = msg.From
	local quantity = msg.Tags.Quantity
	local recipient = msg.Tags.Recipient or account

	assert(quantity and _utils.checkValidAmount(quantity), "Invalid quantity. Must be integer greater than 0")
	assert(balances.walletHasSufficientBalance(account, quantity), "Insufficient balance")

	balances.reduceBalance(account, quantity)
	local ucm = require('ucm')  -- Lazy load to avoid circular dependency
	ucm.transfer(recipient, quantity, ARIO_TOKEN_PROCESS_ID, msg)

	return json.encode({
		Status = 'Success',
		Message = 'ARIO withdrawal initiated',
		Quantity = quantity,
		Recipient = recipient,
	})
end

--- Handler for getting paginated list of balances
--- @param msg table The message with pagination tags
--- @return string JSON-encoded paginated balances
function balances.getPaginatedBalancesHandler(msg)
	local _utils = require("utils")
	local page = _utils.parsePaginationTags(msg)
	local walletBalances = balances.getPaginatedBalances(page.cursor, page.limit, page.sortBy or "balance", page.sortOrder)
	return json.encode(walletBalances)
end

--- Handler for getting a single balance
--- @param msg table The message with optional Target/Address tag (defaults to msg.From)
--- @return string JSON-encoded balance data with breakdown
function balances.getBalanceHandler(msg)
	local target = msg.Tags.Target or msg.Tags.Address or msg.From
	local available = balances.getBalance(target)
	local locked = balances.getUserTotalLockedBalance(target)
	local total = bint(available) + bint(locked)

	balances.ensureAccountExists(target)

	local balanceData = {
		address = target,
		balance = available, -- Available balance
		lockedBalance = locked, -- Total locked in orders
		totalBalance = tostring(total), -- Available + locked
		orders = ARIOBalances[target].orders or {}, -- Per-order locked amounts
	}

	return json.encode(balanceData)
end

-- ============================================================================
-- Order Balance Locking (for bids and buy orders)
-- ============================================================================

--- Lock ARIO from available balance into an order
--- Used for both English auction bids and buy orders
--- @param orderId OrderId The order ID
--- @param user Address The user address (bidder or creator)
--- @param qty BalanceAmount The quantity to lock (string integer in mARIO)
function balances.lockBalanceForOrder(orderId, user, qty)
	assert(type(orderId) == "string", "OrderId is required!")
	assert(type(user) == "string", "User is required!")
	assert(bint(qty) > 0, "Quantity must be greater than 0")
	assert(balances.walletHasSufficientBalance(user, qty), "Insufficient balance to lock for order")

	balances.ensureAccountExists(user)

	-- Reduce from available balance
	balances.reduceBalance(user, qty)

	-- Add to locked orders
	local prevLocked = ARIOBalances[user].orders[orderId] or '0'
	ARIOBalances[user].orders[orderId] = tostring(bint(prevLocked) + bint(qty))
end

--- Unlock ARIO from an order to a recipient's available balance
--- Used when returning bids, cancelling orders, or settling auctions
--- @param orderId OrderId The order ID
--- @param user Address The user who locked the funds (bidder or creator)
--- @param recipient Address The address to receive the funds
--- @param qty BalanceAmount The quantity to unlock (string integer in mARIO)
function balances.unlockBalanceFromOrder(orderId, user, recipient, qty)
	assert(type(orderId) == "string", "OrderId is required!")
	assert(type(user) == "string", "User is required!")
	assert(type(recipient) == "string", "Recipient is required!")
	assert(bint(qty) > 0, "Quantity must be greater than 0")

	balances.ensureAccountExists(user)

	-- Check locked balance exists
	local lockedBalance = ARIOBalances[user].orders[orderId] or '0'
	assert(bint(lockedBalance) > 0, "No locked balance for this user on this order")
	assert(bint(lockedBalance) >= bint(qty), "Insufficient locked balance")

	-- Reduce from locked balance
	local newLockedBalance = bint(lockedBalance) - bint(qty)
	if newLockedBalance == bint(0) then
		ARIOBalances[user].orders[orderId] = nil
	else
		ARIOBalances[user].orders[orderId] = tostring(newLockedBalance)
	end

	-- Add to recipient's available balance
	balances.increaseBalance(recipient, qty)
end

--- Get locked balance for a specific user on an order
--- @param orderId OrderId The order ID
--- @param user Address The user address
--- @return BalanceAmount The locked balance (or '0' if none)
function balances.getOrderLockedBalance(orderId, user)
	if not ARIOBalances[user] or not ARIOBalances[user].orders then
		return '0'
	end
	return ARIOBalances[user].orders[orderId] or '0'
end

--- Get all locked balances for a specific order across all users
--- @param orderId OrderId The order ID
--- @return table<Address, BalanceAmount>|nil Map of user addresses to their locked amounts for this order
function balances.getOrderBalances(orderId)
	local orderBalances = {}
	local hasBalances = false

	for user, userBalance in pairs(ARIOBalances) do
		if userBalance.orders and userBalance.orders[orderId] then
			orderBalances[user] = userBalance.orders[orderId]
			hasBalances = true
		end
	end

	return hasBalances and orderBalances or nil
end

--- Get total locked balance across all orders for a user
--- @param user Address The address of the user
--- @return BalanceAmount The total locked amount (or '0' if none)
function balances.getUserTotalLockedBalance(user)
	if not ARIOBalances[user] or not ARIOBalances[user].orders then
		return '0'
	end

	local total = bint(0)
	for _, amount in pairs(ARIOBalances[user].orders) do
		total = total + bint(amount)
	end

	return tostring(total)
end

--- Get user's total balance breakdown (available + locked)
--- @param user Address The address of the user
--- @return table Balance breakdown with available, locked, and total
function balances.getUserBalanceBreakdown(user)
	local available = balances.getBalance(user)
	local locked = balances.getUserTotalLockedBalance(user)
	local total = bint(available) + bint(locked)

	return {
		available = available,
		locked = locked,
		total = tostring(total),
	}
end

return balances
