import { ARIO, ANT, AOProcess, ArNSMarketplaceWrite, ANTRegistry, ARIO_MAINNET_PROCESS_ID, createAoSigner, ANT_REGISTRY_ID, AoANTInfo } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { TEST_SIGNER } from '../tests/utils/constants.js';
import plimit from 'p-limit'
import kleur from 'kleur';
import ora, { type Ora } from 'ora';

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;

type SlackBlock = {
	type: string;
	text?: { type: string; text: string; emoji?: boolean };
	fields?: { type: string; text: string }[];
};

async function sendSlackNotification(issues: Array<{ antId: string } & AntIssue>): Promise<void> {
	if (!SLACK_WEBHOOK_URL) {
		console.log(kleur.yellow('SLACK_WEBHOOK_URL not set, skipping Slack notification'));
		return;
	}

	const blocks: SlackBlock[] = [
		{
			type: 'header',
			text: {
				type: 'plain_text',
				text: issues.length > 0 ? '⚠️ Marketplace ANT Issues Detected' : '✅ Marketplace State Healthy',
				emoji: true,
			},
		},
		{
			type: 'section',
			text: {
				type: 'mrkdwn',
				text: `*Marketplace Process:* \`${marketplaceProcessId}\`\n*Timestamp:* ${new Date().toISOString()}`,
			},
		},
	];

	if (issues.length > 0) {
		blocks.push({
			type: 'section',
			text: {
				type: 'mrkdwn',
				text: `*Total Issues Found:* ${issues.length}`,
			},
		});

		// Group issues by type for summary
		const issuesByType = {
			notInAntRegistry: issues.filter(i => i.notInAntRegistry).length,
			badCu: issues.filter(i => i.badCu).length,
			notOwnedByMarketplace: issues.filter(i => i.notOwnedByMarketplace).length,
			escrowIssue: issues.filter(i => i.escrowIssue).length,
			unknownError: issues.filter(i => i.unknownError).length,
		};

		blocks.push({
			type: 'section',
			fields: [
				{ type: 'mrkdwn', text: `*Not in Registry:* ${issuesByType.notInAntRegistry}` },
				{ type: 'mrkdwn', text: `*Bad CU:* ${issuesByType.badCu}` },
				{ type: 'mrkdwn', text: `*Not Owned by Marketplace:* ${issuesByType.notOwnedByMarketplace}` },
				{ type: 'mrkdwn', text: `*Escrow Issues:* ${issuesByType.escrowIssue}` },
				{ type: 'mrkdwn', text: `*Unknown Errors:* ${issuesByType.unknownError}` },
			],
		});

		// Add details for first few issues (limit to avoid message size issues)
		const maxDetailsToShow = 5;
		const issuesToShow = issues.slice(0, maxDetailsToShow);
		
		for (const issue of issuesToShow) {
			const issueDetails: string[] = [];
			if (issue.notInAntRegistry) issueDetails.push('Not in registry');
			if (issue.badCu) issueDetails.push(`Bad CU (${issue.badCu.cuName}: ${issue.badCu.status})`);
			if (issue.notOwnedByMarketplace) issueDetails.push(`Not owned by marketplace (owner: <${SCAN_URL}/${issue.notOwnedByMarketplace.owner}|${issue.notOwnedByMarketplace.owner?.slice(0, 8)}...>)`);
			if (issue.escrowIssue) issueDetails.push(`Escrow: ${issue.escrowIssue}`);
			if (issue.unknownError) issueDetails.push('Unknown error');
			if (issue.hasAssociatedArNSName === false) issueDetails.push('No associated ArNS name');

			const arnsLabel = issue.arnsName ? ` (${issue.arnsName})` : '';
			const antLink = `<${SCAN_URL}/${issue.antId}|${issue.antId.slice(0, 8)}...${arnsLabel}>`;

			blocks.push({
				type: 'section',
				text: {
					type: 'mrkdwn',
					text: `*ANT:* ${antLink}\n${issueDetails.join(', ')}`,
				},
			});
		}

		if (issues.length > maxDetailsToShow) {
			blocks.push({
				type: 'section',
				text: {
					type: 'mrkdwn',
					text: `_...and ${issues.length - maxDetailsToShow} more issues_`,
				},
			});
		}
	}

	const payload = {
		blocks,
		text: issues.length > 0 
			? `⚠️ Marketplace ANT Issues: ${issues.length} issues detected` 
			: '✅ Marketplace State Healthy',
	};

	const response = await fetch(SLACK_WEBHOOK_URL, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(payload),
	});

	if (!response.ok) {
		throw new Error(`Failed to send Slack notification: ${response.status} ${response.statusText}`);
	}
}

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
	};
	hasAssociatedArNSName?: boolean;
	arnsName?: string;
};

const SCAN_URL = 'https://scan.ar.io/#/entity';

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

	// Query ArNS records for ANTs with issues to get associated names
	const antIdsWithIssues = Array.from(antIssueMapping.keys());
	if (antIdsWithIssues.length > 0) {
		spinner.start(`Looking up ArNS names for ${antIdsWithIssues.length} ANTs with issues...`);
		try {
			const arnsRecords = await ario.getArNSRecords({filters: { processId: antIdsWithIssues }});
			const processIdToArnsName = new Map<string, string>();
			
			// Build a map of processId -> arnsName
			for (const record of arnsRecords.items) {
				processIdToArnsName.set(record.processId, record.name);
			}

			// Update issue mapping with ArNS name info
			for (const antId of antIdsWithIssues) {
				const arnsName = processIdToArnsName.get(antId);
				if (arnsName) {
					antIssueMapping.set(antId, {...antIssueMapping.get(antId), hasAssociatedArNSName: true, arnsName});
				} else {
					antIssueMapping.set(antId, {...antIssueMapping.get(antId), hasAssociatedArNSName: false});
				}
			}
			spinner.succeed(`Found ArNS names for ${processIdToArnsName.size} of ${antIdsWithIssues.length} ANTs`);
		} catch (error) {
			spinner.fail(`Failed to lookup ArNS names: ${error}`);
		}
	}

	const issues = Array.from(antIssueMapping.entries()).map(([antId, issue]) => ({antId, ...issue}));

	if (issues.length > 0) {
		spinner.warn(`Found ${issues.length} ANTs with issues`);
		console.log(kleur.yellow(JSON.stringify(issues, null, 2)));
	} else {
		spinner.succeed('No ANT issues found');
	}

	// Send Slack notification
	spinner.start('Sending Slack notification...');
	try {
		await sendSlackNotification(issues);
		spinner.succeed('Slack notification sent');
	} catch (error) {
		spinner.fail(`Failed to send Slack notification: ${error}`);
	}
}
observeMarketplaceState();