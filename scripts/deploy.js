import { FoundryDeployer } from "@adraffy/blocksmith";
import { createInterface } from "node:readline/promises";
import { ENS_REGISTRY, BASE_VERIFIER } from "../test/config.js";

const rl = createInterface({
	input: process.stdin,
	output: process.stdout,
});

const deployer = await FoundryDeployer.load({
	privateKey: await rl.question("Private Key (empty to simulate): "),
});

const deployable = await deployer.prepare({
	file: "TeamNickResolver",
	args: [ENS_REGISTRY, BASE_VERIFIER],
});

if (deployer.privateKey) {
	await rl.question("Ready? (abort to stop) ");
	await deployable.deploy();
	const apiKey = await rl.question("Etherscan API Key: ");
	if (apiKey) {
		await deployable.verifyEtherscan({ apiKey });
	}
}
rl.close();
