import { ARIO, ANT, AOProcess, ArNSMarketplaceWrite, ANTRegistry, ARIO_MAINNET_PROCESS_ID, createAoSigner, ANT_REGISTRY_ID, AoANTInfo } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { TEST_SIGNER } from '../tests/utils/constants.js';
import plimit from 'p-limit'
import kleur from 'kleur';
import ora, { type Ora } from 'ora';

type AntIssue = {
	notInAntRegistry?: boolean;
	isOrder?: boolean;
	isIntent?: boolean;
	badCu?: {
		error: boolean;
		cuName: string;
		status: number;
		statusText: string;
	};
	unknownError?: unknown;
	notOwnedByMarketplace?: {
		owner: string | undefined;
	};
	escrowIssue?: 
		| 'intent active but no credit-notice to marketplace'
		| 'order active but is not owned by the marketplace process';
	cuStatus?: {
		error: boolean;
		cuName: string;
		status: number;
		statusText: string;
		antId: string;
	}
};

const concurrencyLimit = plimit(10);
const paginationLimit = 1000;

// Open question:
// How do we validate ants owned by the marketplace process, but aren't in the orderbook, intents, or ant registry? i.e, transfer happened but no cranks happened and intent expired.

/**
 * Potential issues:
 * - Ant is not in the ant registry
 * - Ant is not owned by the marketplace process
 * - Ant is not in the orderbook
 * - Ant is not in the intents
 * - Ant is not in the ant registry
 * - Ant is not in the orderbook
 * - Ant is not in the intents
 * - Ant is not in the ant registry
 */


const cuUrl = 'https://cu.ardrive.io';
const aoTestnetCuUrl = 'https://cu.ao-testnet.xyz';
const arioProcessId = ARIO_MAINNET_PROCESS_ID;
const marketplaceProcessId = 'ijCygKzV48PHx_TUdFN7NNJgbBUatQDL_h8FfqVzXfE';
const antRegistryProcessId = ANT_REGISTRY_ID;

const aoClient = connect({
	CU_URL: cuUrl,
	MODE: 'legacy'
})

const ario = ARIO.init({
	process: new AOProcess({
		processId: arioProcessId,
		ao: aoClient,
	})
});

const marketplace = new ArNSMarketplaceWrite({
	ario: ario as any,
	process: new AOProcess({
		processId: marketplaceProcessId,
		ao: aoClient,
	}),
	signer: createAoSigner(TEST_SIGNER)
});
const antRegistry = ANTRegistry.init({
	process: new AOProcess({
		processId: antRegistryProcessId,
		ao: aoClient,
	}),
	signer: createAoSigner(TEST_SIGNER)
})

async function getAllOrders() {

	let cursor = undefined;
	const orders = [];
	while (true) {
		const result = await marketplace.getPaginatedOrders({cursor, limit: paginationLimit});
		orders.push(...result.items);
		if (!result.hasMore) break;
		cursor = result.nextCursor;
	}
	return orders;
}
async function getAllIntents() {
	let cursor = undefined;
	const intents = [];
	while (true) {
		const result = await marketplace.getPaginatedIntents({cursor, limit: paginationLimit});
		intents.push(...result.items);
		if (!result.hasMore) break;
		cursor = result.nextCursor;
	}
	return intents;
}

async function getAllTransfersOutOffMarketplaceFromPruning() {
	const res = await aoClient.dryrun({
		process: marketplaceProcessId,
		tags: [
			{name: "Action", value: "Info"}
		],
	})
	const [infoNotice, ...maybeTransferOuts] = res.Messages;
	const transferOuts = (maybeTransferOuts || []).filter(msg => msg.Tags.find((tag: any) => tag.name === "Action")?.value === "Transfer");
	return {info: infoNotice, transfers: transferOuts};
}

async function getANTInfo(antId: string): Promise<{error: unknown | null, info: AoANTInfo | null, antId: string}> {
	try {
		const ant = ANT.init({
			process: new AOProcess({
				processId: antId,
				ao: aoClient,
			})
		})
		const infoResult = await ant.getInfo();
		return {error: null, info: infoResult, antId};
	} catch (error) {
		return {error, info: null,antId};
	}
}

		async function checkCuStatus(antId: string): Promise<{error: boolean, cuName: string, status: number, statusText: string, antId: string}> {
		const res = await fetch(`${aoTestnetCuUrl}/state/${antId}`, {method: 'HEAD', redirect: 'follow'});
		const resolvedUrl = res.url;
		const cuName = resolvedUrl.split('.')[0].replace('https://', '');

		if (res.status.toString().startsWith('4') || res.status.toString().startsWith('5')) {
			return {error: true, cuName, status: res.status, statusText: res.statusText, antId};
		}
		return {error: false, cuName, status: res.status, statusText: res.statusText, antId};
	}
async function observeMarketplaceState() {
	const spinner = ora('Fetching marketplace state...').start();

	spinner.text = 'Fetching transfers from pruning...';
	const {transfers} = await getAllTransfersOutOffMarketplaceFromPruning();
	spinner.succeed(`Found ${transfers.length} transfers out of the marketplace in the last pruning`);

	spinner.start('Fetching ANTs owned by marketplace...');
	const ants = await antRegistry.accessControlList({address: marketplaceProcessId});
	spinner.succeed(`Found ${ants.Owned.length} ants owned by the marketplace process`);

	spinner.start('Fetching marketplace orders...');
	const orders = await getAllOrders();
	spinner.succeed(`Found ${orders.length} orders in the marketplace`);

	spinner.start('Fetching marketplace intents...');
	const intents = await getAllIntents();
	spinner.succeed(`Found ${intents.length} intents in the marketplace`);
	
	const antRegistryOwnedAnts = new Set<string>(ants.Owned);
	const aggregatedAntIds = new Set<string>(ants.Owned.concat(ants.Controlled));
	const antsWithActiveMarketplaceOrders = new Set<string>(orders.map(order => order.dominantToken));
	const antsWithActiveMarketplaceIntents = new Set<string>(intents.map(intent => intent.antProcessId));
	// Track issues with ants here
	const antIssueMapping = new Map<string, AntIssue>();

	// map intents and orders to ants
	for (const order of orders) {
		aggregatedAntIds.add(order.dominantToken);
		if (!antRegistryOwnedAnts.has(order.dominantToken)) {
			antIssueMapping.set(order.dominantToken, {...antIssueMapping.get(order.dominantToken), notInAntRegistry: true,});
			antIssueMapping.set(order.dominantToken, {...antIssueMapping.get(order.dominantToken), isOrder: true,});
		}
	}
	for (const intent of intents) {
		aggregatedAntIds.add(intent.antProcessId);
		if (!antRegistryOwnedAnts.has(intent.antProcessId)) {
			antIssueMapping.set(intent.antProcessId, {...antIssueMapping.get(intent.antProcessId), notInAntRegistry: true});
			antIssueMapping.set(intent.antProcessId, {...antIssueMapping.get(intent.antProcessId), isIntent: true,});
		}
	}

	// check for cu status of the ants
	spinner.start(`Checking CU status for ${aggregatedAntIds.size} ANTs...`);
	const cuStatusResults = await Promise.all(Array.from(aggregatedAntIds).map(antId => concurrencyLimit(() => checkCuStatus(antId))));
	spinner.succeed(`Checked CU status for ${aggregatedAntIds.size} ANTs`);
	const cuStatusResultsMap = new Map<string, {error: boolean, cuName: string, status: number, statusText: string, antId: string}>()

	for (const result of cuStatusResults) {
		cuStatusResultsMap.set(result.antId, result);
		if (result.error) {
			const {antId, ...rest} = result;
			antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), badCu: rest});
		}
		if (antIssueMapping.get(result.antId)) {
			antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), cuStatus: result});
		}
	}

	// for ant's that are in the registry but not in the order book, this indicates a potential escrow issue - note, if pruning happened during the read, this could be a false positive
	// so we should check on transfers out of the marketplace on an initial read and filter those out.
	const transferToIds = transfers.map(transfer => transfer.Tags.find((tag: any) => tag.name === "Recipient")?.value);
	const registryOwnedAnts = Array.from(antRegistryOwnedAnts);
	const antsToCheckOwnershipOf = registryOwnedAnts.filter(antId => !transferToIds.includes(antId) && !cuStatusResultsMap.get(antId)?.error);

	spinner.start(`Checking ownership of ${antsToCheckOwnershipOf.length} ANTs...`);
	const antInfoResults = await Promise.all(antsToCheckOwnershipOf.map(antId => concurrencyLimit(() => getANTInfo(antId))));
	spinner.succeed(`Checked ownership of ${antsToCheckOwnershipOf.length} ANTs`);

	for (const result of antInfoResults) {
		if (result.error) {		
			antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), unknownError: result.error});
			continue;
		}
		if (result.info?.Owner !== marketplaceProcessId) {
			antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), notOwnedByMarketplace: {owner: result.info?.Owner}});
			// if the ant is not owned by the marketplace process but there is an intent for it, this indicates the ant was transferred to the marketplace but the credit-notice was not received
			if (antsWithActiveMarketplaceIntents.has(result.antId)) {
				// TODO: this might get noisy, should probably only log if the intent is older than a certain threshold
				antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), escrowIssue: "intent active but no credit-notice to marketplace"});
			}
			// ant has an active order but is not owned by the marketplace process
			if (antsWithActiveMarketplaceOrders.has(result.antId)) {
				antIssueMapping.set(result.antId, {...antIssueMapping.get(result.antId), escrowIssue: "order active but is not owned by the marketplace process"});
			}
			continue;
		}
	}

	if (antIssueMapping.size > 0) {
		spinner.warn(`Found ${antIssueMapping.size} ANTs with issues`);
		console.log(kleur.yellow(JSON.stringify(Array.from(antIssueMapping.entries()).map(([antId, issue]) => ({antId, ...issue})), null, 2)));
	} else {
		spinner.succeed('No ANT issues found');
	}




	// create report with the following information:
	// - ants that are owned by the marketplace process but not in the orderbook or intents - these are problem ants that need to be investigated
	// - investigate the state of the ant, search for the most recent transfer to the marketplace process
	// - get the cu number the ant is on and do a head request to check if the cu is bad
	// - use the cranking verifier 
}
observeMarketplaceState();