print('\n=== Loading utils module for testing ===')
require('test_globals')
local utils = require('utils')
print('✓ utils module loaded')
local json = require('json')
print('✓ json module loaded')
local bint = require('.bint')(256)
print('✓ bint module loaded')

describe('utils', function()
	print('\n--- Starting utils tests ---')
	-- Mock ao.send and reset state between tests that need it
	local sentMessages
	local function resetMocks()
		sentMessages = {}
		---@diagnostic disable-next-line: duplicate-set-field
		_G.ao.send = function(msg)
			table.insert(sentMessages, msg)
		end
	end

	describe('calculateFillAmount', function()
		local testCases = {
			{ input = 0, expected = '0', description = 'zero integer' },
			{ input = 1, expected = '1', description = 'positive integer' },
			{ input = 1.0, expected = '1', description = 'integer as float' },
			{ input = 1.999999, expected = '1', description = 'positive float truncation' },
			{ input = 123456789.987, expected = '123456789', description = 'large float truncation' },
			{ input = -1.1, expected = '-2', description = 'negative float floors down' },
		}

		for _, tc in ipairs(testCases) do
			it('returns ' .. tc.expected .. ' for ' .. tc.description, function()
				assert.are.equal(tc.expected, utils.calculateFillAmount(tc.input))
			end)
		end
	end)

	describe('calculateSendAmount and calculateFeeAmount', function()
		local function expectedSend(amount)
			return tostring((bint(amount) * bint(995)) // bint(1000))
		end

		local function expectedFee(amount)
			return tostring((bint(amount) * bint(5)) // bint(10000))
		end

		local cases = {
			{ amount = '0', desc = 'zero amount' },
			{ amount = '1', desc = 'smallest positive amount' },
			{ amount = '1000', desc = 'round division threshold' },
			{ amount = '999999999999999999999999', desc = 'very large amount' },
			{ amount = '123456789012345678901234567890', desc = 'extremely large amount' },
		}

		for _, c in ipairs(cases) do
			it('calculateSendAmount for ' .. c.desc, function()
				assert.are.equal(expectedSend(c.amount), utils.calculateSendAmount(c.amount))
			end)

			it('calculateFeeAmount for ' .. c.desc, function()
				assert.are.equal(expectedFee(c.amount), utils.calculateFeeAmount(c.amount))
			end)
		end
	end)

	describe('checkValidAddress', function()
		local testCases = {
			-- Valid addresses
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid 43-character alphanumeric address',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9_wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address with underscores',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address with hyphens',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address with mixed alphanumeric, underscore, and hyphen',
			},
			{
				input = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
				expected = true,
				description = 'valid 43-character address with only letters',
			},
			{
				input = '1234567890123456789012345678901234567890123',
				expected = true,
				description = 'valid 43-character address with only numbers',
			},
			{
				input = '___________________________________________',
				expected = true,
				description = 'valid 43-character address with only underscores',
			},
			{
				input = '-------------------------------------------',
				expected = true,
				description = 'valid 43-character address with only hyphens',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address with mixed case letters',
			},
			{
				input = '_aXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address starting with underscore',
			},
			{
				input = '-aXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				expected = true,
				description = 'valid address starting with hyphen',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64_',
				expected = true,
				description = 'valid address ending with underscore',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64-',
				expected = true,
				description = 'valid address ending with hyphen',
			},
			-- Invalid addresses
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64',
				expected = false,
				description = 'address that is too short (42 characters)',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64Mx',
				expected = false,
				description = 'address that is too long (44 characters)',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9 wB0npVviewTkUbh2Yk64M',
				expected = false,
				description = 'address containing spaces',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9@wB0npVviewTkUbh2Yk64M',
				expected = false,
				description = 'address containing special symbols',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9.wB0npVviewTkUbh2Yk64M',
				expected = false,
				description = 'address containing dots',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9\nwB0npVviewTkUbh2Yk64M',
				expected = false,
				description = 'address containing newline character',
			},
			{
				input = 'SaXnsUgxJLkJRghWQOUs9\twB0npVviewTkUbh2Yk64M',
				expected = false,
				description = 'address containing tab character',
			},
			{
				input = nil,
				expected = false,
				description = 'nil input',
			},
			{
				input = '',
				expected = false,
				description = 'empty string',
			},
			{
				input = 123456789,
				expected = false,
				description = 'non-string input (number)',
			},
			{
				input = {},
				expected = false,
				description = 'non-string input (table)',
			},
			{
				input = true,
				expected = false,
				description = 'non-string input (boolean)',
			},
		}

		for _, testCase in ipairs(testCases) do
			it('should return ' .. tostring(testCase.expected) .. ' for ' .. testCase.description, function()
				assert.are.equal(testCase.expected, utils.checkValidAddress(testCase.input))
			end)
		end
	end)

	describe('checkValidAmount', function()
		local testCases = {
			-- Valid positive amounts
			{ input = '1', expected = true, description = 'positive amount as string' },
			{ input = 1, expected = true, description = 'positive amount as number' },
			{
				input = '5000000000000000000000000',
				expected = true,
				description = 'very large positive amount as string',
			},
			-- Zero and negative
			{ input = '0', expected = false, description = 'zero amount as string' },
			{ input = '-1', expected = false, description = 'negative amount as string' },
		}

		for _, tc in ipairs(testCases) do
			it('should return ' .. tostring(tc.expected) .. ' for ' .. tc.description, function()
				assert.are.equal(tc.expected, utils.checkValidAmount(tc.input))
			end)
		end
	end)

	describe('checkValidExpirationTime', function()
		local testCases = {
			{ exp = nil, ts = '1000', expected = { true, nil }, description = 'nil expiration allowed' },
			{
				exp = '0',
				ts = '1000',
				expected = { false, 'Expiration time must be a valid positive integer' },
				description = 'zero is invalid',
			},
			{
				exp = '-1',
				ts = '1000',
				expected = { false, 'Expiration time must be a valid positive integer' },
				description = 'negative is invalid',
			},
			{
				exp = 'abc',
				ts = '1000',
				expected = { false, 'Expiration time must be a valid positive integer' },
				description = 'non-numeric expiration',
			},
			{
				exp = '1000',
				ts = '1000',
				expected = { false, 'Expiration time must be greater than current timestamp' },
				description = 'equal to current timestamp',
			},
			{
				exp = '999',
				ts = '1000',
				expected = { false, 'Expiration time must be greater than current timestamp' },
				description = 'less than current timestamp',
			},
			{ exp = '1001', ts = '1000', expected = { true, nil }, description = 'greater than current timestamp' },
			{
				exp = '1001',
				ts = 'abc',
				expected = { false, 'Expiration time must be a valid timestamp' },
				description = 'invalid current timestamp',
			},
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				local ok, err = utils.checkValidExpirationTime(tc.exp, tc.ts)
				assert.are.equal(tc.expected[1], ok)
				assert.are.equal(tc.expected[2], err)
			end)
		end
	end)

	describe('isExpired', function()
		local testCases = {
			{ exp = nil, ts = 1000, expected = false, description = 'nil expiration returns false' },
			{ exp = nil, ts = '1000', expected = false, description = 'nil expiration with string timestamp' },
			{ exp = '1000', ts = 1001, expected = true, description = 'expiration < timestamp (expired)' },
			{ exp = 1000, ts = '1001', expected = true, description = 'expiration < timestamp (both types)' },
			{ exp = '1001', ts = 1000, expected = false, description = 'expiration > timestamp (not expired)' },
			{ exp = 1001, ts = '1000', expected = false, description = 'expiration > timestamp (mixed types)' },
			{ exp = '1000', ts = 1000, expected = true, description = 'expiration == timestamp (expired)' },
			{ exp = 1000, ts = 1000, expected = true, description = 'expiration == timestamp (both numbers)' },
			{ exp = '999', ts = '1000', expected = true, description = 'past expiration (both strings)' },
			{ exp = '1000000', ts = '999', expected = false, description = 'future expiration (both strings)' },
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				assert.are.equal(tc.expected, utils.isExpired(tc.exp, tc.ts))
			end)
		end
	end)

	describe('createFilterFunction', function()
		local items = {
			{ id = 'a', status = 'active', count = 1 },
			{ id = 'b', status = 'inactive', count = 2 },
			{ id = 'c', status = 'active', count = 2 },
			{ id = 'd', status = 'active', count = '2' },
		}

		it('single field match', function()
			local filterFn = utils.createFilterFunction({ status = 'active' })
			local result = utils.filterArray(items, function(_, v)
				return filterFn(v)
			end)
			assert.are.same({
				{ id = 'a', status = 'active', count = 1 },
				{ id = 'c', status = 'active', count = 2 },
				{ id = 'd', status = 'active', count = '2' },
			}, result)
		end)

		it('multi-field match', function()
			local filterFn = utils.createFilterFunction({ status = 'active', count = 2 })
			local result = utils.filterArray(items, function(_, v)
				return filterFn(v)
			end)
			assert.are.same({
				{ id = 'c', status = 'active', count = 2 },
			}, result)
		end)

		it('non-matching filter returns empty', function()
			local filterFn = utils.createFilterFunction({ status = 'pending' })
			local result = utils.filterArray(items, function(_, v)
				return filterFn(v)
			end)
			assert.are.same({}, result)
		end)

		it('empty filter allows all', function()
			local filterFn = utils.createFilterFunction({})
			local result = utils.filterArray(items, function(_, v)
				return filterFn(v)
			end)
			assert.are.same(items, result)
		end)

		it('type sensitive comparisons', function()
			local filterFn = utils.createFilterFunction({ count = 2 })
			local result = utils.filterArray(items, function(_, v)
				return filterFn(v)
			end)
			assert.are.same({
				{ id = 'b', status = 'inactive', count = 2 },
				{ id = 'c', status = 'active', count = 2 },
			}, result)
		end)
	end)

	describe('createLookupTable', function()
		it('nil input returns empty table', function()
			---@diagnostic disable-next-line: param-type-mismatch
			assert.are.same({}, utils.createLookupTable(nil))
		end)

		it('empty table returns empty table', function()
			assert.are.same({}, utils.createLookupTable({}))
		end)

		it('array values default to true', function()
			assert.are.same({ a = true, b = true, c = true }, utils.createLookupTable({ 'a', 'b', 'c' }))
		end)

		it('object values default to true', function()
			assert.are.same({ x = true, y = true }, utils.createLookupTable({ k1 = 'x', k2 = 'y' }))
		end)

		it('custom valueFn maps to key:value', function()
			local input = { foo = 'X', bar = 'Y' }
			local result = utils.createLookupTable(input, function(key, value)
				return key .. ':' .. value
			end)
			assert.are.same({ X = 'foo:X', Y = 'bar:Y' }, result)
		end)
	end)

	describe('decodeMessageData', function()
		local testCases = {
			{
				input = json.encode({ a = 1, b = 'x' }),
				expected = { true, { a = 1, b = 'x' } },
				description = 'valid JSON object',
			},
			{ input = json.encode({ 1, 2, 3 }), expected = { true, { 1, 2, 3 } }, description = 'valid JSON array' },
			{ input = '{"a":1,', expected = { false, nil }, description = 'malformed JSON' },
			{ input = '', expected = { false, nil }, description = 'empty string' },
			{ input = nil, expected = { false, nil }, description = 'nil input' },
		}

		for _, tc in ipairs(testCases) do
			it('should return ' .. tostring(tc.expected[1]) .. ' for ' .. tc.description, function()
				local ok, decoded = utils.decodeMessageData(tc.input)
				assert.are.equal(tc.expected[1], ok)
				assert.are.same(tc.expected[2], decoded)
			end)
		end
	end)

	describe('deepCopy', function()
		it('nil returns nil', function()
			assert.is_nil(utils.deepCopy(nil))
		end)

	it('number primitive returns as-is', function()
		---@diagnostic disable-next-line: param-type-mismatch
		assert.are.equal(42, utils.deepCopy(42))
	end)

	it('string primitive returns as-is', function()
		---@diagnostic disable-next-line: param-type-mismatch
		assert.are.equal('hello', utils.deepCopy('hello'))
	end)

		it('copies nested tables', function()
			local src = { a = 1, b = { c = 2, d = { e = 3 } } }
			local copy = utils.deepCopy(src)
			-- mutate source to ensure no aliasing
			src.b.d.e = 99
			assert.are.same({ a = 1, b = { c = 2, d = { e = 3 } } }, copy)
		end)

		it('excludes top-level keys', function()
			local src = { a = 1, b = 2, c = 3 }
			assert.are.same({ a = 1, c = 3 }, utils.deepCopy(src, { 'b' }))
		end)

		it('excludes nested dot-path keys', function()
			local src = { user = { id = 'u1', profile = { name = 'N', email = 'E' } }, other = 7 }
			assert.are.same(
				{ user = { id = 'u1', profile = { name = 'N' } }, other = 7 },
				utils.deepCopy(src, { 'user.profile.email' })
			)
		end)

		it('excludes array indices and reindexes sequentially', function()
			local src = { 10, 20, 30, 40 }
			-- exclude the 2nd element
			assert.are.same({ 10, 30, 40 }, utils.deepCopy(src, { '2' }))
		end)

		it('excludes nested array index via dot path', function()
			local src = { users = { { id = 'a' }, { id = 'b' }, { id = 'c' } } }
			assert.are.same({ users = { { id = 'a' }, { id = 'c' } } }, utils.deepCopy(src, { 'users.2' }))
		end)
	end)

	describe('executeTokenTransfers', function()
		local SELL_TOKEN = 'SELL_TOKEN_PROCESS'
		local BUY_TOKEN = 'BUY_TOKEN_PROCESS'

		local function makeOrderEntry(overrides)
			local base = {
				creator = 'seller-addr',
			}
			for k, v in pairs(overrides or {}) do
				base[k] = v
			end
			return base
		end

		local testCases = {
			{
				description = 'sends tokens to seller and buyer with expected quantities (no fees recorded)',
				args = {
					sender = 'buyer-addr',
					dominantToken = SELL_TOKEN,
					swapToken = BUY_TOKEN,
					currentOrderEntry = makeOrderEntry({}),
					calculatedSendAmount = '995',
					calculatedFillAmount = '1',
					msg = { Tags = {} },
				},
				expectedMessages = {
					{
						Target = SELL_TOKEN,
						Action = 'Transfer',
						Tags = { Recipient = 'seller-addr', Quantity = '995' },
					},
					{ Target = BUY_TOKEN, Action = 'Transfer', Tags = { Recipient = 'buyer-addr', Quantity = '1' } },
				},
				expectedFeeDelta = 0,
			},
			-- NOTE: Fee recording has been moved to sendFeeToTreasury (called before executeTokenTransfers)
			-- executeTokenTransfers no longer handles fee calculation/recording
			{
				description = 'does not record fee when original equals calculated',
				args = {
					sender = 'buyer-addr',
					dominantToken = SELL_TOKEN,
					swapToken = BUY_TOKEN,
					originalSendAmount = '995',
					currentOrderEntry = makeOrderEntry({}),
					calculatedSendAmount = '995',
					calculatedFillAmount = '1',
					msg = { Tags = {} },
				},
				expectedMessages = {
					{
						Target = SELL_TOKEN,
						Action = 'Transfer',
						Tags = { Recipient = 'seller-addr', Quantity = '995' },
					},
					{ Target = BUY_TOKEN, Action = 'Transfer', Tags = { Recipient = 'buyer-addr', Quantity = '1' } },
				},
				expectedFeeDelta = 0,
			},
			{
				description = 'does not record fee when original less than calculated',
				args = {
					sender = 'buyer-addr',
					dominantToken = SELL_TOKEN,
					swapToken = BUY_TOKEN,
					originalSendAmount = '990',
					currentOrderEntry = makeOrderEntry({}),
					calculatedSendAmount = '995',
					calculatedFillAmount = '1',
					msg = { Tags = {} },
				},
				expectedMessages = {
					{
						Target = SELL_TOKEN,
						Action = 'Transfer',
						Tags = { Recipient = 'seller-addr', Quantity = '995' },
					},
					{ Target = BUY_TOKEN, Action = 'Transfer', Tags = { Recipient = 'buyer-addr', Quantity = '1' } },
				},
				expectedFeeDelta = 0,
			},
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				resetMocks()
				local ucm = require('ucm')
				local beforeFees = _G.AccruedFeesAmount or '0'
				ucm.executeTokenTransfers(tc.args)
				local afterFees = _G.AccruedFeesAmount or '0'
				-- Need to check if Tags contain X-Intent-Id (should be nil when no parent intent)
				for _, msg in ipairs(sentMessages) do
					if msg.Tags then
						msg.Tags['X-Intent-Id'] = nil -- Clear for comparison
					end
				end
				assert.are.same(tc.expectedMessages, sentMessages)
				local feeDelta = tostring(bint(afterFees) - bint(beforeFees))
				assert.are.equal(tostring(tc.expectedFeeDelta), feeDelta)
			end)
		end
	end)

	describe('filterArray', function()
		it('empty input returns empty array', function()
			assert.are.same(
				{},
				utils.filterArray({}, function()
					return true
				end)
			)
		end)

		local items = { 1, 2, 3, 4, 5 }

		it('match all', function()
			assert.are.same(
				{ 1, 2, 3, 4, 5 },
				utils.filterArray(items, function()
					return true
				end)
			)
		end)

		it('match none', function()
			assert.are.same(
				{},
				utils.filterArray(items, function()
					return false
				end)
			)
		end)

		it('value-based predicate keeps evens', function()
			assert.are.same(
				{ 2, 4 },
				utils.filterArray(items, function(_, v)
					return v % 2 == 0
				end)
			)
		end)

		it('index-based predicate keeps odd indices', function()
			assert.are.same(
				{ 1, 3, 5 },
				utils.filterArray(items, function(i)
					return i % 2 == 1
				end)
			)
		end)

		it('preserves order of passing elements', function()
			local input = { 'a', 'b', 'c', 'd' }
			assert.are.same(
				{ 'a', 'c' },
				utils.filterArray(input, function(_, v)
					return v ~= 'b' and v ~= 'd'
				end)
			)
		end)
	end)

	describe('handleError', function()
		local validTarget = 'error-target-process'

		local testCases = {
			{
				description = 'sends error notice (no refund - handleError only sends notices)',
				args = {
					target = validTarget,
					action = 'Some-Error',
					message = 'Something went wrong',
				},
				expected = {
					{
						Target = validTarget,
						Action = 'Some-Error',
						Error = 'Something went wrong',
						Tags = { Status = 'Error', Message = 'Something went wrong' },
					},
				},
			},
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				resetMocks()
				utils.handleError(tc.args)
				assert.are.same(tc.expected, sentMessages)
			end)
		end
	end)

	describe('isArioToken', function()
		local TEST_ARIO_ID = 'TEST_ARIO_PROCESS_ID_ABCDEFGHIJKLMNOPQRSTUVWXYZ'

		before_each(function()
			_G.ARIO_TOKEN_PROCESS_ID = TEST_ARIO_ID
		end)

		local testCases = {
			{ input = TEST_ARIO_ID, expected = true, description = 'exact match to ARIO token id' },
			{ input = TEST_ARIO_ID .. 'X', expected = false, description = 'non-match different string' },
			{ input = string.lower(TEST_ARIO_ID), expected = false, description = 'case-sensitive non-match' },
			{ input = 'some-other-token-id', expected = false, description = 'completely different token id' },
			{ input = nil, expected = false, description = 'nil input' },
		}

		for _, tc in ipairs(testCases) do
			it('should return ' .. tostring(tc.expected) .. ' for ' .. tc.description, function()
				assert.are.equal(tc.expected, utils.isArioToken(tc.input))
			end)
		end
	end)

	describe('paginateTableWithCursor', function()
		local function clone(tbl)
			local c = {}
			for i, v in ipairs(tbl) do
				c[i] = v
			end
			return c
		end

		local baseItems = {
			{ Id = 'A', CreatedAt = 1000, Status = 'active' },
			{ Id = 'B', CreatedAt = 1001, Status = 'inactive' },
			{ Id = 'C', CreatedAt = 1002, Status = 'active' },
			{ Id = 'D', CreatedAt = 1003, Status = 'active' },
		}

		it('empty input returns empty page', function()
			local res = utils.paginateTableWithCursor({}, nil, 'Id', 2, nil, 'desc', nil)
			assert.are.same({
				items = {},
				limit = 2,
				totalItems = 0,
				sortBy = 'CreatedAt',
				sortOrder = 'desc',
				nextCursor = nil,
				hasMore = false,
			}, res)
		end)

		it('first page default sort desc by CreatedAt', function()
			local items = clone(baseItems)
			local res = utils.paginateTableWithCursor(items, nil, 'Id', 2, nil, 'desc', nil)
			assert.are.same({
				items = {
					{ Id = 'D', CreatedAt = 1003, Status = 'active' },
					{ Id = 'C', CreatedAt = 1002, Status = 'active' },
				},
				limit = 2,
				totalItems = 4,
				sortBy = 'CreatedAt',
				sortOrder = 'desc',
				nextCursor = 'C',
				hasMore = true,
			}, res)
		end)

		it('second page using cursor', function()
			local items = clone(baseItems)
			local res = utils.paginateTableWithCursor(items, 'C', 'Id', 2, nil, 'desc', nil)
			assert.are.same({
				items = {
					{ Id = 'B', CreatedAt = 1001, Status = 'inactive' },
					{ Id = 'A', CreatedAt = 1000, Status = 'active' },
				},
				limit = 2,
				totalItems = 4,
				sortBy = 'CreatedAt',
				sortOrder = 'desc',
				nextCursor = nil,
				hasMore = false,
			}, res)
		end)

		it('tie-breaker with cursorField for identical CreatedAt', function()
			local items = {
				{ Id = 'A', CreatedAt = 1000 },
				{ Id = 'B', CreatedAt = 1000 },
				{ Id = 'C', CreatedAt = 1000 },
			}
			local res1 = utils.paginateTableWithCursor(items, nil, 'Id', 2, 'CreatedAt', 'desc', nil)
			local res2 =
				utils.paginateTableWithCursor(items, res1.items[#res1.items].Id, 'Id', 2, 'CreatedAt', 'desc', nil)

			assert.are.same({
				items = {
					{ Id = 'A', CreatedAt = 1000 },
					{ Id = 'B', CreatedAt = 1000 },
				},
				limit = 2,
				totalItems = 3,
				sortBy = 'CreatedAt',
				sortOrder = 'desc',
				nextCursor = 'B',
				hasMore = true,
			}, res1)

			assert.are.same({
				items = {
					{ Id = 'C', CreatedAt = 1000 },
				},
				limit = 2,
				totalItems = 3,
				sortBy = 'CreatedAt',
				sortOrder = 'desc',
				nextCursor = nil,
				hasMore = false,
			}, res2)
		end)

		it('asc sorting by CreatedAt', function()
			local items = clone(baseItems)
			local res = utils.paginateTableWithCursor(items, nil, 'Id', 3, 'CreatedAt', 'asc', nil)
			assert.are.same({
				items = {
					{ Id = 'A', CreatedAt = 1000, Status = 'active' },
					{ Id = 'B', CreatedAt = 1001, Status = 'inactive' },
					{ Id = 'C', CreatedAt = 1002, Status = 'active' },
				},
				limit = 3,
				totalItems = 4,
				sortBy = 'CreatedAt',
				sortOrder = 'asc',
				nextCursor = 'C',
				hasMore = true,
			}, res)
		end)

		it('filters active only', function()
			local items = clone(baseItems)
			local res = utils.paginateTableWithCursor(items, nil, 'Id', 10, 'CreatedAt', 'asc', { Status = 'active' })
			assert.are.same({
				items = {
					{ Id = 'A', CreatedAt = 1000, Status = 'active' },
					{ Id = 'C', CreatedAt = 1002, Status = 'active' },
					{ Id = 'D', CreatedAt = 1003, Status = 'active' },
				},
				limit = 10,
				totalItems = 3,
				sortBy = 'CreatedAt',
				sortOrder = 'asc',
				nextCursor = nil,
				hasMore = false,
			}, res)
		end)
	end)

	describe('parsePaginationTags', function()
		local function msg(tags)
			return { Tags = tags or {} }
		end

		it('defaults applied when optional tags missing', function()
			local result = utils.parsePaginationTags(msg({}))
			assert.are.same({
				cursor = nil,
				limit = 100,
				sortBy = nil,
				sortOrder = 'desc',
				filters = nil,
			}, result)
		end)

		it('respects cursor, limit, sort order asc, sort by and filters', function()
			local result = utils.parsePaginationTags(msg({
				Cursor = 'abc',
				['Limit'] = '10',
				['Sort-Order'] = 'ASC',
				['Sort-By'] = 'CreatedAt',
				Filters = json.encode({ Status = 'active' }),
			}))
			assert.are.same({
				cursor = 'abc',
				limit = 10,
				sortBy = 'CreatedAt',
				sortOrder = 'asc',
				filters = { Status = 'active' },
			}, result)
		end)

		it('limit exceeds 1000 should assert', function()
			local ok = pcall(function()
				return utils.parsePaginationTags(msg({ ['Limit'] = '1001' }))
			end)
			assert.is_false(ok)
		end)

		it('invalid sort order should assert', function()
			local ok = pcall(function()
				return utils.parsePaginationTags(msg({ ['Sort-Order'] = 'invalid' }))
			end)
			assert.is_false(ok)
		end)

		it('invalid Filters JSON should assert', function()
			local ok = pcall(function()
				return utils.parsePaginationTags(msg({ Filters = '{invalid' }))
			end)
			assert.is_false(ok)
		end)
	end)

	describe('safeDecodeJson', function()
		local testCases = {
			{ input = nil, expected = nil, description = 'nil input returns nil' },
			{ input = '', expected = nil, description = 'empty string returns nil' },
			{ input = '{"a":1,', expected = nil, description = 'malformed JSON returns nil' },
			{
				input = json.encode({ a = 1, b = 'x' }),
				expected = { a = 1, b = 'x' },
				description = 'valid JSON object',
			},
			{ input = json.encode({ 1, 2, 3 }), expected = { 1, 2, 3 }, description = 'valid JSON array' },
			{ input = 123, expected = nil, description = 'non-string input returns nil' },
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				assert.are.same(tc.expected, utils.safeDecodeJson(tc.input))
			end)
		end
	end)

	describe('accrueFee', function()
		it('accrues fee amount', function()
			_G.AccruedFeesAmount = '100'
			utils.accrueFee('50')
			assert.are.equal('150', _G.AccruedFeesAmount)
		end)

		it('handles numeric input', function()
			_G.AccruedFeesAmount = '100'
			utils.accrueFee(75)
			assert.are.equal('175', _G.AccruedFeesAmount)
		end)

		it('ignores zero amounts', function()
			_G.AccruedFeesAmount = '100'
			utils.accrueFee('0')
			assert.are.equal('100', _G.AccruedFeesAmount)
		end)

		it('ignores negative amounts', function()
			_G.AccruedFeesAmount = '100'
			utils.accrueFee('-50')
			assert.are.equal('100', _G.AccruedFeesAmount)
		end)

	it('handles nil input', function()
		_G.AccruedFeesAmount = '100'
		---@diagnostic disable-next-line: param-type-mismatch
		utils.accrueFee(nil)
		assert.are.equal('100', _G.AccruedFeesAmount)
	end)
	end)

	describe('resetAccruedFees', function()
		it('resets fees to zero and returns old amount', function()
			_G.AccruedFeesAmount = '500'
			local amount = utils.resetAccruedFees()
			assert.are.equal('500', amount)
			assert.are.equal('0', _G.AccruedFeesAmount)
		end)

		it('works when fees are already zero', function()
			_G.AccruedFeesAmount = '0'
			local amount = utils.resetAccruedFees()
			assert.are.equal('0', amount)
			assert.are.equal('0', _G.AccruedFeesAmount)
		end)
	end)

	describe('getAccruedFees', function()
		it('returns current accrued fees', function()
			_G.AccruedFeesAmount = '250'
			assert.are.equal('250', utils.getAccruedFees())
		end)

		it('returns zero when no fees accrued', function()
			_G.AccruedFeesAmount = '0'
			assert.are.equal('0', utils.getAccruedFees())
		end)
	end)

	describe('sendFeeToTreasury', function()
		local TEST_TREASURY = 'TEST_TREASURY_ADDRESS_ABCDEFGHIJKLMNOPQRSTUVWXYZ'
		local balances = require('balances')

		it('uses internal balance for ARIO and accrues fee', function()
			_G.TREASURY_ADDRESS = TEST_TREASURY
			_G.AccruedFeesAmount = '0'
			_G.ARIOBalances[TEST_TREASURY] = {balance = '0', orders = {}}
			resetMocks()
			utils.sendFeeToTreasury('1000', '995', _G.ARIO_TOKEN_PROCESS_ID)
			-- No external transfer for ARIO
			assert.are.same({}, sentMessages)
			-- Treasury balance increased
			assert.are.equal('5', balances.getBalance(TEST_TREASURY))
			-- Fee accrued
			assert.are.equal('5', _G.AccruedFeesAmount)
		end)

		it('sends external transfer for non-ARIO tokens', function()
			_G.TREASURY_ADDRESS = TEST_TREASURY
			_G.AccruedFeesAmount = '0'
			resetMocks()
			local antToken = 'ant-token-'..(string.rep('x', 33))
			utils.sendFeeToTreasury('1000', '995', antToken)
			-- External transfer for ANT
			assert.are.equal(1, #sentMessages)
			assert.are.equal(antToken, sentMessages[1].Target)
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal(TEST_TREASURY, sentMessages[1].Tags.Recipient)
			assert.are.equal('5', sentMessages[1].Tags.Quantity)
			-- Fee accrued
			assert.are.equal('5', _G.AccruedFeesAmount)
		end)

		it('no action and no accrue when fee equals zero', function()
			_G.TREASURY_ADDRESS = TEST_TREASURY
			_G.AccruedFeesAmount = '0'
			_G.ARIOBalances[TEST_TREASURY] = {balance = '0', orders = {}}
			resetMocks()
			utils.sendFeeToTreasury('1000', '1000', _G.ARIO_TOKEN_PROCESS_ID)
			assert.are.same({}, sentMessages)
			assert.are.equal('0', balances.getBalance(TEST_TREASURY))
			assert.are.equal('0', _G.AccruedFeesAmount)
		end)

		it('no action and no accrue when fee negative', function()
			_G.TREASURY_ADDRESS = TEST_TREASURY
			_G.AccruedFeesAmount = '0'
			_G.ARIOBalances[TEST_TREASURY] = {balance = '0', orders = {}}
			resetMocks()
			utils.sendFeeToTreasury('900', '995', _G.ARIO_TOKEN_PROCESS_ID)
			assert.are.same({}, sentMessages)
			assert.are.equal('0', balances.getBalance(TEST_TREASURY))
			assert.are.equal('0', _G.AccruedFeesAmount)
		end)

		it('no action when TREASURY_ADDRESS is nil', function()
			_G.TREASURY_ADDRESS = nil
			_G.AccruedFeesAmount = '0'
			resetMocks()
			utils.sendFeeToTreasury('1000', '995', _G.ARIO_TOKEN_PROCESS_ID)
			assert.are.same({}, sentMessages)
			assert.are.equal('0', _G.AccruedFeesAmount)
		end)

		it('accrues fees additively across multiple calls', function()
			_G.TREASURY_ADDRESS = TEST_TREASURY
			_G.AccruedFeesAmount = '10'
			_G.ARIOBalances[TEST_TREASURY] = {balance = '0', orders = {}}
			resetMocks()
			utils.sendFeeToTreasury('1000', '995', _G.ARIO_TOKEN_PROCESS_ID)
			assert.are.equal('5', balances.getBalance(TEST_TREASURY))
			assert.are.equal('15', _G.AccruedFeesAmount)
			utils.sendFeeToTreasury('2000', '1990', _G.ARIO_TOKEN_PROCESS_ID)
			assert.are.equal('15', balances.getBalance(TEST_TREASURY))
			assert.are.equal('25', _G.AccruedFeesAmount)
		end)
	end)

	describe('sortTableByFields', function()
		it('primitives asc with nils at end', function()
			local input = { 3, nil, 1, 2, nil }
			local result = utils.sortTableByFields(input, { { field = nil, order = 'asc' } })
			assert.are.same({ 1, 2, 3, nil, nil }, result)
		end)

		it('primitives desc with nils at end', function()
			local input = { 3, nil, 1, 2, nil }
			local result = utils.sortTableByFields(input, { { field = nil, order = 'desc' } })
			assert.are.same({ 3, 2, 1, nil, nil }, result)
		end)

		local items = {
			{ id = 'b', value = 2 },
			{ id = 'a', value = 3 },
			{ id = 'c', value = 1 },
			{ id = 'd', value = nil },
		}

		it('single field asc with nils last', function()
			local result = utils.sortTableByFields(items, { { field = 'value', order = 'asc' } })
			assert.are.same({
				{ id = 'c', value = 1 },
				{ id = 'b', value = 2 },
				{ id = 'a', value = 3 },
				{ id = 'd', value = nil },
			}, result)
		end)

		it('single field desc with nils last', function()
			local result = utils.sortTableByFields(items, { { field = 'value', order = 'desc' } })
			assert.are.same({
				{ id = 'a', value = 3 },
				{ id = 'b', value = 2 },
				{ id = 'c', value = 1 },
				{ id = 'd', value = nil },
			}, result)
		end)

		it('nested field asc', function()
			local nested = {
				{ id = 'x', meta = { score = 10 } },
				{ id = 'y', meta = { score = 5 } },
				{ id = 'z', meta = { score = 20 } },
			}
			local result = utils.sortTableByFields(nested, { { field = 'meta.score', order = 'asc' } })
			assert.are.same({
				{ id = 'y', meta = { score = 5 } },
				{ id = 'x', meta = { score = 10 } },
				{ id = 'z', meta = { score = 20 } },
			}, result)
		end)

		it('multiple fields (a asc, then b asc, then id asc)', function()
			local multi = {
				{ id = 'b', a = 1, b = 2 },
				{ id = 'a', a = 1, b = 1 },
				{ id = 'c', a = 1, b = 2 },
				{ id = 'd', a = 2, b = 1 },
			}
			local result = utils.sortTableByFields(multi, {
				{ field = 'a', order = 'asc' },
				{ field = 'b', order = 'asc' },
				{ field = 'id', order = 'asc' },
			})
			assert.are.same({
				{ id = 'a', a = 1, b = 1 },
				{ id = 'b', a = 1, b = 2 },
				{ id = 'c', a = 1, b = 2 },
				{ id = 'd', a = 2, b = 1 },
			}, result)
		end)

		it('invalid order should error', function()
			local ok = pcall(function()
				utils.sortTableByFields(items, { { field = 'value', order = 'invalid' } })
			end)
			assert.is_false(ok)
		end)
	end)

	describe('validateArioInTrade', function()
		local TEST_ARIO_ID = 'TEST_ARIO_PROCESS_ID_ABCDEFGHIJKLMNOPQRSTUVWXYZ'

		before_each(function()
			_G.ARIO_TOKEN_PROCESS_ID = TEST_ARIO_ID
		end)

		local testCases = {
			{
				dominant = TEST_ARIO_ID,
				swap = 'OTHER_TOKEN',
				expected = { true, nil },
				description = 'dominant token is ARIO',
			},
			{
				dominant = 'OTHER_TOKEN',
				swap = TEST_ARIO_ID,
				expected = { true, nil },
				description = 'swap token is ARIO',
			},
			{
				dominant = TEST_ARIO_ID,
				swap = TEST_ARIO_ID,
				expected = { true, nil },
				description = 'both tokens are ARIO',
			},
			{
				dominant = 'TOKEN_A',
				swap = 'TOKEN_B',
				expected = { false, 'At least one token in the trade must be ARIO' },
				description = 'neither token is ARIO',
			},
			{
				dominant = nil,
				swap = TEST_ARIO_ID,
				expected = { true, nil },
				description = 'nil dominant but ARIO in swap',
			},
		}

		for _, tc in ipairs(testCases) do
			it('should return ' .. (tc.expected[1] and 'success' or 'failure') .. ' when ' .. tc.description, function()
				local ok, err = utils.validateArioInTrade(tc.dominant, tc.swap)
				assert.are.equal(tc.expected[1], ok)
				assert.are.equal(tc.expected[2], err)
			end)
		end
	end)

	describe('validatePairData', function()
		local ANT = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
		local ARIO = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'

		local testCases = {
			{
				description = 'valid pair of two distinct addresses',
				input = { ANT, ARIO },
				expected = { result = { ANT, ARIO } },
			},
			{
				description = 'input not a 2-element list',
				input = { ANT },
				expected = { result = nil, error = 'Pair must be a list of exactly two strings - [TokenId, TokenId]' },
			},
			{
				description = 'elements are not strings',
				input = { 123, false },
				expected = { result = nil, error = 'Both pair elements must be strings' },
			},
			{
				description = 'elements are invalid addresses',
				input = { 'not_an_address', 'also_not_valid' },
				expected = { result = nil, error = 'Both pair elements must be valid addresses' },
			},
			{
				description = 'addresses cannot be equal',
				input = { ANT, ANT },
				expected = { result = nil, error = 'Pair addresses cannot be equal' },
			},
		}

		for _, tc in ipairs(testCases) do
			it(tc.description, function()
				local res, err = utils.validatePairData(tc.input)
				assert.are.same(tc.expected.result, res)
				assert.are.equal(tc.expected.error, err)
			end)
		end
	end)

	describe('camelCase', function()
		it('should convert snake_case to camelCase', function()
			assert.are.equal(utils.camelCase('start_end'), 'startEnd')
			assert.are.equal(utils.camelCase('multiple_words_example'), 'multipleWordsExample')
		end)

		it('should convert kebab-case to camelCase', function()
			assert.are.equal(utils.camelCase('start-end'), 'startEnd')
			assert.are.equal(utils.camelCase('multiple-words-example'), 'multipleWordsExample')
		end)

		it('should convert space-separated words to camelCase', function()
			assert.are.equal(utils.camelCase('start end'), 'startEnd')
			assert.are.equal(utils.camelCase('multiple words example'), 'multipleWordsExample')
		end)

		it('should convert PascalCase to camelCase', function()
			assert.are.equal(utils.camelCase('StartEnd'), 'startEnd')
			assert.are.equal(utils.camelCase('MultipleWordsExample'), 'multipleWordsExample')
		end)

		it('should handle mixed cases', function()
			assert.are.equal(utils.camelCase('Start_end-Test'), 'startEndTest')
			assert.are.equal(utils.camelCase('Multiple_Words-example Test'), 'multipleWordsExampleTest')
		end)

		it('should handle already camelCase strings', function()
			assert.are.equal(utils.camelCase('startEnd'), 'startEnd')
			assert.are.equal(utils.camelCase('multipleWordsExample'), 'multipleWordsExample')
		end)

		it('should handle single character strings', function()
			assert.are.equal(utils.camelCase('a'), 'a')
			assert.are.equal(utils.camelCase('A'), 'a')
		end)

		it('should handle empty strings', function()
			assert.are.equal(utils.camelCase(''), '')
		end)
	end)

	describe('isValidEthAddress', function()
		local testEthAddress = '0xFCAd0B19bB29D4674531d6f115237E16AfCE377c'

		it('should validate eth address', function()
			assert.is_true(utils.isValidEthAddress(testEthAddress))
		end)

		it('should fail on non-hexadecimal character', function()
			-- invalid non-hexadecimal G character
			assert.is_false(utils.isValidEthAddress('0xFCAd0B19bB29D4674531d6f115237E16AfCE377G'))
		end)

		it('should return false on an invalid-length address', function()
			assert.is_false(utils.isValidEthAddress('0xFCAd0B19bB29D4674531d6f115237E16AfCE37'))
		end)

	it('should return false on passing in non-string value', function()
		---@diagnostic disable-next-line: param-type-mismatch
		assert.is_false(utils.isValidEthAddress(3))
	end)
	end)

	describe('isValidArweaveAddress', function()
		it('should return false for invalid Arweave IDs', function()
			local invalid = utils.isValidArweaveAddress('invalid-arweave-id-123')
			assert.is_false(invalid)
		end)

		it('should return true for a valid Arweave ID', function()
			local valid = utils.isValidArweaveAddress('0E7Ai_rEQ326_vLtgB81XHViFsLlcwQNqlT9ap24uQI')
			assert.is_true(valid)
		end)

		it('should return false for addresses that are too short', function()
			assert.is_false(utils.isValidArweaveAddress('shortaddress'))
		end)

		it('should return false for addresses that are too long', function()
			assert.is_false(utils.isValidArweaveAddress('ThisAddressIsWayTooLongToBeAValidArweaveAddress123'))
		end)

	it('should return false for nil', function()
		---@diagnostic disable-next-line: param-type-mismatch
		assert.is_false(utils.isValidArweaveAddress(nil))
	end)
	end)

	describe('isValidAOAddress', function()
		local testEthAddress = '0xFCAd0B19bB29D4674531d6f115237E16AfCE377c'

		it('should return false for invalid Arweave IDs', function()
			local invalid = utils.isValidAOAddress('invalid-arweave-id-123', false)
			assert.is_false(invalid)
		end)

		it('should return true for a valid Arweave ID', function()
			local valid = utils.isValidAOAddress('0E7Ai_rEQ326_vLtgB81XHViFsLlcwQNqlT9ap24uQI', false)
			assert.is_true(valid)
		end)

		it('should validate eth address', function()
			assert.is_true(utils.isValidAOAddress(testEthAddress, false))
		end)

		it('should return false for nil without allowUnsafe', function()
			assert.is_false(utils.isValidAOAddress(nil, false))
		end)

		it('should return false for nil with allowUnsafe', function()
			assert.is_false(utils.isValidAOAddress(nil, true))
		end)

		it('should allow unsafe addresses when allowUnsafe is true', function()
			assert.is_true(utils.isValidAOAddress('short', true))
			assert.is_true(utils.isValidAOAddress('medium_length_address', true))
			assert.is_true(utils.isValidAOAddress(string.rep('a', 128), true))
		end)

		it('should reject invalid unsafe addresses even when allowUnsafe is true', function()
			assert.is_false(utils.isValidAOAddress('has spaces', true))
			assert.is_false(utils.isValidAOAddress('has@special', true))
			assert.is_false(utils.isValidAOAddress(string.rep('a', 129), true)) -- too long
		end)
	end)

	describe('formatEIP55Address', function()
		it('should format Ethereum addresses to EIP-55 checksum format', function()
			-- Test with known checksummed address
			local lowercase = '0xfcad0b19bb29d4674531d6f115237e16afce377c'
			local checksummed = utils.formatEIP55Address(lowercase)
			assert.are.equal('0xFCAd0B19bB29D4674531d6f115237E16AfCE377c', checksummed)
		end)

		it('should handle already checksummed addresses', function()
			local checksummed = '0xFCAd0B19bB29D4674531d6f115237E16AfCE377c'
			local result = utils.formatEIP55Address(checksummed)
			assert.are.equal(checksummed, result)
		end)
	end)

	describe('formatAddress', function()
		it('should format Ethereum addresses to EIP-55', function()
			local ethAddress = '0xfcad0b19bb29d4674531d6f115237e16afce377c'
			local formatted = utils.formatAddress(ethAddress)
			assert.are.equal('0xFCAd0B19bB29D4674531d6f115237E16AfCE377c', formatted)
		end)

		it('should not modify Arweave addresses', function()
			local arweaveAddress = '0E7Ai_rEQ326_vLtgB81XHViFsLlcwQNqlT9ap24uQI'
			local formatted = utils.formatAddress(arweaveAddress)
			assert.are.equal(arweaveAddress, formatted)
		end)

		it('should not modify invalid addresses', function()
			local invalidAddress = 'invalid-address'
			local formatted = utils.formatAddress(invalidAddress)
			assert.are.equal(invalidAddress, formatted)
		end)
	end)

	describe('splitString', function()
		it('should split by default comma delimiter', function()
			local result = utils.splitString('a,b,c')
			assert.are.same({ 'a', 'b', 'c' }, result)
		end)

		it('should split by custom delimiter', function()
			local result = utils.splitString('a|b|c', '|')
			assert.are.same({ 'a', 'b', 'c' }, result)
		end)

	it('should handle empty string', function()
		---@diagnostic disable-next-line: param-type-mismatch
		local result = utils.splitString('')
		assert.are.same({}, result)
	end)

	it('should handle nil string', function()
		---@diagnostic disable-next-line: param-type-mismatch
		local result = utils.splitString(nil)
		assert.are.same({}, result)
	end)

		it('should handle string with no delimiters', function()
			local result = utils.splitString('single')
			assert.are.same({ 'single' }, result)
		end)

		it('should handle multiple consecutive delimiters', function()
			local result = utils.splitString('a,,b')
			-- Note: consecutive delimiters create empty strings in between
			assert.is_true(#result >= 2)
		end)
	end)

	describe('keys', function()
		it('should extract all keys from a table', function()
			local t = { a = 1, b = 2, c = 3 }
			local keys = utils.keys(t)
			table.sort(keys)
			assert.are.same({ 'a', 'b', 'c' }, keys)
		end)

		it('should handle empty table', function()
			local keys = utils.keys({})
			assert.are.same({}, keys)
		end)

	it('should handle array-like tables', function()
		local t = { 'a', 'b', 'c' }
		local keys = utils.keys(t)
		---@diagnostic disable-next-line: param-type-mismatch
		table.sort(keys)
		assert.are.same({ 1, 2, 3 }, keys)
	end)

	it('should throw error for non-table argument', function()
		assert.has_error(function()
			---@diagnostic disable-next-line: param-type-mismatch
			utils.keys('not a table')
		end, 'argument needs to be a table')
	end)
	end)
end)
