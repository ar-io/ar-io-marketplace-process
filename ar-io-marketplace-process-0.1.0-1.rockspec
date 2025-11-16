package = "ar-io-marketplace-process"
version = "0.1.0-1"

description = {
  summary = "ARnS Marketplace AO process modules",
  detailed = [[
ARnS Marketplace process implementation for AO. This rock provides the core
Lua modules used to run the marketplace, including order management, activity
tracking, auctions, and utilities.
  ]],
  homepage = "https://arns.app/#/listings",
  license = "MIT",
}

source = {
  url = "."
}

dependencies = {
  "lua = 5.3",
  "busted >= 2.0.0",
  "luacov >= 0.15.0"
}

build = {
  type = "builtin",
  modules = {
    ["dutch_auction"] = "src/dutch_auction.lua",
    ["english_auction"] = "src/english_auction.lua",
    ["fixed_price"] = "src/fixed_price.lua",
    ["process"] = "src/process.lua",
    ["ucm"] = "src/ucm.lua",
    ["utils"] = "src/utils.lua",
  }
}
