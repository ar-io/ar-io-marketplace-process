allow_defined = true
globals = {
	'Handlers',
	'ao',
}
max_line_length = 185

-- Enable unused variable checks
unused = true -- Warn on unused variables
unused_args = true -- Warn on unused function arguments
unused_secondaries = true -- Warn on unused secondary values in parallel assignments

-- Note: By default, luacheck ignores variables starting with _
-- Use _ prefix for intentionally unused variables (e.g., _unused, _arg)
