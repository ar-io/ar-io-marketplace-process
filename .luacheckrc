allow_defined = true
globals = {
	'Handlers',
	'ao',
}
max_line_length = 185

-- Exclude bundled fixture contracts from linting
exclude_files = {
	'tests/fixtures/contracts/**',
}

-- Enable unused variable checks
unused = true -- Warn on unused variables
unused_args = true -- Warn on unused function arguments
unused_secondaries = true -- Warn on unused secondary values in parallel assignments

-- Enable redefined local variable checks
-- Note: Luacheck will return exit code 1 (fail) when warnings are found,
-- effectively treating redefined locals as errors in CI/CD pipelines
redefined = true -- Detect when a local variable is redefined in the same scope (W411, W412)

-- Note: By default, luacheck ignores variables starting with _
-- Use _ prefix for intentionally unused variables (e.g., _unused, _arg)
