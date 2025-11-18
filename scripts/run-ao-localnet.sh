pnpm exec ao-localnet configure     # generate wallets and download AOS module
pnpm exec ao-localnet start         # run Docker containers (build them if necessary)
pnpm exec ao-localnet seed          # seed AOS and Scheduler info into the localnet
pnpm exec ao-localnet spawn "name"  # spawn AOS process with correction Authority tag
pnpm exec ao-localnet aos "name"    # connect to the new AOS process by name
